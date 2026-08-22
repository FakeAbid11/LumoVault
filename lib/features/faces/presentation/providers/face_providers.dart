import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumovault/core/di/database_providers.dart';
import 'package:lumovault/features/faces/data/repositories/face_repository.dart';

/// Provider for the [FaceRepository].
final faceRepositoryProvider = Provider<FaceRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return FaceRepository(faceDao: db.faceDao, mediaDao: db.mediaDao);
});

/// Whether face detection is currently running.
final faceAnalysisRunningProvider = StateProvider<bool>((ref) => false);

/// Progress of the current face analysis run: (processed, total, facesFound).
final faceAnalysisProgressProvider = StateProvider<(int, int, int)>(
  (ref) => (0, 0, 0),
);

/// All face groups, refreshed whenever a mutation occurs.
final faceGroupsProvider = FutureProvider.autoDispose<List<FaceGroup>>((
  ref,
) async {
  final repo = ref.watch(faceRepositoryProvider);
  return repo.getAllGroups();
});

/// Stats for the People tab header.
final faceStatsProvider =
    FutureProvider.autoDispose<({int groupCount, int faceCount})>((ref) async {
      final repo = ref.watch(faceRepositoryProvider);
      return repo.getStats();
    });

/// Faces inside a specific group, loaded on demand.
final groupFacesProvider = FutureProvider.autoDispose
    .family<List<DetectedFaceItem>, int>((ref, groupId) async {
      final repo = ref.watch(faceRepositoryProvider);
      return repo.getFacesInGroup(groupId);
    });

/// Media item IDs for a group (for grid display).
final groupMediaIdsProvider = FutureProvider.autoDispose
    .family<List<String>, int>((ref, groupId) async {
      final repo = ref.watch(faceRepositoryProvider);
      return repo.getMediaItemIdsForGroup(groupId);
    });

/// Starts the full face analysis pipeline (detect + group).
///
/// Call this from a UI button or automatically on first launch.
Future<void> runFaceAnalysis(WidgetRef ref) async {
  if (ref.read(faceAnalysisRunningProvider)) return;

  ref.read(faceAnalysisRunningProvider.notifier).state = true;
  ref.read(faceAnalysisProgressProvider.notifier).state = (0, 0, 0);

  try {
    final repo = ref.read(faceRepositoryProvider);
    await repo.runFullPipeline(
      onProgress: (processed, total, facesFound) {
        ref.read(faceAnalysisProgressProvider.notifier).state = (
          processed,
          total,
          facesFound,
        );
      },
    );
    // Invalidate cached data so UI refreshes.
    ref.invalidate(faceGroupsProvider);
    ref.invalidate(faceStatsProvider);
  } finally {
    ref.read(faceAnalysisRunningProvider.notifier).state = false;
  }
}
