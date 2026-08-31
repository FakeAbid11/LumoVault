package com.lumovault.feature.people.repository

import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.sqrt

/**
 * Clusters face embeddings into people groups using average-linkage clustering
 * on 512-dim ArcFace embeddings (w600k_mbf.onnx).
 *
 * InsightFace ArcFace 512-dim embeddings produce cosine similarity
 * 0.50-0.80 for the same person across varied lighting/angles, and
 * 0.10-0.35 for different people.
 */
@Singleton
class FaceGroupingService @Inject constructor() {

    companion object {
        /** Average-linkage clustering threshold. */
        const val DEFAULT_THRESHOLD = 0.45f

        /** Threshold for orphan-to-named-person matching. */
        const val NAMED_THRESHOLD = 0.55f

        /** Threshold for centroid-based reassignment during refinement. */
        const val REFINEMENT_THRESHOLD = 0.50f

        /** Minimum faces required to form a new person cluster. */
        const val MIN_CLUSTER_SIZE = 3
    }

    /**
     * Cosine similarity between two L2-normalized embedding vectors.
     */
    fun cosineSimilarity(a: FloatArray, b: FloatArray): Float {
        if (a.isEmpty() || b.isEmpty()) return 0f
        val length = minOf(a.size, b.size)
        var dot = 0f
        for (i in 0 until length) dot += a[i] * b[i]
        return dot.coerceIn(-1f, 1f)
    }

    /**
     * Compute the centroid (mean) embedding for a list of embeddings.
     */
    fun computeCentroid(embeddings: List<FloatArray>): FloatArray {
        if (embeddings.isEmpty()) return floatArrayOf()
        if (embeddings.size == 1) return embeddings.first().copyOf()
        val dim = embeddings[0].size
        val centroid = FloatArray(dim)
        for (emb in embeddings) {
            for (i in 0 until dim) centroid[i] += emb[i]
        }
        val n = embeddings.size.toFloat()
        for (i in 0 until dim) centroid[i] /= n
        return l2Normalize(centroid)
    }

    /**
     * Average-linkage clustering.
     * Two clusters merge only when the *mean* cosine similarity of all
     * cross-cluster face pairs stays above the threshold.
     */
    fun clusterFaces(
        embeddings: List<FloatArray>,
        threshold: Float = DEFAULT_THRESHOLD,
    ): List<ClusterResult> {
        if (embeddings.isEmpty()) return emptyList()
        if (embeddings.size == 1) {
            return listOf(ClusterResult(listOf(0), embeddings[0].copyOf()))
        }

        // Initialize: each face is its own cluster
        val clusters = embeddings.indices.map { mutableListOf(it) }.toMutableList()
        val centroids = embeddings.map { it.copyOf() }.toMutableList()

        // Pairwise similarity matrix
        val n = embeddings.size
        val simMatrix = Array(n) { FloatArray(n) }
        for (i in 0 until n) {
            for (j in i + 1 until n) {
                val sim = cosineSimilarity(embeddings[i], embeddings[j])
                simMatrix[i][j] = sim
                simMatrix[j][i] = sim
            }
        }

        // Iteratively merge closest clusters
        while (clusters.size > 1) {
            var bestI = -1
            var bestJ = -1
            var bestAvgSim = -1f

            // Find best pair to merge (highest average cross-cluster similarity)
            for (i in clusters.indices) {
                for (j in i + 1 until clusters.size) {
                    val avgSim = averageLinkage(clusters[i], clusters[j], simMatrix)
                    if (avgSim > bestAvgSim) {
                        bestAvgSim = avgSim
                        bestI = i
                        bestJ = j
                    }
                }
            }

            if (bestAvgSim < threshold) break

            // Merge cluster j into i
            clusters[bestI].addAll(clusters[bestJ])
            centroids[bestI] = computeCentroid(clusters[bestI].map { embeddings[it] })
            clusters.removeAt(bestJ)
            centroids.removeAt(bestJ)
        }

        return clusters.mapIndexed { idx, cluster ->
            ClusterResult(
                faceIndices = cluster,
                centroid = centroids[idx],
            )
        }
    }

    /**
     * Refinement pass: reassign faces to their closest cluster centroid
     * if similarity exceeds the refinement threshold.
     */
    fun refineClusters(
        clusters: List<ClusterResult>,
        embeddings: List<FloatArray>,
        threshold: Float = REFINEMENT_THRESHOLD,
    ): List<ClusterResult> {
        val mutableClusters = clusters.map { it.faceIndices.toMutableList() }.toMutableList()
        val centroids = clusters.map { it.centroid }.toMutableList()

        // Collect all face indices that might be reassigned
        val reassigned = mutableListOf<Int>()
        val reassignedFrom = mutableListOf<Int>()

        for (clusterIdx in mutableClusters.indices) {
            for (faceIdx in mutableClusters[clusterIdx].toList()) {
                var bestCluster = clusterIdx
                var bestSim = threshold

                for (otherIdx in centroids.indices) {
                    if (otherIdx == clusterIdx) continue
                    val sim = cosineSimilarity(embeddings[faceIdx], centroids[otherIdx])
                    if (sim > bestSim) {
                        bestSim = sim
                        bestCluster = otherIdx
                    }
                }

                if (bestCluster != clusterIdx) {
                    reassigned.add(faceIdx)
                    reassignedFrom.add(clusterIdx)
                }
            }
        }

        // Apply reassignments
        for (k in reassigned.indices) {
            val faceIdx = reassigned[k]
            val fromCluster = reassignedFrom[k]
            val toCluster = mutableClusters.indices.minByOrNull { idx ->
                if (idx == fromCluster) -1f
                else cosineSimilarity(embeddings[faceIdx], centroids[idx])
            } ?: continue

            mutableClusters[fromCluster].remove(faceIdx)
            mutableClusters[toCluster].add(faceIdx)
        }

        // Recompute centroids
        val result = mutableClusters.mapIndexed { idx, cluster ->
            ClusterResult(
                faceIndices = cluster,
                centroid = if (cluster.isNotEmpty()) {
                    computeCentroid(cluster.map { embeddings[it] })
                } else centroids[idx],
            )
        }

        return result.filter { it.faceIndices.isNotEmpty() }
    }

    /**
     * Merge two people: combine face lists and recompute centroid.
     */
    fun mergePeople(
        target: ClusterResult,
        source: ClusterResult,
        embeddings: List<FloatArray>,
    ): ClusterResult {
        val mergedIndices = target.faceIndices + source.faceIndices
        return ClusterResult(
            faceIndices = mergedIndices,
            centroid = computeCentroid(mergedIndices.map { embeddings[it] }),
        )
    }

    private fun averageLinkage(clusterA: List<Int>, clusterB: List<Int>, simMatrix: Array<FloatArray>): Float {
        var total = 0f
        var count = 0
        for (a in clusterA) {
            for (b in clusterB) {
                total += simMatrix[a][b]
                count++
            }
        }
        return if (count > 0) total / count else 0f
    }

    private fun l2Normalize(embedding: FloatArray): FloatArray {
        var norm = 0f
        for (v in embedding) norm += v * v
        norm = sqrt(norm)
        if (norm > 0f) {
            for (i in embedding.indices) embedding[i] /= norm
        }
        return embedding
    }
}

data class ClusterResult(
    val faceIndices: List<Int>,
    val centroid: FloatArray,
)
