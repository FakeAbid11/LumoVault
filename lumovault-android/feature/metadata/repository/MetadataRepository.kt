package com.lumovault.feature.metadata.repository

import android.util.Log
import com.lumovault.core.database.daos.MediaDao
import com.lumovault.core.database.entities.MediaItemEntity
import com.lumovault.core.tdlib.TdLibConnectionManager
import com.lumovault.core.storage.EncryptedSettingsStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MetadataRepository @Inject constructor(
    private val mediaDao: MediaDao,
    private val connectionManager: TdLibConnectionManager,
    private val manifestService: ManifestService,
    private val partitionService: PartitionService,
    private val encryptedSettings: EncryptedSettingsStore,
) {
    /**
     * Sync local metadata to the storage channel.
     * Creates partition messages containing encoded metadata for each media item.
     */
    suspend fun syncMetadata(channelId: Int): MetadataSyncResult = withContext(Dispatchers.IO) {
        try {
            // Get unsynced items
            val unsyncedItems = mediaDao.getUnsyncedItems()
            if (unsyncedItems.isEmpty()) {
                return@withContext MetadataSyncResult.NothingToSync
            }

            Log.i(TAG, "Syncing ${unsyncedItems.size} unsynced items")

            // Create partitions
            val partitions = partitionService.createPartitions(unsyncedItems).getOrThrow()
            Log.i(TAG, "Created ${partitions.size} partitions")

            // Upload each partition as a message
            var uploadedCount = 0
            for (partition in partitions) {
                try {
                    val inputMessage = mapOf(
                        "@type" to "inputMessageText",
                        "text" to mapOf(
                            "@type" to "formattedText",
                            "text" to partition.caption,
                        ),
                        "clear_draft" to false,
                    )

                    connectionManager.sendRequest(
                        "sendMessage",
                        mapOf(
                            "chat_id" to channelId,
                            "input_message_content" to inputMessage,
                        )
                    )

                    uploadedCount += partition.items.size
                    Log.i(TAG, "Uploaded partition ${partition.index} with ${partition.items.size} items")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to upload partition ${partition.index}", e)
                }
            }

            // Update manifest
            val allItems = mediaDao.getAllItems()
            val totalSize = allItems.sumOf { it.fileSize }
            val manifest = Manifest(
                totalMedia = allItems.size,
                totalSizeBytes = totalSize,
                lastSync = System.currentTimeMillis(),
                deviceHash = encryptedSettings.getDeviceHash(),
            )
            manifestService.uploadManifest(channelId, manifest)

            // Mark items as synced
            mediaDao.markAsSynced(unsyncedItems.map { it.localId })

            MetadataSyncResult.Success(
                syncedCount = uploadedCount,
                totalPartitions = partitions.size,
            )
        } catch (e: Exception) {
            Log.e(TAG, "Metadata sync failed", e)
            MetadataSyncResult.Error(e.message ?: "Sync failed")
        }
    }

    /**
     * Check how many items need syncing.
     */
    suspend fun getUnsyncedCount(): Int {
        return mediaDao.getUnsyncedCount()
    }

    companion object {
        private const val TAG = "MetadataRepository"
    }
}

sealed class MetadataSyncResult {
    data class Success(val syncedCount: Int, val totalPartitions: Int) : MetadataSyncResult()
    object NothingToSync : MetadataSyncResult()
    data class Error(val message: String) : MetadataSyncResult()
}
