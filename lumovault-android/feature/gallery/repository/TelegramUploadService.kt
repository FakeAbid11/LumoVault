package com.lumovault.feature.gallery.repository

import android.util.Log
import com.lumovault.core.database.entities.MediaItemEntity
import com.lumovault.core.storage.EncryptedSettingsStore
import com.lumovault.core.tdlib.TdLibConnectionManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

data class UploadProgress(
    val taskId: String,
    val progress: Float,
    val bytesUploaded: Long,
    val totalBytes: Long,
)

data class UploadResult(
    val taskId: String,
    val messageId: Long,
    val channelId: Int,
    val filePath: String,
)

sealed class UploadError(val message: String) {
    class FileNotFound(message: String) : UploadError(message)
    class ChannelNotFound(message: String) : UploadError(message)
    class TdLibError(message: String) : UploadError(message)
    class Cancelled(message: String = "Upload cancelled") : UploadError(message)
}

@Singleton
class TelegramUploadService @Inject constructor(
    private val connectionManager: TdLibConnectionManager,
    private val encryptedSettings: EncryptedSettingsStore,
) {
    private val _progress = MutableSharedFlow<UploadProgress>(extraBufferCapacity = 16)
    val progress: SharedFlow<UploadProgress> = _progress.asSharedFlow()

    suspend fun uploadFile(
        taskId: String,
        filePath: String,
        channelId: Int,
        caption: String? = null,
    ): Result<UploadResult> = withContext(Dispatchers.IO) {
        try {
            val file = java.io.File(filePath)
            if (!file.exists()) {
                return@withContext Result.failure(UploadError.FileNotFound("File not found: $filePath"))
            }

            // Get existing message to send the file
            val inputFile = mapOf(
                "@type" to "inputFileLocal",
                "path" to filePath,
            )

            val captionContent = if (caption != null) {
                mapOf(
                    "@type" to "formattedText",
                    "text" to caption,
                )
            } else null

            val messageContent = mutableMapOf<String, Any>(
                "@type" to "inputMessageDocument",
                "document" to inputFile,
            )
            if (captionContent != null) {
                messageContent["caption"] = captionContent
            }

            // Send message to channel
            val result = connectionManager.sendRequest(
                "sendMessage",
                mapOf(
                    "chat_id" to channelId,
                    "input_message_content" to messageContent,
                )
            )

            val message = result["message"] as? Map<*, *>
                ?: return@withContext Result.failure(UploadError.TdLibError("No message in response"))

            val messageId = (message["id"] as? Number)?.toLong()
                ?: return@withContext Result.failure(UploadError.TdLibError("No message ID"))

            val content = message["content"] as? Map<*, *>
            val document = content?.get("document") as? Map<*, *>
            val remote = document?.get("remote") as? Map<*, *>
            val remoteId = remote?.get("id") as? String ?: ""

            // Monitor upload progress via file updates
            monitorUploadProgress(taskId, file.length())

            Result.success(
                UploadResult(
                    taskId = taskId,
                    messageId = messageId,
                    channelId = channelId,
                    filePath = filePath,
                )
            )
        } catch (e: Exception) {
            Log.e(TAG, "Upload failed: $filePath", e)
            Result.failure(UploadError.TdLibError(e.message ?: "Unknown error"))
        }
    }

    private suspend fun monitorUploadProgress(taskId: String, totalBytes: Long) {
        // TDLib sends updateFile during upload — we'd listen to updates here
        // For now, report completion
        _progress.emit(
            UploadProgress(
                taskId = taskId,
                progress = 1f,
                bytesUploaded = totalBytes,
                totalBytes = totalBytes,
            )
        )
    }

    suspend fun getStorageChannelId(): Int? {
        val cached = encryptedSettings.getStorageChannelId()
        if (cached != null) return cached

        // Search for existing channel
        val searchResult = connectionManager.sendRequest(
            "searchChats",
            mapOf("query" to "LumoVault Backup", "limit" to 10)
        )

        val chatIds = (searchResult["chat_ids"] as? List<*>)?.filterIsInstance<Number>() ?: emptyList()
        for (chatId in chatIds) {
            val chatInfo = connectionManager.sendRequest(
                "getChat",
                mapOf("chat_id" to chatId.toLong())
            )
            val title = chatInfo["title"] as? String
            if (title == "LumoVault Backup") {
                val id = chatId.toInt()
                encryptedSettings.setStorageChannelId(id)
                return id
            }
        }

        return null
    }

    suspend fun deleteMessage(channelId: Int, messageId: Long): Boolean {
        return try {
            connectionManager.sendRequest(
                "deleteMessages",
                mapOf(
                    "chat_id" to channelId,
                    "message_ids" to listOf(messageId),
                    "revoke" to true,
                )
            )
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete message", e)
            false
        }
    }

    companion object {
        private const val TAG = "TelegramUploadService"
    }
}
