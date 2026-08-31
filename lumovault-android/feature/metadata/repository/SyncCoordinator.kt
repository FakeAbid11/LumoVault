package com.lumovault.feature.metadata.repository

import android.util.Log
import com.lumovault.core.storage.EncryptedSettingsStore
import com.lumovault.core.tdlib.TdLibConnectionManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Coordinates periodic metadata sync between local database and the storage channel.
 * Automatically triggers sync when connected to Telegram.
 */
@Singleton
class SyncCoordinator @Inject constructor(
    private val metadataRepository: MetadataRepository,
    private val encryptedSettings: EncryptedSettingsStore,
    private val connectionManager: TdLibConnectionManager,
) {
    private var syncJob: Job? = null

    /**
     * Start periodic sync (every 5 minutes if connected).
     */
    fun startPeriodicSync(scope: CoroutineScope) {
        if (syncJob?.isActive == true) return

        syncJob = scope.launch {
            while (true) {
                delay(5 * 60 * 1000) // 5 minutes

                try {
                    val isConnected = connectionManager.isConnected()
                    if (!isConnected) continue

                    val channelId = encryptedSettings.getStorageChannelId()
                    if (channelId == null) continue

                    val unsynced = metadataRepository.getUnsyncedCount()
                    if (unsynced == 0) continue

                    Log.i(TAG, "Periodic sync: $unsynced unsynced items")
                    metadataRepository.syncMetadata(channelId)
                } catch (e: Exception) {
                    Log.e(TAG, "Periodic sync failed", e)
                }
            }
        }
    }

    fun stopPeriodicSync() {
        syncJob?.cancel()
        syncJob = null
    }

    suspend fun getUnsyncedCount(): Int {
        return metadataRepository.getUnsyncedCount()
    }

    /**
     * Trigger an immediate sync.
     */
    suspend fun syncNow(): MetadataSyncResult {
        val channelId = encryptedSettings.getStorageChannelId()
            ?: return MetadataSyncResult.Error("No storage channel configured")

        return metadataRepository.syncMetadata(channelId)
    }

    companion object {
        private const val TAG = "SyncCoordinator"
    }
}
