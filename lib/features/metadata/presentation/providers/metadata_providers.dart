import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/conflict_resolver.dart';
import '../../data/repositories/manifest_service.dart';
import '../../data/repositories/metadata_repository.dart';
import '../../data/repositories/migration_service.dart';
import '../../data/repositories/partition_service.dart';
import '../../data/repositories/search_index_service.dart';
import '../../data/repositories/sync_service.dart';

/// Manifest service provider.
final manifestServiceProvider = Provider<ManifestService>((ref) {
  final service = ManifestService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Partition service provider.
final partitionServiceProvider = Provider<PartitionService>((ref) {
  final service = PartitionService();
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
final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService();
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

/// Search results provider.
final searchMetadataProvider = Provider.family<Set<String>, String>((
  ref,
  query,
) {
  final searchIndex = ref.watch(searchIndexServiceProvider);
  return searchIndex.search(query);
});
