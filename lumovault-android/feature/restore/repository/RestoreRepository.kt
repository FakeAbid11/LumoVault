package com.lumovault.feature.restore.repository

import android.util.Log
import com.lumovault.core.database.entities.MediaItemEntity
import com.lumovault.core.tdlib.TdLibConnectionManager
import com.lumovault.core.storage.EncryptedSettingsStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class RestoreRepository @Inject constructor(
    private val connectionManager: TdLibConnectionManager,
    private val encryptedSettings: EncryptedSettingsStore,
) {
    suspend fun findStorageChannel(): Int? {
        val cached = encryptedSettings.getStorageChannelId()
        if (cached != null) return cached

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

    suspend fun downloadFile(
        channelId: Int,
        messageId: Long,
        destinationPath: String,
    ): Result<String> = withContext(Dispatchers.IO) {
        try {
            val message = connectionManager.sendRequest(
                "getMessage",
                mapOf("chat_id" to channelId, "message_id" to messageId)
            )

            val content = message["content"] as? Map<*, *>
                ?: return@withContext Result.failure(Exception("No content in message"))

            val file = extractFile(content)
                ?: return@withContext Result.failure(Exception("No file in message"))

            val fileId = (file["id"] as? Number)?.toLong()
                ?: return@withContext Result.failure(Exception("No file ID"))

            val local = file["local"] as? Map<*, *>
            val existingPath = local?.get("path") as? String

            if (!existingPath.isNullOrEmpty() && File(existingPath).exists()) {
                return@withContext Result.success(existingPath)
            }

            // Request download
            connectionManager.sendRequest(
                "downloadFile",
                mapOf("file_id" to fileId)
            )

            // Poll for completion
            var attempts = 0
            while (attempts < 300) { // 5 minutes max
                val fileUpdate = connectionManager.sendRequest(
                    "getFile",
                    mapOf("file_id" to fileId)
                )
                val updatedLocal = fileUpdate["local"] as? Map<*, *>
                val isCompleted = updatedLocal?.get("is_downloading_completed") as? Boolean ?: false
                val path = updatedLocal?.get("path") as? String

                if (isCompleted && !path.isNullOrEmpty()) {
                    return@withContext Result.success(path)
                }

                Thread.sleep(1000)
                attempts++
            }

            Result.failure(Exception("Download timed out"))
        } catch (e: Exception) {
            Log.e(TAG, "File download failed: $messageId", e)
            Result.failure(e)
        }
    }

    private fun extractFile(content: Map<*, *>): Map<*, ?>? {
        return when (content["@type"]) {
            "messageDocument" -> {
                val doc = content["document"] as? Map<*, *>
                doc?.get("document") as? Map<*, *>
            }
            "messagePhoto" -> {
                val photo = content["photo"] as? Map<*, *>
                val sizes = photo?.get("sizes") as? List<*>
                val largest = sizes?.lastOrNull() as? Map<*, *>
                largest?.get("photo") as? Map<*, *>
            }
            "messageVideo" -> {
                val video = content["video"] as? Map<*, *>
                video?.get("video") as? Map<*, *>
            }
            else -> null
        }
    }

    companion object {
        private const val TAG = "RestoreRepository"
    }
}
