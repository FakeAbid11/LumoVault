package com.lumovault.feature.restore.repository

import android.util.Log
import com.lumovault.core.database.entities.MediaItemEntity
import com.lumovault.core.tdlib.TdLibConnectionManager
import com.lumovault.core.storage.EncryptedSettingsStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ChannelScanService @Inject constructor(
    private val connectionManager: TdLibConnectionManager,
    private val encryptedSettings: EncryptedSettingsStore,
) {
    /**
     * Scan the backup channel and build a MediaItem list from caption-encoded metadata.
     */
    suspend fun scanChannel(channelId: Int): ChannelScanResult = withContext(Dispatchers.IO) {
        try {
            val items = mutableListOf<MediaItemEntity>()
            var offset = 0
            var totalFetched = 0

            while (true) {
                val result = connectionManager.sendRequest(
                    "getChatHistory",
                    mapOf(
                        "chat_id" to channelId,
                        "from_message_id" to 0,
                        "offset" to offset,
                        "limit" to 100,
                        "only_local" to false,
                    )
                )

                val messages = result["messages"] as? List<*> ?: break
                if (messages.isEmpty()) break

                for (msg in messages) {
                    val message = msg as? Map<*, *> ?: continue
                    val content = message["content"] as? Map<*, *> ?: continue
                    val type = content["@type"] as? String ?: continue

                    if (type != "messageDocument" && type != "messagePhoto") continue

                    val caption = extractCaption(content) ?: continue
                    val metadata = parseCaptionMetadata(caption) ?: continue

                    val messageId = (message["id"] as? Number)?.toLong() ?: continue
                    val date = (message["date"] as? Number)?.toLong()?.times(1000) ?: 0L

                    val entity = MediaItemEntity(
                        localId = "tg_${messageId}",
                        fileHash = metadata.fileHash,
                        telegramMessageId = messageId.toString(),
                        filePath = "telegram://$messageId",
                        fileName = metadata.fileName,
                        mimeType = metadata.mimeType,
                        fileSize = metadata.fileSize,
                        width = metadata.width,
                        height = metadata.height,
                        createdAt = metadata.createdAt,
                        modifiedAt = metadata.modifiedAt,
                        backedUpAt = date,
                        status = MediaItemEntity.STATUS_UPLOADED,
                        isFavorite = metadata.isFavorite,
                        isHidden = metadata.isHidden,
                        isArchived = metadata.isArchived,
                        albumName = metadata.albumName,
                        latitude = metadata.latitude,
                        longitude = metadata.longitude,
                    )

                    items.add(entity)
                }

                totalFetched += messages.size
                offset -= messages.size

                if (messages.size < 100) break
            }

            Log.i(TAG, "Scanned ${items.size} items from channel")
            ChannelScanResult.Success(items)
        } catch (e: Exception) {
            Log.e(TAG, "Channel scan failed", e)
            ChannelScanResult.Error(e.message ?: "Scan failed")
        }
    }

    private fun extractCaption(content: Map<*, *>): String? {
        return when (content["@type"]) {
            "messageDocument" -> {
                val doc = content["document"] as? Map<*, *>
                val caption = doc?.get("caption") as? Map<*, *>
                caption?.get("text") as? String
            }
            "messagePhoto" -> {
                val photo = content["photo"] as? Map<*, *>
                val caption = photo?.get("caption") as? Map<*, *>
                caption?.get("text") as? String
            }
            else -> null
        }
    }

    private fun parseCaptionMetadata(caption: String): CaptionMetadata? {
        if (!caption.startsWith("lumovault:")) return null

        return try {
            val parts = caption.removePrefix("lumovault:v2|").split("|")
            val map = mutableMapOf<String, String>()
            for (part in parts) {
                val kv = part.split(":", limit = 2)
                if (kv.size == 2) map[kv[0]] = kv[1]
            }

            CaptionMetadata(
                fileHash = map["hash"] ?: "",
                createdAt = map["created"]?.toLongOrNull() ?: 0L,
                modifiedAt = map["modified"]?.toLongOrNull() ?: 0L,
                fileSize = map["size"]?.toLongOrNull() ?: 0L,
                mimeType = map["mime"] ?: "image/jpeg",
                width = map["w"]?.toIntOrNull() ?: 0,
                height = map["h"]?.toIntOrNull() ?: 0,
                isFavorite = map["fav"] == "1",
                isHidden = map["hidden"] == "1",
                isArchived = map["archived"] == "1",
                albumName = map["album"],
                description = map["desc"],
                latitude = map["lat"]?.toDoubleOrNull(),
                longitude = map["lon"]?.toDoubleOrNull(),
            )
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        private const val TAG = "ChannelScanService"
    }
}

sealed class ChannelScanResult {
    data class Success(val items: List<MediaItemEntity>) : ChannelScanResult()
    data class Error(val message: String) : ChannelScanResult()
}

data class CaptionMetadata(
    val fileHash: String,
    val createdAt: Long,
    val modifiedAt: Long,
    val fileSize: Long,
    val mimeType: String,
    val width: Int,
    val height: Int,
    val isFavorite: Boolean = false,
    val isHidden: Boolean = false,
    val isArchived: Boolean = false,
    val albumName: String? = null,
    val description: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
)
