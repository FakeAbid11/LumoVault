import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../features/gallery/data/models/device_folder.dart';
import '../../features/gallery/data/models/media_item.dart';
import '../../features/gallery/data/repositories/gallery_repository.dart';
import '../../features/gallery/data/repositories/incremental_scanner.dart';
import '../../features/gallery/data/repositories/media_scanner_service.dart';
import 'database_providers.dart';

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

final albumsProvider = Provider<List<String>>((ref) {
  final repository = ref.watch(galleryRepositoryProvider);
  final folders = repository.folders;
  return folders.map((f) => f.name).toList();
});

final albumItemsProvider = FutureProvider.autoDispose
    .family<List<MediaItem>, String>((ref, albumName) async {
      final repository = ref.watch(galleryRepositoryProvider);
      return repository.getAlbumItems(albumName);
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

final mediaItemProvider = FutureProvider.autoDispose.family<MediaItem?, String>(
  (ref, localId) async {
    final repository = ref.watch(galleryRepositoryProvider);
    return repository.getItemById(localId);
  },
);
