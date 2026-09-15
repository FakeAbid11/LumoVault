import 'dart:math';

/// Service for clustering faces into people groups using face embeddings.
///
/// Uses cosine similarity on 512-dim InsightFace ArcFace embeddings
/// (w600k_mbf.onnx) for comparison.
/// Supports adaptive thresholds, centroid computation, and refinement.
class FaceClusteringService {
  /// Average-linkage clustering threshold. Two clusters merge only when
  /// the *mean* cosine similarity of all cross-cluster face pairs stays
  /// above this value. This prevents single-linkage "chaining" where a
  /// loose chain of pairwise similarities merges distinct people.
  ///
  /// InsightFace ArcFace 512-dim embeddings produce cosine similarity
  /// 0.50-0.80 for the same person across varied lighting/angles, and
  /// 0.10-0.35 for different people. 0.45 is the sweet spot: high enough
  /// to separate different people, low enough to keep the same person
  /// together across lighting/angle variation.
  static const double defaultThreshold = 0.45;

  /// Threshold for orphan-to-named-person matching.
  /// Named people have confirmed identity, so require higher similarity.
  static const double namedThreshold = 0.55;

  /// Threshold for centroid-based reassignment during refinement.
  /// After initial clustering, faces closer to another cluster's centroid
  /// than their own are reassigned if similarity exceeds this value.
  static const double refinementThreshold = 0.50;

  /// Minimum number of faces required to form a new person cluster.
  /// Clusters with fewer faces are left unassigned and may be picked up
  /// later by [FaceRepository.reclusterOrphans] if a matching person
  /// accumulates enough faces. Mirrors Immich's DBSCAN "core point" rule.
  static const int minClusterSizeForNewPerson = 3;

  /// Calculate cosine similarity between two embedding vectors.
  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;

    final length = min(a.length, b.length);
    double dotProduct = 0;
    double normA = 0;
    double normB = 0;

    for (var i = 0; i < length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = sqrt(normA) * sqrt(normB);
    if (denominator == 0) return 0.0;

    return dotProduct / denominator;
  }

  /// Compute the centroid (mean) embedding for a list of embeddings.
  List<double> computeCentroid(List<List<double>> embeddings) {
    if (embeddings.isEmpty) return [];
    if (embeddings.length == 1) return embeddings.first;

    final dim = embeddings.first.length;
    final centroid = List<double>.filled(dim, 0.0);

    for (final emb in embeddings) {
      for (var i = 0; i < min(dim, emb.length); i++) {
        centroid[i] += emb[i];
      }
    }

    // Normalize
    for (var i = 0; i < dim; i++) {
      centroid[i] /= embeddings.length;
    }

    // Re-normalize to unit vector
    double norm = 0;
    for (final v in centroid) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm > 0) {
      for (var i = 0; i < dim; i++) {
        centroid[i] /= norm;
      }
    }

    return centroid;
  }

  /// Cluster faces using average-linkage agglomerative clustering.
  ///
  /// Unlike single-linkage (Union-Find), this prevents "chaining" where
  /// a loose chain of pairwise similarities merges distinct people.
  /// Two clusters merge only when the *mean* cross-cluster similarity
  /// stays above [defaultThreshold].
  List<List<int>> clusterFaces({required List<List<double>> embeddings}) {
    final n = embeddings.length;
    if (n == 0) return [];
    if (n == 1) {
      return [
        [0],
      ];
    }

    // Average linkage is tracked as a running sum + pair count per cluster
    // pair, so a merge costs O(n) to fold in rather than re-walking every
    // cross-cluster face pair (which made large batches unusably slow).
    final sum = List.generate(n, (_) => List<double>.filled(n, 0.0));
    final count = List.generate(n, (_) => List<int>.filled(n, 1));
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final s = cosineSimilarity(embeddings[i], embeddings[j]);
        sum[i][j] = s;
        sum[j][i] = s;
      }
    }

    // Each cluster is a list of face indices; start with N singletons.
    final clusters = List.generate(n, (i) => [i]);
    // Track which cluster index is still alive (false = merged away).
    final alive = List<bool>.filled(n, true);

    while (true) {
      // Find the best pair of alive clusters to merge.
      var bestI = -1;
      var bestJ = -1;
      var bestAvg = 0.0;

      for (var i = 0; i < n; i++) {
        if (!alive[i]) continue;
        for (var j = i + 1; j < n; j++) {
          if (!alive[j]) continue;
          final pairs = count[i][j];
          final avg = pairs > 0 ? sum[i][j] / pairs : 0.0;
          if (avg > bestAvg) {
            bestAvg = avg;
            bestI = i;
            bestJ = j;
          }
        }
      }

      // Stop if the best merge would drop below threshold.
      if (bestI < 0 || bestAvg < defaultThreshold) break;

      // Merge cluster bestJ into bestI and fold its similarity sums in.
      clusters[bestI].addAll(clusters[bestJ]);
      alive[bestJ] = false;
      for (var k = 0; k < n; k++) {
        if (!alive[k] || k == bestI) continue;
        sum[bestI][k] += sum[bestJ][k];
        sum[k][bestI] = sum[bestI][k];
        count[bestI][k] += count[bestJ][k];
        count[k][bestI] = count[bestI][k];
      }
    }

    return [
      for (var c = 0; c < n; c++)
        if (alive[c]) clusters[c],
    ];
  }

  /// Refine clusters by reassigning edge-case faces to nearest centroid.
  ///
  /// After initial clustering, some faces may be on the boundary between
  /// two clusters. This method reassigns them to the nearest centroid
  /// if the similarity exceeds the refinement threshold.
  List<List<int>> refineClusters({
    required List<List<double>> embeddings,
    required List<List<int>> clusters,
  }) {
    if (clusters.length <= 1) return clusters;

    // Compute centroids for each cluster
    final centroids = <int, List<double>>{};
    for (var c = 0; c < clusters.length; c++) {
      final clusterEmbeddings = clusters[c].map((i) => embeddings[i]).toList();
      centroids[c] = computeCentroid(clusterEmbeddings);
    }

    // Build a map from face index to current cluster
    final faceToCluster = <int, int>{};
    for (var c = 0; c < clusters.length; c++) {
      for (final i in clusters[c]) {
        faceToCluster[i] = c;
      }
    }

    // Reassign faces that are closer to another centroid
    final reassignments = <int, int>{};
    for (var i = 0; i < embeddings.length; i++) {
      final currentCluster = faceToCluster[i] ?? 0;
      var bestCluster = currentCluster;
      var bestSimilarity = 0.0;

      for (var c = 0; c < clusters.length; c++) {
        final sim = cosineSimilarity(embeddings[i], centroids[c]!);
        if (sim > bestSimilarity) {
          bestSimilarity = sim;
          bestCluster = c;
        }
      }

      // Reassign if closer to another cluster and above refinement threshold
      if (bestCluster != currentCluster &&
          bestSimilarity >= refinementThreshold) {
        reassignments[i] = bestCluster;
      }
    }

    // Apply reassignments
    if (reassignments.isNotEmpty) {
      for (final entry in reassignments.entries) {
        final faceIdx = entry.key;
        final newCluster = entry.value;
        final oldCluster = faceToCluster[faceIdx]!;

        clusters[oldCluster].remove(faceIdx);
        clusters[newCluster].add(faceIdx);
      }

      // Remove empty clusters
      clusters.removeWhere((c) => c.isEmpty);
    }

    return clusters;
  }
}

/// Runs [FaceClusteringService.clusterFaces] followed by
/// [FaceClusteringService.refineClusters] on a plain list of embeddings.
///
/// Top-level so it can be handed to `compute()` — clustering is pure CPU work
/// and would otherwise jank the UI while a scan is running.
List<List<int>> clusterAndRefine(List<List<double>> embeddings) {
  final service = FaceClusteringService();
  final clusters = service.clusterFaces(embeddings: embeddings);
  return service.refineClusters(embeddings: embeddings, clusters: clusters);
}
