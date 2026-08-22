import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/faces/data/services/face_grouping_service.dart';

void main() {
  group('FaceGroupingService', () {
    late FaceGroupingService service;

    setUp(() {
      service = FaceGroupingService();
    });

    group('cosineSimilarity', () {
      test('returns 1.0 for identical vectors', () {
        final a = List<double>.filled(192, 0.5);
        final b = List<double>.filled(192, 0.5);
        expect(FaceGroupingService.cosineSimilarity(a, b), closeTo(1.0, 1e-6));
      });

      test('returns 0.0 for orthogonal vectors', () {
        final a = List<double>.filled(192, 0.0);
        a[0] = 1.0;
        final b = List<double>.filled(192, 0.0);
        b[1] = 1.0;
        expect(
          FaceGroupingService.cosineSimilarity(a, b),
          closeTo(0.0, 1e-6),
        );
      });

      test('returns 0.0 for zero vectors', () {
        final a = List<double>.filled(192, 0.0);
        final b = List<double>.filled(192, 0.0);
        expect(FaceGroupingService.cosineSimilarity(a, b), 0.0);
      });

      test('returns 0.0 for different-length vectors', () {
        final a = List<double>.filled(192, 1.0);
        final b = List<double>.filled(64, 1.0);
        expect(FaceGroupingService.cosineSimilarity(a, b), 0.0);
      });

      test('returns negative value for opposite vectors', () {
        final a = List<double>.filled(192, 1.0);
        final b = List<double>.filled(192, -1.0);
        expect(
          FaceGroupingService.cosineSimilarity(a, b),
          closeTo(-1.0, 1e-6),
        );
      });
    });

    group('computeCentroid', () {
      test('returns zero vector for empty input', () {
        final centroid = FaceGroupingService.computeCentroid([]);
        expect(centroid, hasLength(192));
        expect(centroid, everyElement(0.0));
      });

      test('returns the single embedding for one input', () {
        final embedding = List<double>.generate(192, (i) => i.toDouble());
        final centroid = FaceGroupingService.computeCentroid([embedding]);
        expect(centroid, equals(embedding));
      });

      test('averages two embeddings correctly', () {
        final a = List<double>.filled(192, 2.0);
        final b = List<double>.filled(192, 4.0);
        final centroid = FaceGroupingService.computeCentroid([a, b]);
        expect(centroid, everyElement(3.0));
      });
    });

    group('findMatchingGroup', () {
      test('returns -1 when no groups exist', () {
        final result = service.findMatchingGroup(
          groupCentroids: [],
          newEmbedding: List<double>.filled(192, 0.5),
        );
        expect(result, -1);
      });

      test('returns index of matching group when similarity is high', () {
        final embedding = List<double>.filled(192, 0.5);
        final result = service.findMatchingGroup(
          groupCentroids: [embedding],
          newEmbedding: List<double>.filled(192, 0.5),
        );
        expect(result, 0);
      });

      test('returns -1 when no group is similar enough', () {
        final centroid = List<double>.filled(192, 0.0);
        centroid[0] = 1.0;
        final newEmbedding = List<double>.filled(192, 0.0);
        newEmbedding[1] = 1.0;

        final result = service.findMatchingGroup(
          groupCentroids: [centroid],
          newEmbedding: newEmbedding,
        );
        expect(result, -1);
      });

      test('returns best matching group index', () {
        final close = List<double>.filled(192, 0.5);
        final far = List<double>.filled(192, 0.0);
        far[0] = 1.0;
        final newEmbedding = List<double>.filled(192, 0.5);

        final result = service.findMatchingGroup(
          groupCentroids: [far, close],
          newEmbedding: newEmbedding,
        );
        expect(result, 1);
      });
    });

    group('assignFaces', () {
      test('creates new group for unmatched face', () {
        final result = service.assignFaces(
          embeddings: [List<double>.filled(192, 0.5)],
          existingGroupIds: [],
          existingCentroids: [],
        );

        expect(result, hasLength(1));
        expect(result[0].$2, isTrue); // isNew
      });

      test('assigns to existing group when similar', () {
        final embedding = List<double>.filled(192, 0.5);
        final result = service.assignFaces(
          embeddings: [List<double>.filled(192, 0.5)],
          existingGroupIds: [42],
          existingCentroids: [embedding],
        );

        expect(result, hasLength(1));
        expect(result[0].$1, 42); // groupId
        expect(result[0].$2, isFalse); // isNew
      });

      test('creates new group and assigns to existing', () {
        final existing = List<double>.filled(192, 0.5);
        final newFace = List<double>.filled(192, 0.0);
        newFace[0] = 1.0;

        final result = service.assignFaces(
          embeddings: [existing, newFace],
          existingGroupIds: [10],
          existingCentroids: [existing],
        );

        expect(result, hasLength(2));
        expect(result[0].$1, 10); // first goes to existing group
        expect(result[0].$2, isFalse);
        expect(result[1].$2, isTrue); // second creates new group
      });
    });
  });
}
