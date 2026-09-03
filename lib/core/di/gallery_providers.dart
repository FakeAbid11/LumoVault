import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../features/gallery/data/models/device_folder.dart';
import '../../features/gallery/data/models/media_item.dart';
import '../../features/gallery/data/repositories/gallery_repository.dart';
import '../../features/gallery/data/repositories/incremental_scanner.dart';
import '../../features/gallery/data/repositories/media_scanner_service.dart';
import '../../features/gallery/data/services/image_classifier_service.dart';
import '../storage/storage_channel_service.dart';
import 'database_providers.dart';
import 'tdlib_providers.dart';
import 'transfer_providers.dart';

final mediaScannerServiceProvider = Provider<MediaScannerService>((ref) {
  return PhotoManagerScannerService();
});

final incrementalScannerProvider = Provider<IncrementalScanner>((ref) {
  return IncrementalScanner();
});

/// Lists device folders directly — metadata-only (asset counts, no file
/// reads), so it works before any scan has ever run. GalleryRepository.folders
/// only gets populated as a side effect of scanning, which meant the folder
/// selection screen showed nothing until a backup had already been started
/// once — backwards, since picking folders is something you'd want to do
/// beforehand.
final deviceFoldersProvider = FutureProvider.autoDispose<List<DeviceFolder>>((
  ref,
) async {
  final scannerService = ref.watch(mediaScannerServiceProvider);
  return scannerService.getDeviceFolders();
});

final galleryRepositoryProvider = Provider<GalleryRepository>((ref) {
  final scannerService = ref.watch(mediaScannerServiceProvider);
  final incrementalScanner = ref.watch(incrementalScannerProvider);
  final mediaDao = ref.watch(appDatabaseProvider).mediaDao;
  return GalleryRepository(
    scannerService: scannerService,
    mediaDao: mediaDao,
    incrementalScanner: incrementalScanner,
  );
});

final scanProgressProvider = StateProvider<ScanProgress>((ref) {
  return const ScanProgress(current: 0, total: 0, isScanning: false);
});

/// Wires permanent-delete propagation onto [GalleryRepository]: when the user
/// deletes forever (or trash retention expires), the repository revokes each
/// item's copy in the storage channel via [deletionServiceProvider]. Resolves
/// the channel lazily per delete (no channel → no-op) so this never forces
/// channel creation. Must be read once at bootstrap to install the callback;
/// like [metadataIntegrationProvider], the read is the wiring.
final galleryRemoteDeletionProvider = Provider<void>((ref) {
  final gallery = ref.watch(galleryRepositoryProvider);
  final deletionService = ref.watch(deletionServiceProvider);
  final channelService = ref.watch(storageChannelServiceProvider);

  gallery.setRemoteDeleteCallback((messageIds) async {
    final result = await channelService.findExistingChannel();
    final int channelId;
    switch (result) {
      case StorageChannelFound(channelId: final id):
      case StorageChannelCreated(channelId: final id):
        channelId = id;
      case StorageChannelNotFound():
      case StorageChannelError():
        return; // No channel to delete from — tombstone alone converges peers.
    }
    await deletionService.deleteMessages(
      channelId: channelId,
      messageIds: messageIds,
    );
  });
});

/// Bumped whenever the thumbnail cache is cleared or rebuilt, so the timeline
/// can force its tiles to re-run their thumbnail loaders instead of showing
/// the stale placeholder for the rest of the session.
final thumbnailGenerationProvider = StateProvider<int>((ref) => 0);

class ScanProgress {
  const ScanProgress({
    required this.current,
    required this.total,
    required this.isScanning,
  });
  final int current;
  final int total;
  final bool isScanning;

  double get progress => total > 0 ? current / total : 0.0;
}

final timelineProvider = FutureProvider.autoDispose<List<MediaItem>>((
  ref,
) async {
  final repository = ref.watch(galleryRepositoryProvider);
  return repository.getTimelineItems();
});

/// Media items to plot on the Map tab.
///
/// Emits twice via [StreamProvider] so the map renders instantly:
///  1. First emission (synchronous): scanned library items that already carry a
///     resolved location — coordinates are persisted, hidden/trashed items are
///     already dropped by [GalleryRepository.getTimelineItems].
///  2. Second emission (background): device photos not yet scanned, whose GPS
///     EXIF is read directly (no hashing — see [resolveAssetLocations]) so
///     they appear a few seconds later. Coordinates already known from source 1
///     are skipped so a fix is never re-read.
///
/// Items the user has hidden or trashed are suppressed from source 2: those
/// flags only live on scanned items (which getTimelineItems has filtered out),
/// so without this guard a raw device read would resurrect them onto the map.
final mapPhotosProvider = StreamProvider.autoDispose<List<MediaItem>>((
  ref,
) async* {
  final repository = ref.watch(galleryRepositoryProvider);

  final located = <String, MediaItem>{
    for (final item in repository.getTimelineItems())
      if (item.hasLocation) item.localId: item,
  };

  // First emission: show already-scanned items instantly.
  yield located.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  // Background: resolve GPS for device photos not yet in the database.
  final suppressed = <String>{
    for (final item in repository.mediaItems)
      if (item.isHidden || item.isTrashed) item.localId,
  };

  final assets = await ref.watch(deviceAssetsProvider.future);
  final pending = [
    for (final asset in assets)
      if (!located.containsKey(asset.id) && !suppressed.contains(asset.id))
        asset,
  ];

  // Split into cached and uncached.
  final uncached = <AssetEntity>[];
  for (final asset in pending) {
    final cached = repository.getCachedLocation(asset.id);
    if (cached != null) {
      final item = MediaItem(
        localId: asset.id,
        fileHash: '',
        filePath: '',
        fileName: asset.title ?? asset.id,
        mimeType: asset.type == AssetType.image ? 'image/jpeg' : 'video/mp4',
        fileSize: 0,
        width: asset.width,
        height: asset.height,
        durationMs: asset.type == AssetType.video
            ? asset.duration * 1000
            : null,
        createdAt: asset.createDateTime,
        modifiedAt: asset.modifiedDateTime,
        scannedAt: DateTime.now(),
        status: MediaStatus.pending,
        latitude: cached.$1,
        longitude: cached.$2,
      );
      located[item.localId] = item;
    } else {
      uncached.add(asset);
    }
  }

  // Yield with cached locations immediately.
  yield located.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  if (uncached.isEmpty) return;

  // Resolve uncached assets in batches of 50, yielding progressively.
  const batchSize = 50;
  for (var start = 0; start < uncached.length; start += batchSize) {
    final end = start + batchSize;
    final chunk = uncached.sublist(
      start,
      end > uncached.length ? uncached.length : end,
    );

    final resolved = await Future.wait(
      chunk.map((asset) async {
        try {
          final latlng = await asset.latlngAsync();
          if (latlng == null) return null;
          final lat = latlng.latitude;
          final lng = latlng.longitude;
          if (lat == 0 && lng == 0) return null;
          // Cache for next visit.
          repository.cacheLocation(asset.id, lat, lng);
          final mimeType = asset.type == AssetType.image
              ? 'image/jpeg'
              : 'video/mp4';
          return MediaItem(
            localId: asset.id,
            fileHash: '',
            filePath: '',
            fileName: asset.title ?? asset.id,
            mimeType: mimeType,
            fileSize: 0,
            width: asset.width,
            height: asset.height,
            durationMs: asset.type == AssetType.video
                ? asset.duration * 1000
                : null,
            createdAt: asset.createDateTime,
            modifiedAt: asset.modifiedDateTime,
            scannedAt: DateTime.now(),
            status: MediaStatus.pending,
            latitude: lat,
            longitude: lng,
          );
        } catch (_) {
          return null;
        }
      }),
    );

    for (final item in resolved.whereType<MediaItem>()) {
      located[item.localId] = item;
    }

    // Yield after each batch so markers appear progressively.
    yield located.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
});

/// Lists device photos/videos directly for the timeline grid — fast,
/// metadata-only, no hashing. Kept separate from [timelineProvider] (which
/// reads the hashed/scanned [MediaItem] list) since display no longer
/// depends on the slow scan; only starting an actual backup does.
///
/// Uses [keepAlive] so the asset list is cached across tab switches —
/// the Map tab reuses it without re-paginating through all device photos.
final deviceAssetsProvider = FutureProvider<List<AssetEntity>>((ref) async {
  final scannerService = ref.watch(mediaScannerServiceProvider);
  final assets = await scannerService.listAllAssets();
  assets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
  return assets;
});

final timelineByDateProvider = Provider<Map<String, List<MediaItem>>>((ref) {
  final repository = ref.watch(galleryRepositoryProvider);
  return repository.getTimelineByDate();
});

final favoriteItemsProvider = FutureProvider.autoDispose<List<MediaItem>>((
  ref,
) async {
  final repository = ref.watch(galleryRepositoryProvider);
  return repository.getFavoriteItems();
});

final searchProvider = Provider.autoDispose.family<List<MediaItem>, String>((
  ref,
  query,
) {
  final repository = ref.watch(galleryRepositoryProvider);
  return repository.searchMedia(query);
});

final trashedItemsProvider = FutureProvider.autoDispose<List<MediaItem>>((
  ref,
) async {
  final repository = ref.watch(galleryRepositoryProvider);
  return repository.getTrashedItems();
});

final hiddenItemsProvider = FutureProvider.autoDispose<List<MediaItem>>((
  ref,
) async {
  final repository = ref.watch(galleryRepositoryProvider);
  return repository.getHiddenItems();
});

final archivedItemsProvider = FutureProvider.autoDispose<List<MediaItem>>((
  ref,
) async {
  final repository = ref.watch(galleryRepositoryProvider);
  return repository.getArchivedItems();
});

final duplicateGroupsProvider = Provider<Map<String, List<MediaItem>>>((ref) {
  final repository = ref.watch(galleryRepositoryProvider);
  return repository.getDuplicateGroups();
});

final mediaItemProvider = FutureProvider.autoDispose.family<MediaItem?, String>(
  (ref, localId) async {
    final repository = ref.watch(galleryRepositoryProvider);
    return repository.getItemById(localId);
  },
);

/// Singleton instance of the AI image classifier.
final imageClassifierProvider = Provider<ImageClassifierService>((ref) {
  return ImageClassifierService.instance;
});

/// The pool the AI scan draws from: every image on the device that has no AI
/// labels yet — including photos that have never been through a scan.
///
/// Label state lives on gallery records (written when a photo is scanned or
/// built on demand via [GalleryRepository.upsertFromAsset]), so "already
/// labeled" can only be evaluated for photos that have a record; photos
/// without one are always unlabeled, and the scan creates their record
/// before classifying. Hidden/trashed records stay out of the pool,
/// matching the exclusions the repository-based pool used to apply.
final aiScanPoolProvider = FutureProvider.autoDispose<List<AssetEntity>>((
  ref,
) async {
  final assets = await ref.watch(deviceAssetsProvider.future);
  final repository = ref.watch(galleryRepositoryProvider);

  final recordsById = {
    for (final item in repository.mediaItems) item.localId: item,
  };

  bool isUnlabeled(AssetEntity asset) {
    final item = recordsById[asset.id];
    if (item == null) return true; // never scanned — always needs labeling
    if (item.isHidden || item.isTrashed) return false;
    return item.aiLabels.isEmpty;
  }

  return [
    for (final asset in assets)
      if (asset.type == AssetType.image && isUnlabeled(asset)) asset,
  ];
});

/// Count of items that have been AI-labeled.
final labeledCountProvider = Provider<int>((ref) {
  final repository = ref.watch(galleryRepositoryProvider);
  return repository.mediaItems
      .where(
        (item) =>
            !item.isHidden &&
            !item.isTrashed &&
            item.mediaType == MediaType.image &&
            item.aiLabels.isNotEmpty,
      )
      .length;
});
