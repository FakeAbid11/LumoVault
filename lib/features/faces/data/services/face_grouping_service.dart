import 'dart:math';

/// Simple agglomerative clustering for face embeddings.
///
/// Uses cosine similarity with a configurable threshold to decide whether
/// two faces belong to the same person. The algorithm is intentionally
/// lightweight (O(n²) pairwise comparison) — sufficient for a personal
/// photo library of tens of thousands of faces.
class FaceGroupingService {
  /// Cosine similarity threshold above which two faces are considered the
  /// same person. Tuned conservatively to avoid false merges; the user can
  /// manually merge groups later.
  static const double similarityThreshold = 0.82;

  /// Given a list of existing group centroids (embedding vectors) and a new
  /// face embedding, returns the index of the best-matching group, or -1 if
  /// no group is similar enough.
  int findMatchingGroup({
    required List<List<double>> groupCentroids,
    required List<double> newEmbedding,
    double threshold = similarityThreshold,
  }) {
    int bestIndex = -1;
    double bestScore = threshold;

    for (int i = 0; i < groupCentroids.length; i++) {
      final score = cosineSimilarity(groupCentroids[i], newEmbedding);
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  /// Compute cosine similarity between two vectors.
  ///
  /// Returns a value in [-1.0, 1.0] where 1.0 means identical direction.
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = sqrt(normA) * sqrt(normB);
    if (denominator == 0) return 0.0;

    return dotProduct / denominator;
  }

  /// Compute the centroid (mean) of a set of embeddings.
  ///
  /// Used to update a group's representative vector after new faces are added.
  static List<double> computeCentroid(List<List<double>> embeddings) {
    if (embeddings.isEmpty) return List.filled(192, 0.0);

    final dim = embeddings[0].length;
    final centroid = List<double>.filled(dim, 0.0);

    for (final embedding in embeddings) {
      for (int i = 0; i < dim && i < embedding.length; i++) {
        centroid[i] += embedding[i];
      }
    }

    for (int i = 0; i < dim; i++) {
      centroid[i] /= embeddings.length;
    }

    return centroid;
  }

  /// Assign a batch of new face embeddings to existing groups, creating new
  /// groups as needed.
  ///
  /// Returns a list of (groupId, isNewGroup) tuples — one per input face —
  /// in the same order as [embeddings].
  List<(int groupId, bool isNew)> assignFaces({
    required List<List<double>> embeddings,
    required List<int> existingGroupIds,
    required List<List<double>> existingCentroids,
  }) {
    final results = <(int groupId, bool isNew)>[];
    // Working copies that grow as we create new groups.
    final groupIds = List<int>.from(existingGroupIds);
    final centroids = List<List<double>>.from(
      existingCentroids.map((c) => List<double>.from(c)),
    );

    for (final embedding in embeddings) {
      final matchIdx = findMatchingGroup(
        groupCentroids: centroids,
        newEmbedding: embedding,
      );

      if (matchIdx >= 0) {
        // Existing group — update its centroid incrementally.
        final gid = groupIds[matchIdx];
        final oldCentroid = centroids[matchIdx];
        final newCentroid = _incrementalCentroid(oldCentroid, embedding, 1);
        centroids[matchIdx] = newCentroid;
        results.add((gid, false));
      } else {
        // New group.
        final newId = groupIds.isEmpty
            ? 1
            : groupIds.reduce(max) + 1;
        groupIds.add(newId);
        centroids.add(List<double>.from(embedding));
        results.add((newId, true));
      }
    }

    return results;
  }

  /// Incrementally update a centroid by blending in a new sample.
  List<double> _incrementalCentroid(
    List<double> current,
    List<double> newSample,
    int currentCount,
  ) {
    final result = List<double>.filled(current.length, 0.0);
    final total = currentCount + 1;
    for (int i = 0; i < current.length && i < newSample.length; i++) {
      result[i] = (current[i] * currentCount + newSample[i]) / total;
    }
    return result;
  }
}
