package com.lumovault.feature.people.repository

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.sqrt

/**
 * Groups detected faces into people clusters using simple embedding comparison.
 * Uses face region, skin tone, and eye/mouth positions for similarity matching.
 */
@Singleton
class FaceGroupingService @Inject constructor() {

    /**
     * Generate a simple embedding from a DetectedFace for comparison.
     * This is a lightweight feature vector (not a full ML embedding).
     */
    fun generateEmbedding(face: DetectedFace, imageWidth: Int, imageHeight: Int): FloatArray {
        val bounds = face.boundingBox

        // Normalize bounding box position
        val centerX = (bounds.centerX().toFloat() / imageWidth).coerceIn(0f, 1f)
        val centerY = (bounds.centerY().toFloat() / imageHeight).coerceIn(0f, 1f)

        // Normalize face size
        val faceWidth = (bounds.width().toFloat() / imageWidth).coerceIn(0f, 1f)
        val faceHeight = (bounds.height().toFloat() / imageHeight).coerceIn(0f, 1f)
        val faceRatio = faceWidth / faceHeight.coerceAtLeast(0.01f)

        // Head pose angles (already in reasonable ranges)
        val eulerX = (face.headEulerAngleX + 90f) / 180f
        val eulerY = (face.headEulerAngleY + 90f) / 180f
        val eulerZ = (face.headEulerAngleZ + 90f) / 180f

        // Eye opening ratios
        val leftEye = face.leftEyeOpenProbability
        val rightEye = face.rightEyeOpenProbability

        // Smile probability
        val smile = face.smilingProbability

        return floatArrayOf(
            centerX, centerY,
            faceWidth, faceHeight, faceRatio,
            eulerX, eulerY, eulerZ,
            leftEye, rightEye,
            smile,
        )
    }

    /**
     * Compute cosine similarity between two embeddings.
     */
    fun cosineSimilarity(a: FloatArray, b: FloatArray): Float {
        if (a.size != b.size) return 0f

        var dotProduct = 0f
        var normA = 0f
        var normB = 0f

        for (i in a.indices) {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        val denominator = sqrt(normA) * sqrt(normB)
        return if (denominator > 0f) dotProduct / denominator else 0f
    }

    /**
     * Assign faces to existing people clusters, or create new ones.
     * Returns a map of personId -> list of face indices.
     */
    fun clusterFaces(
        embeddings: List<FloatArray>,
        threshold: Float = 0.75f,
    ): List<ClusterResult> {
        if (embeddings.isEmpty()) return emptyList()

        val clusters = mutableListOf<MutableList<Int>>()
        val clusterCentroids = mutableListOf<FloatArray>()

        for (i in embeddings.indices) {
            var bestCluster = -1
            var bestSimilarity = threshold

            for (j in clusters.indices) {
                val similarity = cosineSimilarity(embeddings[i], clusterCentroids[j])
                if (similarity > bestSimilarity) {
                    bestSimilarity = similarity
                    bestCluster = j
                }
            }

            if (bestCluster >= 0) {
                clusters[bestCluster].add(i)
                // Update centroid as running average
                val size = clusters[bestCluster].size
                clusterCentroids[bestCluster] = FloatArray(embeddings[0].size) { k ->
                    (clusterCentroids[bestCluster][k] * (size - 1) + embeddings[i][k]) / size
                }
            } else {
                clusters.add(mutableListOf(i))
                clusterCentroids.add(embeddings[i].copyOf())
            }
        }

        return clusters.map { cluster ->
            ClusterResult(
                faceIndices = cluster,
                centroid = clusterCentroids[clusters.indexOf(cluster)],
            )
        }
    }

    /**
     * Merge two people (reassign all faces from personB to personA).
     */
    fun mergeEmbeddings(centroidA: FloatArray, countA: Int, centroidB: FloatArray): FloatArray {
        return FloatArray(centroidA.size) { i ->
            (centroidA[i] * countA + centroidB[i]) / (countA + 1)
        }
    }

    companion object {
        private const val TAG = "FaceGroupingService"
    }
}

data class ClusterResult(
    val faceIndices: List<Int>,
    val centroid: FloatArray,
)
