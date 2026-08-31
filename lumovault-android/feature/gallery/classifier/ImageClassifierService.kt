package com.lumovault.feature.gallery.classifier

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.FloatBuffer
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ImageClassifierService @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private var ortEnv: OrtEnvironment? = null
    private var session: OrtSession? = null
    private var initialized = false

    private val inputSize = 224
    private val threshold = 0.15
    private val maxLabels = 5

    val isReady: Boolean get() = initialized

    suspend fun init() = withContext(Dispatchers.IO) {
        if (initialized) return@withContext
        try {
            ortEnv = OrtEnvironment.getEnvironment()
            val modelBytes = context.assets.open("models/efficientnet_lite0.onnx").use { it.readBytes() }
            session = ortEnv!!.createSession(modelBytes)
            initialized = true
        } catch (e: Exception) {
            initialized = false
        }
    }

    /**
     * Classify a bitmap and return top labels (e.g. ["beach", "sunset"]).
     */
    suspend fun classify(bitmap: Bitmap): List<String> = withContext(Dispatchers.IO) {
        if (!initialized) return@withContext emptyList()

        try {
            val resized = Bitmap.createScaledBitmap(bitmap, inputSize, inputSize, true)
            val inputTensor = preprocess(resized)

            val inputName = session!!.inputNames.first()
            val results = session!!.run(mapOf(inputName to inputTensor))

            val outputName = session!!.outputNames.first()
            val output = results[outputName] ?: return@withContext emptyList()
            val logits = (output.value as Array<FloatArray>)[0]

            inputTensor.close()
            results.close()

            decodeTopLabels(logits)
        } catch (e: Exception) {
            emptyList()
        }
    }

    /**
     * Classify from file path.
     */
    suspend fun classifyFile(filePath: String): List<String> {
        val bitmap = BitmapFactory.decodeFile(filePath) ?: return emptyList()
        return classify(bitmap)
    }

    private fun preprocess(bitmap: Bitmap): OnnxTensor {
        val buffer = FloatBuffer.allocate(3 * inputSize * inputSize)
        for (c in 0 until 3) {
            for (y in 0 until inputSize) {
                for (x in 0 until inputSize) {
                    val pixel = bitmap.getPixel(x, y)
                    val value = when (c) {
                        0 -> (pixel shr 16 and 0xFF) / 255.0f
                        1 -> (pixel shr 8 and 0xFF) / 255.0f
                        else -> (pixel and 0xFF) / 255.0f
                    }
                    buffer.put(value)
                }
            }
        }
        buffer.rewind()
        return OnnxTensor.createTensor(ortEnv!!, buffer, longArrayOf(1, 3, inputSize.toLong(), inputSize.toLong()))
    }

    private fun decodeTopLabels(logits: FloatArray): List<String> {
        // Softmax
        val maxLogit = logits.max()
        val exps = logits.map { Math.exp((it - maxLogit).toDouble()).toFloat() }
        val sumExp = exps.sum()
        val probs = exps.map { it / sumExp }

        // Top-N above threshold
        return probs.indices
            .filter { probs[it] >= threshold }
            .sortedByDescending { probs[it] }
            .take(maxLabels)
            .mapNotNull { LabelMap.getLabel(it) }
            .map { "ai_${it.lowercase().replace(" ", "_")}" }
    }

    fun close() {
        session?.close()
        session = null
        ortEnv?.close()
        ortEnv = null
        initialized = false
    }
}
