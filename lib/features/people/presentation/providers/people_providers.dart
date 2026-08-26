import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/database_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../core/database/daos/face_dao.dart';
import '../../data/repositories/face_repository.dart';
import '../../data/services/face_detection_service.dart';
import '../../data/services/face_clustering_service.dart';

final faceDetectionServiceProvider = Provider<FaceDetectionService>((ref) {
  return FaceDetectionService();
});

final faceClusteringServiceProvider = Provider<FaceClusteringService>((ref) {
  return FaceClusteringService();
});

final faceRepositoryProvider = Provider<FaceRepository>((ref) {
  final faceDao = ref.watch(appDatabaseProvider).faceDao;
  final detectionService = ref.watch(faceDetectionServiceProvider);
  final clusteringService = ref.watch(faceClusteringServiceProvider);
  return FaceRepository(
    faceDao: faceDao,
    faceDetectionService: detectionService,
    faceClusteringService: clusteringService,
  );
});

class FaceScanProgress {
  const FaceScanProgress({
    required this.current,
    required this.total,
    required this.isScanning,
    this.facesFound = 0,
  });

  final int current;
  final int total;
  final bool isScanning;
  final int facesFound;

  double get progress => total > 0 ? current / total : 0.0;
}

final faceScanProgressProvider = StateProvider<FaceScanProgress>((ref) {
  return const FaceScanProgress(current: 0, total: 0, isScanning: false);
});

final peopleProvider = FutureProvider.autoDispose<List<PersonWithCount>>((
  ref,
) async {
  final repository = ref.watch(faceRepositoryProvider);
  return repository.getPeople();
});

final personProvider = FutureProvider.autoDispose.family<dynamic, int>((
  ref,
  personId,
) async {
  final repository = ref.watch(faceRepositoryProvider);
  return repository.getPerson(personId);
});

final personMediaIdsProvider = FutureProvider.autoDispose
    .family<List<String>, int>((ref, personId) async {
      final repository = ref.watch(faceRepositoryProvider);
      return repository.getMediaItemIdsForPerson(personId);
    });

final faceCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final repository = ref.watch(faceRepositoryProvider);
  return repository.getFaceCount();
});

/// Whether there are device photos that haven't been face-scanned yet.
final hasUnscannedPhotosProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final repository = ref.watch(faceRepositoryProvider);
  final assets = await ref.watch(deviceAssetsProvider.future);
  if (assets.isEmpty) return false;
  final scannedIds = await repository.faceDao.scannedMediaItemIds();
  return assets.any((a) => !scannedIds.contains(a.id));
});

/// Provider to get the thumbnail path for a person's representative face.
final personThumbnailProvider = FutureProvider.autoDispose.family<String?, int>(
  (ref, personId) async {
    final faceDao = ref.watch(appDatabaseProvider).faceDao;
    final person = await faceDao.personById(personId);
    if (person?.thumbnailFaceId == null) return null;

    final faces = await faceDao.allFaces(personId: personId);
    final thumbnailFace = faces.firstWhere(
      (f) => f.id == person?.thumbnailFaceId,
      orElse: () => faces.first,
    );

    return thumbnailFace.thumbnailPath;
  },
);

/// Drives face scanning and progressive clustering.
///
/// Held by a keep-alive [Provider] rather than driven from a widget, so a scan
/// that outlives the People screen keeps running instead of blowing up on a
/// disposed `WidgetRef`.
class FaceScanController {
  FaceScanController(this._ref);

  final Ref _ref;
  bool _isScanning = false;

  bool get isScanning => _isScanning;

  Future<void> start() async {
    if (_isScanning) return;

    final assets = await _ref.read(deviceAssetsProvider.future);
    if (assets.isEmpty) return;

    _isScanning = true;
    _setProgress(
      const FaceScanProgress(current: 0, total: 0, isScanning: true),
    );

    final repository = _ref.read(faceRepositoryProvider);
    try {
      await repository.scanMediaItems(
        assets,
        onProgress: (current, total) {
          _setProgress(
            FaceScanProgress(current: current, total: total, isScanning: true),
          );
        },
        // Runs every FaceRepository.scanBatchSize (50) photos: cluster what
        // has been found so far and refresh the grid, then scanning resumes.
        onBatchComplete: () async {
          await repository.clusterFaces();
          _ref.invalidate(peopleProvider);
          _ref.invalidate(faceCountProvider);
        },
      );

      // Final pass for the trailing photos of the last, partial batch.
      await repository.clusterFaces();
    } finally {
      _isScanning = false;
      _setProgress(
        const FaceScanProgress(current: 0, total: 0, isScanning: false),
      );
      _ref.invalidate(peopleProvider);
      _ref.invalidate(faceCountProvider);
    }
  }

  void _setProgress(FaceScanProgress progress) {
    _ref.read(faceScanProgressProvider.notifier).state = progress;
  }
}

final faceScanControllerProvider = Provider<FaceScanController>((ref) {
  return FaceScanController(ref);
});
