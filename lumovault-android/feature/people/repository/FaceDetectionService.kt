package com.lumovault.feature.people.repository

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

data class DetectedFace(
    val boundingBox: android.graphics.Rect,
    val leftEyeOpenProbability: Float = 0f,
    val rightEyeOpenProbability: Float = 0f,
    val smilingProbability: Float = 0f,
    val headEulerAngleX: Float = 0f,
    val headEulerAngleY: Float = 0f,
    val headEulerAngleZ: Float = 0f,
    val faceBitmap: Bitmap,
)

@Singleton
class FaceDetectionService @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val detector by lazy {
        val options = FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .setMinFaceSize(0.1f)
            .build()

        FaceDetection.getClient(options)
    }

    /**
     * Detect faces in an image file.
     * Returns a list of cropped face bitmaps with metadata.
     */
    suspend fun detectFaces(filePath: String): List<DetectedFace> = withContext(Dispatchers.IO) {
        try {
            val bitmap = loadBitmapFromFile(filePath) ?: return@withContext emptyList()

            val image = InputImage.fromBitmap(bitmap, 0)
            val faces = detector.process(image).await()

            faces.map { face ->
                val bounds = face.boundingBox

                // Clamp bounds to bitmap
                val left = bounds.left.coerceIn(0, bitmap.width)
                val top = bounds.top.coerceIn(0, bitmap.height)
                val right = bounds.right.coerceIn(left, bitmap.width)
                val bottom = bounds.bottom.coerceIn(top, bitmap.height)

                val faceBitmap = Bitmap.createBitmap(
                    bitmap,
                    left,
                    top,
                    (right - left).coerceAtLeast(1),
                    (bottom - top).coerceAtLeast(1),
                )

                DetectedFace(
                    boundingBox = bounds,
                    leftEyeOpenProbability = face.leftEyeOpenProbability ?: 0f,
                    rightEyeOpenProbability = face.rightEyeOpenProbability ?: 0f,
                    smilingProbability = face.smilingProbability ?: 0f,
                    headEulerAngleX = face.headEulerAngleX,
                    headEulerAngleY = face.headEulerAngleY,
                    headEulerAngleZ = face.headEulerAngleZ,
                    faceBitmap = faceBitmap,
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /**
     * Extract a thumbnail-quality face bitmap (64x64) for embedding.
     */
    fun getFaceThumbnail(faceBitmap: Bitmap): Bitmap {
        return Bitmap.createScaledBitmap(faceBitmap, 64, 64, true)
    }

    private fun loadBitmapFromFile(filePath: String): Bitmap? {
        return try {
            val file = File(filePath)
            if (!file.exists()) return null

            // Decode bounds
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeFile(filePath, options)

            // Calculate sample size for memory efficiency
            val maxDim = 1024
            val sampleSize = calculateSampleSize(options.outWidth, options.outHeight, maxDim)

            val decodeOptions = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
            }
            BitmapFactory.decodeFile(filePath, decodeOptions)
        } catch (e: Exception) {
            null
        }
    }

    private fun calculateSampleSize(width: Int, height: Int, maxDim: Int): Int {
        var sampleSize = 1
        while (width / sampleSize > maxDim || height / sampleSize > maxDim) {
            sampleSize *= 2
        }
        return sampleSize
    }

    fun close() {
        detector.close()
    }
}
