import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:photo_manager/photo_manager.dart' hide LatLng;

import '../../features/gallery/data/models/device_folder.dart';
import '../../features/gallery/data/models/media_item.dart';
import '../../features/gallery/data/repositories/asset_location.dart';
import '../../features/gallery/data/repositories/gallery_repository.dart';
import '../../features/gallery/data/repositories/incremental_scanner.dart';
import '../../features/gallery/data/repositories/media_scanner_service.dart';
import '../../features/gallery/presentation/widgets/heatmap_layer.dart';
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

  for (final item in await resolveAssetLocations(pending)) {
    located[item.localId] = item;
  }

  // Second emission: merged list with newly-resolved items.
  yield located.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
});

/// Transforms [mapPhotosProvider] data into weighted [HeatmapPoint]s for the
/// heatmap layer. Each photo contributes weight 1. Photos at the exact same
/// 6-decimal coordinate are grouped into a single point with accumulated weight.
final heatmapPointsProvider = FutureProvider.autoDispose<List<HeatmapPoint>>((
  ref,
) async {
  final photosAsync = ref.watch(mapPhotosProvider);
  return photosAsync.when(
    loading: () => [],
    error: (_, __) => [],
    data: (photos) {
      final grouped = <String, HeatmapPoint>{};
      for (final photo in photos) {
        if (!photo.hasLocation) continue;
        final key =
            '${photo.latitude!.toStringAsFixed(6)},${photo.longitude!.toStringAsFixed(6)}';
        final existing = grouped[key];
        if (existing != null) {
          grouped[key] = HeatmapPoint(
            latLng: existing.latLng,
            weight: existing.weight + 1,
          );
        } else {
          grouped[key] = HeatmapPoint(
            latLng: LatLng(photo.latitude!, photo.longitude!),
          );
        }
      }
      return grouped.values.toList();
    },
  );
});

/// Lists device photos/videos directly for the timeline grid — fast,
/// metadata-only, no hashing. Kept separate from [timelineProvider] (which
/// reads the hashed/scanned [MediaItem] list) since display no longer
/// depends on the slow scan; only starting an actual backup does.
final deviceAssetsProvider = FutureProvider.autoDispose<List<AssetEntity>>((
  ref,
) async {
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

final searchProvider = FutureProvider.autoDispose
    .family<List<MediaItem>, String>((ref, query) async {
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
