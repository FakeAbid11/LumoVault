package com.lumovault.feature.people.repository

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.Rect
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.FloatBuffer
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.sqrt

/**
 * ONNX-based face detection (SCRFD det_500m.onnx) and embedding (w600k_mbf.onnx).
 * Produces 512-dim ArcFace embeddings for cosine-similarity clustering.
 */
@Singleton
class OnnxFaceService @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private var ortEnv: OrtEnvironment? = null
    private var detectorSession: OrtSession? = null
    private var embedderSession: OrtSession? = null
    private var initialized = false

    // SCRFD detector constants
    private val detectorInputSize = 640
    private val scrfdStrides = intArrayOf(8, 16, 32)
    private val nmsThreshold = 0.4f
    private val scoreThreshold = 0.5f

    // Embedder constants
    private val embedderInputSize = 112

    val isReady: Boolean get() = initialized

    suspend fun init() = withContext(Dispatchers.IO) {
        if (initialized) return@withContext
        try {
            ortEnv = OrtEnvironment.getEnvironment()

            val detBytes = context.assets.open("models/det_500m.onnx").use { it.readBytes() }
            detectorSession = ortEnv!!.createSession(detBytes)

            val embBytes = context.assets.open("models/w600k_mbf.onnx").use { it.readBytes() }
            embedderSession = ortEnv!!.createSession(embBytes)

            initialized = true
        } catch (e: Exception) {
            initialized = false
        }
    }

    /**
     * Detect faces and compute 512-dim embeddings.
     */
    suspend fun detectAndEmbed(filePath: String): List<DetectedFaceWithEmbedding> = withContext(Dispatchers.IO) {
        if (!initialized) return@withContext emptyList()

        try {
            val bitmap = loadBitmap(filePath) ?: return@withContext emptyList()
            val detections = detectFaces(bitmap)
            val faces = mutableListOf<DetectedFaceWithEmbedding>()

            for (det in detections) {
                val faceBitmap = cropAndAlignFace(bitmap, det.box)
                if (faceBitmap != null) {
                    val embedding = computeEmbedding(faceBitmap)
                    if (embedding != null) {
                        faces.add(
                            DetectedFaceWithEmbedding(
                                boundingBox = det.box,
                                score = det.score,
                                embedding = embedding,
                                filePath = filePath,
                            )
                        )
                    }
                }
            }

            faces
        } catch (e: Exception) {
            emptyList()
        }
    }

    /**
     * Compute 512-dim embedding for a face bitmap.
     */
    suspend fun computeEmbedding(faceBitmap: Bitmap): FloatArray? = withContext(Dispatchers.IO) {
        if (!initialized || embedderSession == null) return@withContext null

        try {
            val resized = Bitmap.createScaledBitmap(faceBitmap, embedderInputSize, embedderInputSize, true)
            val inputTensor = preprocessFace(resized)

            val inputName = embedderSession!!.inputNames.first()
            val results = embedderSession!!.run(mapOf(inputName to inputTensor))
            val outputName = embedderSession!!.outputNames.first()
            val output = results[outputName] ?: return@withContext null

            val rawEmbedding = (output.value as Array<FloatArray>)[0]

            inputTensor.close()
            results.close()

            // L2-normalize
            l2Normalize(rawEmbedding)
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Cosine similarity between two embeddings.
     */
    fun cosineSimilarity(a: FloatArray, b: FloatArray): Float {
        if (a.size != b.size) return 0f
        var dot = 0f; var normA = 0f; var normB = 0f
        for (i in a.indices) { dot += a[i] * b[i]; normA += a[i] * a[i]; normB += b[i] * b[i] }
        val denom = sqrt(normA) * sqrt(normB)
        return if (denom > 0f) dot / denom else 0f
    }

    private fun detectFaces(bitmap: Bitmap): List<ScrfdDetection> {
        val resized = Bitmap.createScaledBitmap(bitmap, detectorInputSize, detectorInputSize, true)
        val inputTensor = preprocessDetector(resized)

        val inputName = detectorSession!!.inputNames.first()
        val results = detectorSession!!.run(mapOf(inputName to inputTensor))

        // Parse SCRFD outputs — simplified NMS
        val detections = mutableListOf<ScrfdDetection>()
        val outputNames = detectorSession!!.outputNames.toList()

        // Collect score boxes and landmark data from outputs
        val allScores = mutableListOf<Float>()
        val allBoxes = mutableListOf<Rect>()

        // SCRFD outputs: bbox_and_kps arrays per stride
        for (name in outputNames) {
            val output = results[name] ?: continue
            val data = output.value
            if (data is Array<*>) {
                // Process based on shape
                @Suppress("UNCHECKED_CAST")
                val arr = data as? Array<FloatArray> ?: continue
                for (row in arr) {
                    if (row.size >= 5) {
                        val score = row[4]
                        if (score >= scoreThreshold) {
                            allScores.add(score)
                            // Decode box from anchor + stride offsets
                            allBoxes.add(Rect(
                                (row[0] * bitmap.width / detectorInputSize).toInt().coerceIn(0, bitmap.width),
                                (row[1] * bitmap.height / detectorInputSize).toInt().coerceIn(0, bitmap.height),
                                (row[2] * bitmap.width / detectorInputSize).toInt().coerceIn(0, bitmap.width),
                                (row[3] * bitmap.height / detectorInputSize).toInt().coerceIn(0, bitmap.height),
                            ))
                        }
                    }
                }
            }
        }

        inputTensor.close()
        results.close()

        // Apply NMS
        val keep = nms(allBoxes, allScores, nmsThreshold)
        return keep.map { idx ->
            ScrfdDetection(box = allBoxes[idx], score = allScores[idx])
        }
    }

    private fun cropAndAlignFace(bitmap: Bitmap, box: Rect): Bitmap? {
        val padding = ((box.width() * 0.2).toInt())
        val left = (box.left - padding).coerceAtLeast(0)
        val top = (box.top - padding).coerceAtLeast(0)
        val right = (box.right + padding).coerceAtMost(bitmap.width)
        val bottom = (box.bottom + padding).coerceAtMost(bitmap.height)
        val w = right - left
        val h = bottom - top
        if (w <= 0 || h <= 0) return null
        return Bitmap.createBitmap(bitmap, left, top, w, h)
    }

    private fun preprocessDetector(bitmap: Bitmap): OnnxTensor {
        val buffer = FloatBuffer.allocate(3 * detectorInputSize * detectorInputSize)
        for (c in 0 until 3) {
            for (y in 0 until detectorInputSize) {
                for (x in 0 until detectorInputSize) {
                    val pixel = bitmap.getPixel(x, y)
                    val value = when (c) {
                        0 -> ((pixel shr 16 and 0xFF) - 127.5f) / 128f
                        1 -> ((pixel shr 8 and 0xFF) - 127.5f) / 128f
                        else -> ((pixel and 0xFF) - 127.5f) / 128f
                    }
                    buffer.put(value)
                }
            }
        }
        buffer.rewind()
        return OnnxTensor.createTensor(ortEnv!!, buffer, longArrayOf(1, 3, detectorInputSize.toLong(), detectorInputSize.toLong()))
    }

    private fun preprocessFace(bitmap: Bitmap): OnnxTensor {
        val buffer = FloatBuffer.allocate(3 * embedderInputSize * embedderInputSize)
        for (c in 0 until 3) {
            for (y in 0 until embedderInputSize) {
                for (x in 0 until embedderInputSize) {
                    val pixel = bitmap.getPixel(x, y)
                    val value = when (c) {
                        0 -> ((pixel shr 16 and 0xFF) - 127.5f) / 128f
                        1 -> ((pixel shr 8 and 0xFF) - 127.5f) / 128f
                        else -> ((pixel and 0xFF) - 127.5f) / 128f
                    }
                    buffer.put(value)
                }
            }
        }
        buffer.rewind()
        return OnnxTensor.createTensor(ortEnv!!, buffer, longArrayOf(1, 3, embedderInputSize.toLong(), embedderInputSize.toLong()))
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

    private fun nms(boxes: List<Rect>, scores: List<Float>, threshold: Float): List<Int> {
        val sorted = scores.indices.sortedByDescending { scores[it] }
        val keep = mutableListOf<Int>()
        val suppressed = BooleanArray(boxes.size)

        for (i in sorted) {
            if (suppressed[i]) continue
            keep.add(i)
            for (j in sorted) {
                if (j <= i || suppressed[j]) continue
                if (iou(boxes[i], boxes[j]) > threshold) {
                    suppressed[j] = true
                }
            }
        }
        return keep
    }

    private fun iou(a: Rect, b: Rect): Float {
        val interLeft = maxOf(a.left, b.left)
        val interTop = maxOf(a.top, b.top)
        val interRight = minOf(a.right, b.right)
        val interBottom = minOf(a.bottom, b.bottom)
        val interArea = maxOf(0, interRight - interLeft) * maxOf(0, interBottom - interTop)
        val aArea = a.width() * a.height()
        val bArea = b.width() * b.height()
        val union = aArea + bArea - interArea
        return if (union > 0) interArea.toFloat() / union else 0f
    }

    private fun loadBitmap(filePath: String): Bitmap? {
        return try {
            val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(filePath, opts)
            val sampleSize = calculateSampleSize(opts.outWidth, opts.outHeight, 1024)
            BitmapFactory.decodeFile(filePath, BitmapFactory.Options().apply { inSampleSize = sampleSize })
        } catch (e: Exception) { null }
    }

    private fun calculateSampleSize(w: Int, h: Int, max: Int): Int {
        var s = 1
        while (w / s > max || h / s > max) s *= 2
        return s
    }

    fun close() {
        detectorSession?.close()
        embedderSession?.close()
        detectorSession = null
        embedderSession = null
        ortEnv?.close()
        ortEnv = null
        initialized = false
    }
}

data class DetectedFaceWithEmbedding(
    val boundingBox: Rect,
    val score: Float,
    val embedding: FloatArray,
    val filePath: String,
)

data class ScrfdDetection(
    val box: Rect,
    val score: Float,
)
