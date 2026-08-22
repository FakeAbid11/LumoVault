import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../gallery/data/models/media_item.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../core/di/tdlib_providers.dart';
import '../../../../core/di/transfer_providers.dart';
import '../../../restore/presentation/providers/restore_providers.dart';
import '../../data/repositories/channel_update_listener.dart';
import '../../data/repositories/conflict_resolver.dart';
import '../../data/repositories/manifest_persistence.dart';
import '../../data/repositories/manifest_service.dart';
import '../../data/repositories/metadata_integration.dart';
import '../../data/repositories/metadata_repository.dart';
import '../../data/repositories/metadata_sync_coordinator.dart';
import '../../data/repositories/migration_service.dart';
import '../../data/repositories/partition_persistence.dart';
import '../../data/repositories/partition_service.dart';
import '../../data/repositories/search_index_service.dart';
import '../../data/repositories/sync_log_persistence.dart';
import '../../data/repositories/sync_service.dart';
import '../../data/repositories/telegram_metadata_downloader.dart';
import '../../data/repositories/telegram_metadata_uploader.dart';

/// Manifest persistence provider (JSON file in app documents).
final manifestStoreProvider = Provider<ManifestStore>((ref) {
  return FileManifestStore();
});

/// Partition persistence provider (JSON file in app documents).
final partitionStoreProvider = Provider<PartitionStore>((ref) {
  return FilePartitionStore();
});

/// Manifest service provider.
final manifestServiceProvider = Provider<ManifestService>((ref) {
  final service = ManifestService(store: ref.watch(manifestStoreProvider));
  ref.onDispose(() => service.dispose());
  return service;
});

/// Partition service provider.
final partitionServiceProvider = Provider<PartitionService>((ref) {
  final service = PartitionService(store: ref.watch(partitionStoreProvider));
  ref.onDispose(() => service.dispose());
  return service;
});

/// Search index service provider.
final searchIndexServiceProvider = Provider<SearchIndexService>((ref) {
  final service = SearchIndexService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Sync service provider.
///
/// Wired with the on-disk log store so the sync log survives restarts; unit
/// tests construct [SyncService] bare and stay memory-only.
final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(logStore: FileSyncLogStore());
  ref.onDispose(() => service.dispose());
  return service;
});

/// Conflict resolver provider.
final conflictResolverProvider = Provider<ConflictResolver>((ref) {
  return ConflictResolver();
});

/// Migration service provider.
final migrationServiceProvider = Provider<MigrationService>((ref) {
  final service = MigrationService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Core metadata repository provider.
final metadataRepositoryProvider = Provider<MetadataRepository>((ref) {
  final repo = MetadataRepository(
    manifestService: ref.watch(manifestServiceProvider),
    partitionService: ref.watch(partitionServiceProvider),
    searchIndexService: ref.watch(searchIndexServiceProvider),
    syncService: ref.watch(syncServiceProvider),
    conflictResolver: ref.watch(conflictResolverProvider),
  );
  ref.onDispose(() => repo.dispose());
  return repo;
});

/// Installs the metadata write callback on GalleryRepository.
///
/// Must be read once during app bootstrap — constructing this provider is what
/// wires gallery mutations (scan, favorite, trash, delete, ...) through to the
/// metadata layer. Without it, GalleryRepository's change callback stays null
/// and nothing reaches MetadataRepository.
final metadataIntegrationProvider = Provider<MetadataIntegration>((ref) {
  final integration = MetadataIntegration(
    metadataRepository: ref.watch(metadataRepositoryProvider),
  );
  integration.connectGalleryRepository(ref.watch(galleryRepositoryProvider));
  return integration;
});

/// Uploads manifest/partition JSON to the storage channel as documents.
final telegramMetadataUploaderProvider = Provider<TelegramMetadataUploader>((
  ref,
) {
  return TelegramMetadataUploader(
    uploadService: ref.watch(uploadServiceProvider),
    storageChannelService: ref.watch(storageChannelServiceProvider),
  );
});

/// Downloads + parses the remote manifest/partition documents — the pull half
/// of two-way sync, symmetric to [telegramMetadataUploaderProvider].
final telegramMetadataDownloaderProvider = Provider<TelegramMetadataDownloader>(
  (ref) {
    return TelegramMetadataDownloader(
      client: ref.watch(tdLibClientProvider),
      downloadService: ref.watch(downloadServiceProvider),
      storageChannelService: ref.watch(storageChannelServiceProvider),
    );
  },
);

/// Drives the metadata sync layer: makes sure a manifest exists, then uploads
/// dirty partitions and the manifest to Telegram.
///
/// Must be read once during app bootstrap so the 'sync_pending' listener is
/// attached in the UI isolate — that is what makes ordinary gallery mutations
/// reach Telegram automatically after the debounced flush.
final metadataSyncCoordinatorProvider = Provider<MetadataSyncCoordinator>((
  ref,
) {
  final coordinator = MetadataSyncCoordinator(
    metadataRepository: ref.watch(metadataRepositoryProvider),
    uploader: ref.watch(telegramMetadataUploaderProvider),
    downloader: ref.watch(telegramMetadataDownloaderProvider),
  );
  ref.onDispose(() => coordinator.dispose());
  return coordinator;
});

/// Live channel subscription: watches TDLib updates and fires a debounced pull
/// when the storage channel changes (another device, or another Telegram
/// client). Must be read once at bootstrap — like
/// [metadataSyncCoordinatorProvider] — so the subscription is attached in the
/// UI isolate. [ChannelUpdateListener.start] is called here.
final channelUpdateListenerProvider = Provider<ChannelUpdateListener>((ref) {
  final listener = ChannelUpdateListener(
    updates: ref.watch(tdLibClientProvider).updates,
    coordinator: ref.watch(metadataSyncCoordinatorProvider),
    uploader: ref.watch(telegramMetadataUploaderProvider),
    storageChannelService: ref.watch(storageChannelServiceProvider),
  );
  listener.start();
  ref.onDispose(() => listener.dispose());
  return listener;
});

/// Metadata sync status provider (reactive).
final metadataSyncStatusProvider =
    StateNotifierProvider<MetadataSyncStatusNotifier, MetadataSyncStatus>((
      ref,
    ) {
      return MetadataSyncStatusNotifier(ref);
    });

/// Metadata sync status notifier.
class MetadataSyncStatusNotifier extends StateNotifier<MetadataSyncStatus> {
  MetadataSyncStatusNotifier(this._ref) : super(const MetadataSyncStatus()) {
    _listenToChanges();
  }

  final Ref _ref;
  StreamSubscription? _changeSubscription;

  void _listenToChanges() {
    final repo = _ref.read(metadataRepositoryProvider);
    _changeSubscription = repo.changeStream.listen((_) {
      _updateStatus();
    });
  }

  void _updateStatus() {
    final repo = _ref.read(metadataRepositoryProvider);
    state = repo.getSyncStatus();
  }

  Future<void> syncToTelegram({
    required Future<void> Function(String partitionId, String data)
    uploadPartition,
    required Future<void> Function(String manifestJson) uploadManifest,
  }) async {
    state = state.copyWith(syncInProgress: true);

    final repo = _ref.read(metadataRepositoryProvider);
    await repo.syncToTelegram(
      uploadPartition: uploadPartition,
      uploadManifest: uploadManifest,
    );

    _updateStatus();
  }

  @override
  void dispose() {
    _changeSubscription?.cancel();
    super.dispose();
  }
}

/// Total metadata items count provider.
final metadataItemCountProvider = Provider<int>((ref) {
  final repo = ref.watch(metadataRepositoryProvider);
  return repo.totalItems;
});

/// Dirty partitions count provider.
final dirtyPartitionsCountProvider = Provider<int>((ref) {
  final repo = ref.watch(metadataRepositoryProvider);
  return repo.getDirtyPartitions().length;
});

/// Search results provider (raw IDs from the search index).
final searchMetadataProvider = Provider.family<Set<String>, String>((
  ref,
  query,
) {
  final searchIndex = ref.watch(searchIndexServiceProvider);
  return searchIndex.search(query);
});

/// Optimized search provider that leverages the indexed search term store.
///
/// Falls back to the gallery's in-memory linear scan when the index returns
/// no results (e.g., for terms only present in the gallery but not yet
/// indexed by the metadata layer). This is O(m) where m is the number of
/// indexed terms, vs the gallery's O(n) linear scan over all items.
final indexedSearchProvider =
    FutureProvider.autoDispose.family<List<MediaItem>, String>((ref, query) async {
  final gallery = ref.watch(galleryRepositoryProvider);
  final searchIndex = ref.watch(searchIndexServiceProvider);

  // Use the indexed search when the index has entries.
  if (searchIndex.indexSize > 0) {
    final ids = searchIndex.search(query);
    if (ids.isNotEmpty) {
      return [
        for (final id in ids)
          if (gallery.getItemById(id) case final item?) item,
      ];
    }
  }

  // Fall back to the gallery's linear scan for unindexed terms.
  return gallery.searchMedia(query);
});
