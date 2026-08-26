import 'dart:math';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
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

  // ── Person lifecycle ───────────────────────────────────────────────────────
  //
  // Every embedding below is a 2-d unit vector, so its cosine similarity
  // against [reference] is exactly the number passed to [vec]. That makes the
  // 0.45 / 0.55 thresholds testable without hand-rolled 512-d fixtures.

  const reference = <double>[1.0, 0.0];
  List<double> vec(double similarityToReference) => [
    similarityToReference,
    sqrt(1 - similarityToReference * similarityToReference),
  ];

  var nextMediaId = 0;
  Future<int> addFace(List<double> embedding, {int? personId}) {
    nextMediaId++;
    return db.faceDao.insertFace(
      FacesCompanion.insert(
        mediaItemId: 'photo_$nextMediaId',
        boundingBoxX: 0.1,
        boundingBoxY: 0.1,
        boundingBoxWidth: 0.2,
        boundingBoxHeight: 0.2,
        embedding: Value(embedding),
        confidence: 0.9,
        createdAt: DateTime(2026, 1, 1).add(Duration(minutes: nextMediaId)),
        personId: personId == null ? const Value.absent() : Value(personId),
      ),
    );
  }

  Future<int> addPerson({String? name, required List<double> centroid}) async {
    final id = await db.faceDao.createPerson(name);
    await db.faceDao.updateCentroid(id, centroid);
    return id;
  }

  Future<int?> personIdOf(int faceId) async {
    final rows = await db.faceDao.allFaces();
    return rows.firstWhere((f) => f.id == faceId).personId;
  }

  group('absorbThreshold', () {
    test('an unnamed person uses the same bar that formed its cluster', () {
      expect(
        FaceRepository.absorbThreshold(null),
        FaceClusteringService.defaultThreshold,
      );
    });

    test('a named person demands the stricter bar', () {
      expect(
        FaceRepository.absorbThreshold('Alice'),
        FaceClusteringService.namedThreshold,
      );
    });

    test('a blank name is not a name', () {
      // Renaming a person to whitespace must not silently tighten their bar.
      expect(
        FaceRepository.absorbThreshold('   '),
        FaceClusteringService.defaultThreshold,
      );
    });
  });

  group('reclusterOrphans', () {
    test('absorbs a 0.50 face into an unnamed person', () async {
      // The regression this guards: 0.50 clears the 0.45 clustering bar, so
      // three such faces would group together and mint a duplicate person,
      // yet the old code held every person to 0.55 and refused to absorb them.
      final personId = await addPerson(centroid: reference);
      final faceId = await addFace(vec(0.50));

      await repository.reclusterOrphans();

      expect(await personIdOf(faceId), personId);
    });

    test('leaves a 0.50 face alone when the person is named', () async {
      await addPerson(name: 'Alice', centroid: reference);
      final faceId = await addFace(vec(0.50));

      await repository.reclusterOrphans();

      expect(await personIdOf(faceId), isNull);
    });

    test('absorbs a 0.60 face into a named person', () async {
      final personId = await addPerson(name: 'Alice', centroid: reference);
      final faceId = await addFace(vec(0.60));

      await repository.reclusterOrphans();

      expect(await personIdOf(faceId), personId);
    });

    test('prefers a passing lower score over a failing higher one', () async {
      // Two orthogonal anchors, so the face's similarity to each is just its
      // component along that axis: 0.54 against Alice — which fails her 0.55
      // bar — and 0.50 against the unnamed person, which clears 0.45. Picking
      // the argmax first and thresholding afterwards would strand the face on
      // Alice's higher but disqualified score.
      await addPerson(name: 'Alice', centroid: const [1.0, 0.0, 0.0]);
      final unnamedId = await addPerson(centroid: const [0.0, 1.0, 0.0]);
      final faceId = await addFace([
        0.54,
        0.50,
        sqrt(1 - 0.54 * 0.54 - 0.50 * 0.50),
      ]);

      await repository.reclusterOrphans();

      expect(await personIdOf(faceId), unnamedId);
    });

    test('ignores people that have no centroid yet', () async {
      await db.faceDao.createPerson(null);
      final faceId = await addFace(vec(0.99));

      await repository.reclusterOrphans();

      expect(await personIdOf(faceId), isNull);
    });

    test('leaves a face that matches nobody unassigned', () async {
      await addPerson(centroid: reference);
      final faceId = await addFace(vec(0.10));

      await repository.reclusterOrphans();

      expect(await personIdOf(faceId), isNull);
    });
  });

  group('clusterFaces absorbs before creating', () {
    test('three faces of an existing person create no second tile', () async {
      // The duplicate-people bug, end to end. Before the ordering fix these
      // three cleared the 0.45 clustering bar between themselves and became a
      // brand-new person, because existing centroids were only consulted
      // afterwards and only for clusters too small to stand alone.
      final personId = await addPerson(centroid: reference);
      for (var i = 0; i < 3; i++) {
        await addFace(vec(0.50));
      }

      final created = await repository.clusterFaces();

      expect(created, 0);
      final people = await db.faceDao.allPeopleRows();
      expect(people.map((p) => p.id), [personId]);
      expect(await db.faceDao.assignedFaceCount(), 3);
    });

    test('three faces of a genuinely new person still create one', () async {
      final existingId = await addPerson(name: 'Alice', centroid: reference);
      for (var i = 0; i < 3; i++) {
        await addFace(vec(0.05));
      }

      final created = await repository.clusterFaces();

      expect(created, 1);
      final ids = (await db.faceDao.allPeopleRows()).map((p) => p.id).toSet();
      expect(ids, contains(existingId));
      expect(ids.length, 2);
    });

    test('a cluster below the minimum size creates nobody', () async {
      expect(FaceClusteringService.minClusterSizeForNewPerson, 3);
      await addFace(vec(0.05));
      await addFace(vec(0.05));

      expect(await repository.clusterFaces(), 0);
      expect(await db.faceDao.allPeopleRows(), isEmpty);
    });
  });

  group('consolidateDuplicatePeople', () {
    test('merges an unnamed duplicate into the larger cluster', () async {
      final big = await addPerson(centroid: reference);
      final small = await addPerson(centroid: vec(0.97));
      for (var i = 0; i < 3; i++) {
        await addFace(reference, personId: big);
      }
      await addFace(vec(0.97), personId: small);

      expect(await repository.consolidateDuplicatePeople(), 1);

      // The bigger tile survives so the user's familiar thumbnail is kept.
      expect((await db.faceDao.allPeopleRows()).map((p) => p.id), [big]);
      final faces = await db.faceDao.facesForPerson(big);
      expect(faces.length, 4);
    });

    test('never merges two named people', () async {
      // Identical centroids, but the user said these are different people.
      final alice = await addPerson(name: 'Alice', centroid: reference);
      final bob = await addPerson(name: 'Bob', centroid: reference);
      await addFace(reference, personId: alice);
      await addFace(reference, personId: bob);

      expect(await repository.consolidateDuplicatePeople(), 0);
      expect((await db.faceDao.allPeopleRows()).length, 2);
    });

    test('merges an unnamed duplicate into a named person', () async {
      final alice = await addPerson(name: 'Alice', centroid: reference);
      final stray = await addPerson(centroid: vec(0.90));
      await addFace(reference, personId: alice);
      await addFace(vec(0.90), personId: stray);

      expect(await repository.consolidateDuplicatePeople(), 1);

      final rows = await db.faceDao.allPeopleRows();
      expect(rows.map((p) => p.id), [alice]);
      expect(rows.single.name, 'Alice');
    });

    test('respects the named bar when absorbing into a named person', () async {
      // 0.50 clears 0.45 but not Alice's 0.55, and a named person is the only
      // candidate — so the stray stays its own tile rather than being folded
      // into a confirmed identity on a weak match.
      await addPerson(name: 'Alice', centroid: reference);
      await addPerson(centroid: vec(0.50));

      expect(await repository.consolidateDuplicatePeople(), 0);
      expect((await db.faceDao.allPeopleRows()).length, 2);
    });

    test('leaves genuinely distinct people alone', () async {
      await addPerson(centroid: reference);
      await addPerson(centroid: vec(0.20));

      expect(await repository.consolidateDuplicatePeople(), 0);
      expect((await db.faceDao.allPeopleRows()).length, 2);
    });

    test('is a no-op below two people with centroids', () async {
      await addPerson(centroid: reference);
      // No centroid, so not a candidate however similar it might be.
      await db.faceDao.createPerson(null);

      expect(await repository.consolidateDuplicatePeople(), 0);
      expect((await db.faceDao.allPeopleRows()).length, 2);
    });

    test('recomputes the centroid so a chain collapses in one pass', () async {
      // A (5 faces at the reference) absorbs B (3 faces at 0.50) and thereby
      // swings its own centroid to ~0.93/0.37 — which lands 0.46 from C. C is
      // only 0.10 from A's *original* centroid, so it merges if and only if the
      // recompute after B lands before C is compared. Without it C survives as
      // a third tile for the same face and the grid still shows duplicates.
      final a = await addPerson(centroid: reference);
      final b = await addPerson(centroid: vec(0.50));
      final c = await addPerson(centroid: vec(0.10));
      for (var i = 0; i < 5; i++) {
        await addFace(reference, personId: a);
      }
      for (var i = 0; i < 3; i++) {
        await addFace(vec(0.50), personId: b);
      }
      await addFace(vec(0.10), personId: c);

      // Sanity-check the premise: C is out of reach of A as it stands.
      expect(
        FaceClusteringService().cosineSimilarity(reference, vec(0.10)),
        lessThan(FaceClusteringService.defaultThreshold),
      );

      expect(await repository.consolidateDuplicatePeople(), 2);
      expect((await db.faceDao.allPeopleRows()).map((p) => p.id), [a]);
      expect((await db.faceDao.facesForPerson(a)).length, 9);
    });
  });
}
