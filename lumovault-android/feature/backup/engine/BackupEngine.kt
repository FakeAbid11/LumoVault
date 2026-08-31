package com.lumovault.feature.backup.engine

import android.util.Log
import com.lumovault.core.database.entities.MediaItemEntity
import com.lumovault.core.tdlib.TdLibConnectionManager
import com.lumovault.feature.backup.model.BackupSettings
import com.lumovault.feature.backup.model.BackupStats
import com.lumovault.feature.backup.model.BackupStatus
import com.lumovault.feature.gallery.repository.GalleryRepository
import com.lumovault.feature.gallery.repository.TelegramUploadService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class BackupEngine @Inject constructor(
    private val galleryRepository: GalleryRepository,
    private val uploadService: TelegramUploadService,
    private val connectionManager: TdLibConnectionManager,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val uploadMutex = Mutex()
    private var backupJob: Job? = null

    private val uploadQueue = UploadQueue()

    private val _status = MutableStateFlow(BackupStatus.IDLE)
    val status: StateFlow<BackupStatus> = _status.asStateFlow()

    private val _stats = MutableStateFlow(BackupStats())
    val stats: StateFlow<BackupStats> = _stats.asStateFlow()

    private val _currentItem = MutableStateFlow<String?>(null)
    val currentItem: StateFlow<String?> = _currentItem.asStateFlow()

    fun startBackup(settings: BackupSettings) {
        if (backupJob?.isActive == true) return

        backupJob = scope.launch {
            try {
                _status.value = BackupStatus.SCANNING
                _stats.update { it.copy(pendingItems = 0, backedUpItems = 0, failedItems = 0) }

                // Scan for new items
                galleryRepository.scanDevice(
                    if (settings.includedFolders.isNotEmpty()) settings.includedFolders else null
                )

                val pendingItems = galleryRepository.getPendingBackup().first()
                val filtered = pendingItems.filter { item ->
                    shouldBackup(item, settings)
                }

                Log.i(TAG, "Found ${filtered.size} items to backup")
                _stats.update { it.copy(totalItems = filtered.size, pendingItems = filtered.size) }

                if (filtered.isEmpty()) {
                    _status.value = BackupStatus.COMPLETED
                    return@launch
                }

                // Enqueue items
                uploadQueue.enqueue(filtered)

                // Get storage channel
                val channelId = uploadService.getStorageChannelId()
                if (channelId == null) {
                    _status.value = BackupStatus.FAILED
                    _stats.update { it.copy(failedItems = filtered.size) }
                    return@launch
                }

                // Start upload loop
                _status.value = BackupStatus.UPLOADING
                uploadLoop(channelId, settings)

            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "Backup failed", e)
                _status.value = BackupStatus.FAILED
            }
        }
    }

    fun pauseBackup() {
        uploadQueue.pause()
        _status.value = BackupStatus.PAUSED
    }

    fun resumeBackup() {
        uploadQueue.resume()
        _status.value = BackupStatus.UPLOADING
    }

    fun cancelBackup() {
        backupJob?.cancel()
        backupJob = null
        uploadQueue.cancelAll()
        _status.value = BackupStatus.IDLE
        _currentItem.value = null
    }

    private suspend fun uploadLoop(channelId: Int, settings: BackupSettings) {
        while (scope.isActive && uploadQueue.pendingCount() > 0) {
            if (uploadQueue.state.value.isPaused) {
                delay(1000)
                continue
            }

            val task = uploadQueue.dequeue() ?: break

            _currentItem.value = task.mediaItem.fileName
            _stats.update { it.copy(
                uploadingItems = uploadQueue.state.value.activeTasks.size,
            )}

            try {
                val caption = buildCaption(task.mediaItem)
                val result = uploadService.uploadFile(
                    taskId = task.id,
                    filePath = task.mediaItem.filePath,
                    channelId = channelId,
                    caption = caption,
                )

                result.fold(
                    onSuccess = { uploadResult ->
                        uploadQueue.complete(task.id)
                        galleryRepository.markUploaded(task.mediaItem.localId)
                        _stats.update { it.copy(
                            backedUpItems = it.backedUpItems + 1,
                            backedUpBytes = it.backedUpBytes + task.mediaItem.fileSize,
                        )}
                        Log.d(TAG, "Uploaded: ${task.mediaItem.fileName}")
                    },
                    onFailure = { error ->
                        val message = error.message ?: "Upload failed"
                        uploadQueue.fail(task.id, message)
                        galleryRepository.markFailed(task.mediaItem.localId, message)
                        _stats.update { it.copy(failedItems = it.failedItems + 1) }
                        Log.e(TAG, "Failed: ${task.mediaItem.fileName} - $message")
                    }
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                uploadQueue.fail(task.id, e.message ?: "Unknown error")
                _stats.update { it.copy(failedItems = it.failedItems + 1) }
            }

            // Delay between uploads
            delay(settings.uploadDelayMs)
        }

        // All done
        if (uploadQueue.pendingCount() == 0 && uploadQueue.state.value.activeTasks.isEmpty()) {
            _status.value = BackupStatus.COMPLETED
            _currentItem.value = null
        }
    }

    private fun shouldBackup(item: MediaItemEntity, settings: BackupSettings): Boolean {
        // Already backed up
        if (item.status == MediaItemEntity.STATUS_UPLOADED) return false

        // In excluded hashes
        if (item.fileHash in settings.excludedFileHashes) return false

        // Excluded folder
        if (item.albumName in settings.excludedFolders) return false

        // File too large
        if (item.fileSize > settings.maxFileSizeBytes) return false

        // Type filtering
        val isVideo = item.mimeType.startsWith("video/")
        val isImage = item.mimeType.startsWith("image/")
        if (isVideo && !settings.backupVideos) return false
        if (isImage && !settings.backupPhotos) return false

        return true
    }

    private fun buildCaption(item: MediaItemEntity): String {
        return buildString {
            append("lumovault:v2|")
            append("hash:${item.fileHash}|")
            append("created:${item.createdAt}|")
            append("modified:${item.modifiedAt}|")
            append("size:${item.fileSize}|")
            append("mime:${item.mimeType}|")
            append("w:${item.width}|h:${item.height}")
            if (item.isFavorite) append("|fav:1")
            if (item.isHidden) append("|hidden:1")
            if (item.isArchived) append("|archived:1")
            item.albumName?.let { append("|album:$it") }
            item.description?.let { append("|desc:$it") }
            if (item.latitude != null && item.longitude != null) {
                append("|lat:${item.latitude}|lon:${item.longitude}")
            }
        }
    }

    companion object {
        private const val TAG = "BackupEngine"
    }
}
