package com.lumovault.feature.restore.engine

import android.util.Log
import com.lumovault.core.database.daos.MediaDao
import com.lumovault.core.database.entities.MediaItemEntity
import com.lumovault.feature.gallery.repository.GalleryRepository
import com.lumovault.feature.restore.model.ManifestInfo
import com.lumovault.feature.restore.model.RestorePhase
import com.lumovault.feature.restore.model.RestoreProgress
import com.lumovault.feature.restore.repository.ChannelScanResult
import com.lumovault.feature.restore.repository.ChannelScanService
import com.lumovault.feature.restore.repository.RestoreRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class RestoreEngine @Inject constructor(
    private val restoreRepository: RestoreRepository,
    private val channelScanService: ChannelScanService,
    private val galleryRepository: GalleryRepository,
    private val restoreStateStore: RestoreStateStore,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var restoreJob: Job? = null

    private val _progress = MutableStateFlow(RestoreProgress())
    val progress: StateFlow<RestoreProgress> = _progress.asStateFlow()

    fun startRestore() {
        if (restoreJob?.isActive == true) return

        restoreJob = scope.launch {
            try {
                _progress.value = RestoreProgress(
                    phase = RestorePhase.DETECTING_CHANNEL,
                    startedAt = System.currentTimeMillis(),
                    currentPhaseDescription = "Finding backup channel...",
                )

                // Phase 1: Detect channel
                val channelId = restoreRepository.findStorageChannel()
                if (channelId == null) {
                    _progress.update {
                        it.copy(
                            phase = RestorePhase.FAILED,
                            error = "No backup channel found. Make sure you have backed up photos to Telegram.",
                        )
                    }
                    return@launch
                }

                // Phase 2: Scan channel
                _progress.update {
                    it.copy(
                        phase = RestorePhase.DOWNLOADING_MANIFEST,
                        currentPhaseDescription = "Scanning backup channel...",
                    )
                }

                val scanResult = channelScanService.scanChannel(channelId)
                when (scanResult) {
                    is ChannelScanResult.Error -> {
                        _progress.update {
                            it.copy(
                                phase = RestorePhase.FAILED,
                                error = scanResult.message,
                            )
                        }
                        return@launch
                    }
                    is ChannelScanResult.Success -> {
                        val items = scanResult.items
                        _progress.update {
                            it.copy(
                                totalItems = items.size,
                                currentPhaseDescription = "Found ${items.size} backed up items",
                            )
                        }

                        // Phase 3: Filter already restored
                        val restoredHashes = restoreStateStore.getRestoredHashes()
                        val newItems = items.filter { it.fileHash !in restoredHashes }
                        val skippedCount = items.size - newItems.size

                        _progress.update {
                            it.copy(
                                skippedItems = skippedCount,
                                totalItems = newItems.size,
                                currentPhaseDescription = "Skipping $skippedCount already restored items",
                            )
                        }

                        // Phase 4: Rebuild database
                        _progress.update {
                            it.copy(
                                phase = RestorePhase.REBUILDING_DATABASE,
                                currentPhaseDescription = "Saving to database...",
                            )
                        }

                        galleryRepository.saveRestoredItems(newItems)
                        restoreStateStore.addRestoredHashes(newItems.map { it.fileHash }.toSet())

                        // Phase 5: Download thumbnails (simplified — just mark complete)
                        _progress.update {
                            it.copy(
                                phase = RestorePhase.DOWNLOADING_THUMBNAILS,
                                currentPhaseDescription = "Processing...",
                            )
                        }

                        // Phase 6: Complete
                        _progress.update {
                            it.copy(
                                phase = RestorePhase.COMPLETED,
                                completedItems = newItems.size,
                                overallProgress = 1f,
                                currentPhaseDescription = "Restore complete!",
                            )
                        }
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "Restore failed", e)
                _progress.update {
                    it.copy(
                        phase = RestorePhase.FAILED,
                        error = e.message ?: "Restore failed",
                    )
                }
            }
        }
    }

    fun pauseRestore() {
        _progress.update { it.copy(isPaused = true) }
    }

    fun resumeRestore() {
        _progress.update { it.copy(isPaused = false) }
    }

    fun cancelRestore() {
        restoreJob?.cancel()
        restoreJob = null
        _progress.value = RestoreProgress()
    }

    companion object {
        private const val TAG = "RestoreEngine"
    }
}

// Extension function on GalleryRepository
private suspend fun GalleryRepository.saveRestoredItems(items: List<MediaItemEntity>) {
    items.forEach { item ->
        val existing = getByLocalId(item.localId)
        if (existing == null) {
            // Insert new item
            upsertItem(item)
        }
    }
}
