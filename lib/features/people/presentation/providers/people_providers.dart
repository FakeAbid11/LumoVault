import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/daos/face_dao.dart';
import '../../../../core/di/database_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../core/storage/isolate_run_lock.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../data/repositories/face_scan_lock.dart';
import '../../data/models/person.dart';
import '../../data/repositories/face_repository.dart';
import '../../data/services/face_detection_service.dart';
import '../../data/services/face_clustering_service.dart';

final faceDetectionServiceProvider = Provider<FaceDetectionService>((ref) {
  // Single detector asset for all devices: the 500M SCRFD (the config
  // default). There was an 8+ core tier that selected
  // scrfd_2_5g_kps_fp16.onnx, but that asset shipped as a truncated
  // placeholder — smaller than the 500M it was meant to upgrade — so
  // high-end devices failed to load it, silently fell back to 500M behind a
  // debug-only log, and the advertised tiering delivered nothing. The branch
  // is gone until a real export exists, and that re-add should come with an
  // asset-integrity test.
  final service = FaceDetectionService();
  // The detector holds two ONNX sessions and a preprocessing worker isolate.
  // In the background isolate the per-task container is disposed after EVERY
  // face-scan task while WorkManager keeps the process alive, so without this
  // the sessions and isolate accumulated across task fires.
  ref.onDispose(service.dispose);
  return service;
});

final faceClusteringServiceProvider = Provider<FaceClusteringService>((ref) {
  return FaceClusteringService();
});

final faceRepositoryProvider = Provider<FaceRepository>((ref) {
  final faceDao = ref.watch(appDatabaseProvider).faceDao;
  final detectionService = ref.watch(faceDetectionServiceProvider);
  final clusteringService = ref.watch(faceClusteringServiceProvider);
  final repository = FaceRepository(
    faceDao: faceDao,
    faceDetectionService: detectionService,
    faceClusteringService: clusteringService,
  );
  // Invalidate the gallery's person names search cache when face assignments
  // change, so the next search reflects newly named people.
  repository.onAssignmentsChanged = () {
    ref.read(galleryRepositoryProvider).invalidatePersonNamesCache();
  };
  return repository;
});

class FaceScanProgress {
  const FaceScanProgress({
    required this.current,
    required this.total,
    required this.isScanning,
    this.facesFound = 0,
    this.isPaused = false,
    this.error,
  });

  final int current;
  final int total;
  final bool isScanning;
  final int facesFound;
  final bool isPaused;

  /// Set when a scan aborted (e.g. the detector could not be loaded) so the
  /// People screen can show a retry instead of a silent "No people found".
  final String? error;

  double get progress => total > 0 ? current / total : 0.0;

  FaceScanProgress copyWith({bool? isPaused}) {
    return FaceScanProgress(
      current: current,
      total: total,
      isScanning: isScanning,
      facesFound: facesFound,
      isPaused: isPaused ?? this.isPaused,
      error: error,
    );
  }
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

final personProvider = FutureProvider.autoDispose.family<Person?, int>((
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
  final gallery = ref.watch(galleryRepositoryProvider);
  final assets = (await ref.watch(deviceAssetsProvider.future)).where((a) {
    // Hidden/trashed photos are never scanned — including them here would
    // show the "new photos to scan" card forever, since they never enter
    // the scan log.
    final item = gallery.getItemById(a.id);
    return item?.isHidden != true && item?.isTrashed != true;
  }).toList();
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
    if (faces.isEmpty) return null;
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
  bool _pauseRequested = false;
  FaceScanProgress _lastProgress = const FaceScanProgress(
    current: 0,
    total: 0,
    isScanning: false,
  );

  bool get isScanning => _isScanning;
  bool get isPaused => _pauseRequested;

  Future<void> start() async {
    if (_isScanning) return;

    // Hidden and trashed photos must never be face-scanned: without this
    // filter the detector crops of private-vault photos were written to the
    // cache and their embeddings stored, even though backup correctly
    // skipped them.
    final gallery = _ref.read(galleryRepositoryProvider);
    final assets = (await _ref.read(deviceAssetsProvider.future)).where((a) {
      final item = gallery.getItemById(a.id);
      return item?.isHidden != true && item?.isTrashed != true;
    }).toList();
    if (assets.isEmpty) return;

    // The background face-scan worker holds the same lock; without it the two
    // scans race and double the ONNX session count. The lock file is the only
    // signal between isolates, so back off instead of starting a second
    // detector — the background scan releases on its next task boundary.
    final lock = IsolateRunLock(name: kFaceScanLockName);
    if (!await lock.tryAcquire()) {
      _setProgress(
        const FaceScanProgress(
          current: 0,
          total: 0,
          isScanning: false,
          error:
              'A background face scan is already running. Please try again '
              'in a moment.',
        ),
      );
      return;
    }

    // Enable auto-scan for future photos.
    _ref
        .read(appSettingsProvider.notifier)
        .updateField((s) => s.copyWith(faceScanEnabled: true));

    _isScanning = true;
    _pauseRequested = false;
    _setProgress(
      const FaceScanProgress(current: 0, total: 0, isScanning: true),
    );

    final repository = _ref.read(faceRepositoryProvider);
    String? error;
    Timer? heartbeatTimer;
    try {
      // A large library scans for many minutes; without a heartbeat the lock
      // goes stale after 20 min and a background task legally takes it,
      // starting a second detector alongside this one.
      heartbeatTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => unawaited(lock.heartbeat()),
      );
      await repository.scanMediaItems(
        assets,
        onProgress: (current, total) {
          // Per-photo state writes rebuild the entire People grid thousands
          // of times over a scan; report on the first photo and at each
          // batch boundary instead.
          if (current == 1 || current % FaceRepository.scanBatchSize == 0) {
            _setProgress(
              FaceScanProgress(
                current: current,
                total: total,
                isScanning: true,
                isPaused: _pauseRequested,
              ),
            );
          }
        },
        // Runs every FaceRepository.scanBatchSize (50) photos: cluster what
        // has been found so far and refresh the grid, then scanning resumes.
        onBatchComplete: () async {
          await repository.clusterFaces();
          _ref.invalidate(peopleProvider);
          _ref.invalidate(faceCountProvider);
        },
        pauseGate: _awaitUnpaused,
      );

      // Final pass for the trailing photos of the last, partial batch.
      await repository.clusterFaces();
    } on FaceDetectorUnavailable catch (e) {
      // A dead detector used to look like "no faces" — surface it instead.
      debugPrint('[FaceScanController] Detector unavailable: $e');
      error = e.toString();
    } catch (e) {
      debugPrint('[FaceScanController] Scan failed: $e');
      error = e.toString();
    } finally {
      heartbeatTimer?.cancel();
      await lock.release();
      _isScanning = false;
      _pauseRequested = false;
      _setProgress(
        FaceScanProgress(current: 0, total: 0, isScanning: false, error: error),
      );
      _ref.invalidate(peopleProvider);
      _ref.invalidate(faceCountProvider);
      _ref.invalidate(hasUnscannedPhotosProvider);
    }
  }

  /// Holds the scan at a batch boundary while the user has it paused.
  Future<void> _awaitUnpaused() async {
    while (_pauseRequested && _isScanning) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Pause at the next batch boundary (a scan batch takes ~10-30 s of ONNX
  /// inference, so the stop is quick without mid-photo interruption).
  void pause() {
    if (!_isScanning || _pauseRequested) return;
    _pauseRequested = true;
    _setProgress(_lastProgress.copyWith(isPaused: true));
  }

  void resume() {
    if (!_pauseRequested) return;
    _pauseRequested = false;
    _setProgress(_lastProgress.copyWith(isPaused: false));
  }

  /// Wipe all face data and re-scan every photo from scratch.
  ///
  /// Useful for picking up faces that were previously missed (e.g. video call
  /// screenshots where the detector confidence was borderline). Named people
  /// are kept as merge anchors; unnamed groups are removed. Clearing only the
  /// scan log used to duplicate every face row on each full rescan.
  Future<void> rescanAll() async {
    if (_isScanning) return;

    final repository = _ref.read(faceRepositoryProvider);
    await repository.faceDao.clearForRescan();
    await start();
  }

  void _setProgress(FaceScanProgress progress) {
    _lastProgress = progress;
    _ref.read(faceScanProgressProvider.notifier).state = progress;
  }
}

final faceScanControllerProvider = Provider<FaceScanController>((ref) {
  return FaceScanController(ref);
});
