package com.lumovault.feature.metadata.repository

import android.util.Log
import com.lumovault.core.database.daos.MediaDao
import com.lumovault.core.tdlib.TdLibConnectionManager
import com.lumovault.core.storage.EncryptedSettingsStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages the manifest file that tracks all backed-up media metadata.
 * The manifest is uploaded as a pinned message in the storage channel.
 */
@Singleton
class ManifestService @Inject constructor(
    private val connectionManager: TdLibConnectionManager,
    private val encryptedSettings: EncryptedSettingsStore,
) {
    suspend fun uploadManifest(
        channelId: Int,
        manifest: Manifest,
    ): Result<Long> = withContext(Dispatchers.IO) {
        try {
            val json = manifestToJson(manifest)
            val caption = JSONObject().apply {
                put("@type", "formattedText")
                put("text", "LUMOVAULT_MANIFEST|$json")
            }

            val inputMessage = mapOf(
                "@type" to "inputMessageDocument",
                "document" to mapOf("@type" to "inputFileLocal", "path" to ""),
                "caption" to caption,
            )

            val result = connectionManager.sendRequest(
                "sendMessage",
                mapOf(
                    "chat_id" to channelId,
                    "input_message_content" to inputMessage,
                )
            )

            val message = result["message"] as? Map<*, *>
            val messageId = (message?.get("id") as? Number)?.toLong() ?: 0L

            // Pin the manifest message
            connectionManager.sendRequest(
                "pinChatMessage",
                mapOf(
                    "chat_id" to channelId,
                    "message_id" to messageId,
                    "disable_notification" to true,
                )
            )

            Result.success(messageId)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to upload manifest", e)
            Result.failure(e)
        }
    }

    suspend fun downloadManifest(channelId: Int): Result<Manifest> = withContext(Dispatchers.IO) {
        try {
            // Get pinned message
            val chat = connectionManager.sendRequest(
                "getChat",
                mapOf("chat_id" to channelId)
            )
            val pinnedMessageId = (chat["pinned_message_id"] as? Number)?.toLong()

            if (pinnedMessageId == null || pinnedMessageId == 0L) {
                return@withContext Result.failure(Exception("No pinned manifest found"))
            }

            val message = connectionManager.sendRequest(
                "getMessage",
                mapOf("chat_id" to channelId, "message_id" to pinnedMessageId)
            )

            val content = message["content"] as? Map<*, *>
            val doc = content?.get("document") as? Map<*, *>
            val caption = doc?.get("caption") as? Map<*, *>
            val text = caption?.get("text") as? String ?: ""

            if (!text.startsWith("LUMOVAULT_MANIFEST|")) {
                return@withContext Result.failure(Exception("Invalid manifest format"))
            }

            val jsonStr = text.removePrefix("LUMOVAULT_MANIFEST|")
            val manifest = jsonToManifest(jsonStr)
            Result.success(manifest)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to download manifest", e)
            Result.failure(e)
        }
    }

    private fun manifestToJson(manifest: Manifest): String {
        return JSONObject().apply {
            put("app", manifest.app)
            put("schema_version", manifest.schemaVersion)
            put("created", manifest.created)
            put("device_hash", manifest.deviceHash)
            put("total_media", manifest.totalMedia)
            put("total_size_bytes", manifest.totalSizeBytes)
            put("last_sync", manifest.lastSync)
        }.toString()
    }

    private fun jsonToManifest(json: String): Manifest {
        val obj = JSONObject(json)
        return Manifest(
            app = obj.optString("app", "LumoVault"),
            schemaVersion = obj.optInt("schema_version", 1),
            created = obj.optLong("created", 0),
            deviceHash = obj.optString("device_hash", ""),
            totalMedia = obj.optInt("total_media", 0),
            totalSizeBytes = obj.optLong("total_size_bytes", 0),
            lastSync = obj.optLong("last_sync", 0),
        )
    }

    companion object {
        private const val TAG = "ManifestService"
    }
}

data class Manifest(
    val app: String = "LumoVault",
    val schemaVersion: Int = 2,
    val created: Long = System.currentTimeMillis(),
    val deviceHash: String = "",
    val totalMedia: Int = 0,
    val totalSizeBytes: Long = 0,
    val lastSync: Long = System.currentTimeMillis(),
)
