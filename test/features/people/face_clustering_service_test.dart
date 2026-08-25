import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/people/data/services/face_clustering_service.dart';

/// A unit-length embedding pointing mostly along [axis], nudged by [jitter] so
/// members of one group are similar but not identical.
List<double> _embedding(int axis, {double jitter = 0.0, int dim = 8}) {
  final v = List<double>.filled(dim, 0.0);
  v[axis] = 1.0;
  v[(axis + 1) % dim] = jitter;
  final norm = math.sqrt(v.fold<double>(0, (a, b) => a + b * b));
  return v.map((e) => e / norm).toList();
}

void main() {
  final service = FaceClusteringService();

  group('cosineSimilarity', () {
    test('is 1 for identical vectors and 0 for orthogonal ones', () {
      expect(
        service.cosineSimilarity(_embedding(0), _embedding(0)),
        closeTo(1.0, 1e-9),
      );
      expect(
        service.cosineSimilarity(_embedding(0), _embedding(4)),
        closeTo(0.0, 1e-9),
      );
    });

    test('returns 0 when either vector is empty', () {
      expect(service.cosineSimilarity(const [], _embedding(0)), 0.0);
      expect(service.cosineSimilarity(_embedding(0), const []), 0.0);
    });

    test('compares over the shared prefix when lengths differ', () {
      // Only the overlapping leading dimensions are scored.
      expect(
        service.cosineSimilarity(const [1.0, 0.0], _embedding(0)),
        closeTo(1.0, 1e-9),
      );
    });
  });

  group('clusterFaces', () {
    test('returns nothing for no embeddings', () {
      expect(service.clusterFaces(embeddings: const []), isEmpty);
    });

    test('returns one singleton cluster for a single embedding', () {
      expect(service.clusterFaces(embeddings: [_embedding(0)]), [
        [0],
      ]);
    });

    test('separates two distinct people without chaining them', () {
      // Group A around axis 0, group B around axis 4 — orthogonal, so no
      // cross-group similarity can pull them together.
      final embeddings = [
        _embedding(0, jitter: 0.05),
        _embedding(0, jitter: 0.10),
        _embedding(0, jitter: 0.15),
        _embedding(4, jitter: 0.05),
        _embedding(4, jitter: 0.10),
        _embedding(4, jitter: 0.15),
      ];

      final clusters = service.clusterFaces(embeddings: embeddings);

      expect(clusters, hasLength(2));
      final asSets = clusters.map((c) => c.toSet()).toList();
      expect(
        asSets,
        containsAll([
          {0, 1, 2},
          {3, 4, 5},
        ]),
      );
    });

    test('groups every near-duplicate of one person into a single cluster', () {
      final embeddings = List.generate(
        5,
        (i) => _embedding(2, jitter: 0.02 * i),
      );

      final clusters = service.clusterFaces(embeddings: embeddings);

      expect(clusters, hasLength(1));
      expect(clusters.single.toSet(), {0, 1, 2, 3, 4});
    });

    test('leaves mutually dissimilar faces as singletons', () {
      final embeddings = [_embedding(0), _embedding(2), _embedding(4)];

      final clusters = service.clusterFaces(embeddings: embeddings);

      expect(clusters, hasLength(3));
      expect(clusters.every((c) => c.length == 1), isTrue);
    });

    test('assigns every input index to exactly one cluster', () {
      final embeddings = [
        _embedding(0, jitter: 0.05),
        _embedding(0, jitter: 0.10),
        _embedding(4, jitter: 0.05),
        _embedding(6),
      ];

      final clusters = service.clusterFaces(embeddings: embeddings);
      final flattened = clusters.expand((c) => c).toList();

      expect(flattened, hasLength(embeddings.length));
      expect(flattened.toSet(), {0, 1, 2, 3});
    });
  });

  group('computeCentroid', () {
    test('averages the members and returns a unit vector', () {
      final centroid = service.computeCentroid([
        _embedding(0, jitter: 0.05),
        _embedding(0, jitter: 0.15),
      ]);

      final norm = math.sqrt(centroid.fold<double>(0, (a, b) => a + b * b));
      expect(norm, closeTo(1.0, 1e-9));
      // Still points at the group's dominant axis.
      expect(centroid[0], greaterThan(0.9));
    });
  });

  group('clusterAndRefine', () {
    test('is the isolate entry point and preserves the split', () {
      final embeddings = [
        _embedding(0, jitter: 0.05),
        _embedding(0, jitter: 0.10),
        _embedding(0, jitter: 0.15),
        _embedding(4, jitter: 0.05),
        _embedding(4, jitter: 0.10),
        _embedding(4, jitter: 0.15),
      ];

      final clusters = clusterAndRefine(embeddings);

      expect(clusters, hasLength(2));
      expect(clusters.expand((c) => c).toSet(), {0, 1, 2, 3, 4, 5});
    });
  });
}
