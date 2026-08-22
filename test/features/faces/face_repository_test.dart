import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/core/database/tables/face_tables.dart';
import 'package:lumovault/features/faces/data/repositories/face_repository.dart';
import 'package:lumovault/features/faces/data/services/face_detection_service.dart';
import 'package:lumovault/features/faces/data/services/face_grouping_service.dart';

void main() {
  late AppDatabase db;
  late FaceRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = FaceRepository(
      faceDao: db.faceDao,
      mediaDao: db.mediaDao,
      detectionService: _MockFaceDetectionService(),
      groupingService: FaceGroupingService(),
    );
  });

  tearDown(() async {
    await db.close();
    await repository.dispose();
  });

  group('FaceRepository', () {
    test('getAllGroups returns empty list initially', () async {
      final groups = await repository.getAllGroups();
      expect(groups, isEmpty);
    });

    test('getStats returns zero counts initially', () async {
      final stats = await repository.getStats();
      expect(stats.groupCount, 0);
      expect(stats.faceCount, 0);
    });

    test('renameGroup updates group name', () async {
      // First create a group via the DAO.
      final groupId = await db.faceDao.createGroup(name: 'Original');

      await repository.renameGroup(groupId, 'Updated');

      final groups = await repository.getAllGroups();
      expect(groups, hasLength(1));
      expect(groups.first.name, 'Updated');
    });

    test('deleteGroup ungroups faces', () async {
      // Create a group and a face in it.
      final groupId = await db.faceDao.createGroup(name: 'Test');
      await db.faceDao.upsertFaces([
        FacesCompanion.insert(
          mediaItemId: 'test_1',
          groupId: groupId,
          bboxLeft: 0.1,
          bboxTop: 0.1,
          bboxRight: 0.5,
          bboxBottom: 0.5,
          embedding: '[0.1, 0.2]',
          confidence: 0.9,
          detectedAt: DateTime.now(),
        ),
      ]);

      await repository.deleteGroup(groupId);

      final groups = await repository.getAllGroups();
      expect(groups, isEmpty);

      // Face should be ungrouped.
      final ungrouped = await db.faceDao.ungroupedFaces();
      expect(ungrouped, hasLength(1));
    });

    test('mergeGroups moves faces to target', () async {
      final group1 = await db.faceDao.createGroup(name: 'A');
      final group2 = await db.faceDao.createGroup(name: 'B');

      await db.faceDao.upsertFaces([
        FacesCompanion.insert(
          mediaItemId: 'test_1',
          groupId: group1,
          bboxLeft: 0.1,
          bboxTop: 0.1,
          bboxRight: 0.5,
          bboxBottom: 0.5,
          embedding: '[0.1]',
          confidence: 0.9,
          detectedAt: DateTime.now(),
        ),
        FacesCompanion.insert(
          mediaItemId: 'test_2',
          groupId: group2,
          bboxLeft: 0.2,
          bboxTop: 0.2,
          bboxRight: 0.6,
          bboxBottom: 0.6,
          embedding: '[0.2]',
          confidence: 0.8,
          detectedAt: DateTime.now(),
        ),
      ]);

      await repository.mergeGroups(group1, group2);

      // Source group should be deleted.
      final groups = await repository.getAllGroups();
      expect(groups, hasLength(1));
      expect(groups.first.id, group2);

      // Both faces should now be in group2.
      final facesInGroup2 = await db.faceDao.facesInGroup(group2);
      expect(facesInGroup2, hasLength(2));
    });

    test('getFacesInGroup returns faces for the given group', () async {
      final groupId = await db.faceDao.createGroup(name: 'Test');

      await db.faceDao.upsertFaces([
        FacesCompanion.insert(
          mediaItemId: 'item_1',
          groupId: groupId,
          bboxLeft: 0.1,
          bboxTop: 0.1,
          bboxRight: 0.5,
          bboxBottom: 0.5,
          embedding: '[0.1]',
          confidence: 0.9,
          detectedAt: DateTime(2026, 1, 1),
        ),
        FacesCompanion.insert(
          mediaItemId: 'item_2',
          groupId: groupId,
          bboxLeft: 0.2,
          bboxTop: 0.2,
          bboxRight: 0.6,
          bboxBottom: 0.6,
          embedding: '[0.2]',
          confidence: 0.8,
          detectedAt: DateTime(2026, 1, 2),
        ),
        // Face in a different group.
        FacesCompanion.insert(
          mediaItemId: 'item_3',
          groupId: 999,
          bboxLeft: 0.3,
          bboxTop: 0.3,
          bboxRight: 0.7,
          bboxBottom: 0.7,
          embedding: '[0.3]',
          confidence: 0.7,
          detectedAt: DateTime(2026, 1, 3),
        ),
      ]);

      final faces = await repository.getFacesInGroup(groupId);
      expect(faces, hasLength(2));
      // Should be ordered by detectedAt descending (newest first).
      expect(faces.first.mediaItemId, 'item_2');
      expect(faces.last.mediaItemId, 'item_1');
    });

    test('getMediaItemIdsForGroup returns unique media item IDs', () async {
      final groupId = await db.faceDao.createGroup(name: 'Test');

      await db.faceDao.upsertFaces([
        FacesCompanion.insert(
          mediaItemId: 'item_1',
          groupId: groupId,
          bboxLeft: 0.1,
          bboxTop: 0.1,
          bboxRight: 0.5,
          bboxBottom: 0.5,
          embedding: '[0.1]',
          confidence: 0.9,
          detectedAt: DateTime.now(),
        ),
        FacesCompanion.insert(
          mediaItemId: 'item_1', // Same item, second face.
          groupId: groupId,
          bboxLeft: 0.4,
          bboxTop: 0.4,
          bboxRight: 0.8,
          bboxBottom: 0.8,
          embedding: '[0.4]',
          confidence: 0.85,
          detectedAt: DateTime.now(),
        ),
        FacesCompanion.insert(
          mediaItemId: 'item_2',
          groupId: groupId,
          bboxLeft: 0.2,
          bboxTop: 0.2,
          bboxRight: 0.6,
          bboxBottom: 0.6,
          embedding: '[0.2]',
          confidence: 0.8,
          detectedAt: DateTime.now(),
        ),
      ]);

      final ids = await repository.getMediaItemIdsForGroup(groupId);
      expect(ids, hasLength(2));
      expect(ids, containsAll(['item_1', 'item_2']));
    });
  });
}

/// Minimal mock that always returns zero faces (file not found).
class _MockFaceDetectionService implements FaceDetectionService {
  @override
  Future<List<DetectedFace>> detectFaces({
    required String filePath,
    required int imageWidth,
    required int imageHeight,
  }) async {
    return [];
  }

  @override
  Future<void> dispose() async {}
}
