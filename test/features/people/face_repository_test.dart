import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/features/people/data/repositories/face_repository.dart';
import 'package:lumovault/features/people/data/services/face_clustering_service.dart';
import 'package:lumovault/features/people/data/services/face_detection_service.dart';

void main() {
  late AppDatabase db;
  late FaceRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = FaceRepository(
      faceDao: db.faceDao,
      // Never initialised in these tests: FaceDetectionService swallows its own
      // init failure, and isHighQualityFace/the scan log never call into it.
      faceDetectionService: FaceDetectionService(),
      faceClusteringService: FaceClusteringService(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  DetectedFace face({
    required double left,
    required double top,
    required double width,
    required double height,
    double confidence = 0.9,
  }) => DetectedFace(
    boundingBox: ui.Rect.fromLTWH(left, top, width, height),
    embedding: const [],
    confidence: confidence,
  );

  group('isHighQualityFace', () {
    // A 4000×3000 photo — the size that made the old area-based gate reject
    // every real face.
    const w = 4000;
    const h = 3000;

    test('accepts an ordinary face on a 12 MP photo', () {
      // 200×240 px: well under 2% of the image area, but 5%/8% of a side.
      expect(
        repository.isHighQualityFace(
          face(left: 100, top: 100, width: 200, height: 240),
          w,
          h,
        ),
        isTrue,
      );
    });

    test('rejects a low-confidence detection', () {
      expect(
        repository.isHighQualityFace(
          face(left: 0, top: 0, width: 400, height: 400, confidence: 0.69),
          w,
          h,
        ),
        isFalse,
      );
      expect(
        repository.isHighQualityFace(
          face(
            left: 0,
            top: 0,
            width: 400,
            height: 400,
            confidence: FaceRepository.minConfidence,
          ),
          w,
          h,
        ),
        isTrue,
      );
    });

    test('rejects a face smaller than 3% of either side', () {
      // 3% of 4000 = 120 px wide, 3% of 3000 = 90 px tall.
      expect(
        repository.isHighQualityFace(
          face(left: 0, top: 0, width: 119, height: 200),
          w,
          h,
        ),
        isFalse,
      );
      expect(
        repository.isHighQualityFace(
          face(left: 0, top: 0, width: 200, height: 89),
          w,
          h,
        ),
        isFalse,
      );
      expect(
        repository.isHighQualityFace(
          face(left: 0, top: 0, width: 120, height: 90),
          w,
          h,
        ),
        isTrue,
      );
    });

    test('rejects boxes that are too elongated to be a face', () {
      // 2.1:1 wide and 2.1:1 tall are both outside the aspect window.
      expect(
        repository.isHighQualityFace(
          face(left: 0, top: 0, width: 630, height: 300),
          w,
          h,
        ),
        isFalse,
      );
      expect(
        repository.isHighQualityFace(
          face(left: 0, top: 0, width: 300, height: 630),
          w,
          h,
        ),
        isFalse,
      );
      // Exactly 2:1 is still allowed.
      expect(
        repository.isHighQualityFace(
          face(left: 0, top: 0, width: 600, height: 300),
          w,
          h,
        ),
        isTrue,
      );
    });

    test('rejects everything when the image dimensions are unknown', () {
      expect(
        repository.isHighQualityFace(
          face(left: 0, top: 0, width: 400, height: 400),
          0,
          0,
        ),
        isFalse,
      );
    });
  });

  group('normalizedLandmarks', () {
    DetectedFace withLandmarks(List<ui.Offset> landmarks) => DetectedFace(
      boundingBox: const ui.Rect.fromLTWH(0, 0, 100, 100),
      embedding: const [],
      confidence: 0.9,
      landmarks: landmarks,
    );

    test('normalises all five points against the image dimensions', () {
      final map = repository.normalizedLandmarks(
        withLandmarks(const [
          ui.Offset(100, 150),
          ui.Offset(300, 150),
          ui.Offset(200, 300),
          ui.Offset(120, 450),
          ui.Offset(280, 450),
        ]),
        400,
        600,
      );

      expect(map.keys, FaceRepository.landmarkNames);
      expect(map['leftEye'], (0.25, 0.25));
      expect(map['rightEye'], (0.75, 0.25));
      expect(map['nose'], (0.5, 0.5));
    });

    test('is empty when the detector produced no keypoints', () {
      expect(
        repository.normalizedLandmarks(withLandmarks(const []), 400, 600),
        isEmpty,
      );
    });

    test('is empty for a partial landmark set', () {
      expect(
        repository.normalizedLandmarks(
          withLandmarks(const [ui.Offset(1, 1), ui.Offset(2, 2)]),
          400,
          600,
        ),
        isEmpty,
      );
    });

    test('is empty when the image dimensions are unknown', () {
      expect(
        repository.normalizedLandmarks(
          withLandmarks(List.filled(5, const ui.Offset(1, 1))),
          0,
          0,
        ),
        isEmpty,
      );
    });
  });

  group('scan log', () {
    test('remembers scanned photos so they are not re-detected', () async {
      expect(await db.faceDao.scannedMediaItemIds(), isEmpty);

      await db.faceDao.markMediaItemScanned('a', 2);
      await db.faceDao.markMediaItemScanned('b', 0);

      expect(await db.faceDao.scannedMediaItemIds(), {'a', 'b'});
      expect(await db.faceDao.scannedMediaItemCount(), 2);
    });

    test('re-marking a photo updates rather than duplicates its row', () async {
      await db.faceDao.markMediaItemScanned('a', 0);
      await db.faceDao.markMediaItemScanned('a', 3);

      expect(await db.faceDao.scannedMediaItemCount(), 1);
    });

    test('clearScanLog forces a full re-scan', () async {
      await db.faceDao.markMediaItemScanned('a', 1);
      await db.faceDao.clearScanLog();

      expect(await db.faceDao.scannedMediaItemIds(), isEmpty);
    });

    test('a face-less photo still counts as scanned', () async {
      await db.faceDao.markMediaItemScanned('a', 0);

      // No faces were inserted, yet the photo is not offered again.
      expect(await db.faceDao.faceCount(), 0);
      expect(await db.faceDao.scannedMediaItemIds(), contains('a'));
    });
  });

  group('scanMediaItems batching', () {
    test('clusters every 50 photos', () {
      expect(FaceRepository.scanBatchSize, 50);
    });

    test('skips photos that are already in the scan log', () async {
      await db.faceDao.markMediaItemScanned('a', 1);

      // scanMediaItems filters against scannedMediaItemIds(); with an empty
      // asset list there is nothing left to do, and no clustering pass runs.
      var batches = 0;
      final results = await repository.scanMediaItems(
        const [],
        onBatchComplete: () async => batches++,
      );

      expect(results, isEmpty);
      expect(batches, 0);
    });
  });
}
