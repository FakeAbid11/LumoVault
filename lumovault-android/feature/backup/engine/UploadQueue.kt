package com.lumovault.feature.backup.engine

import android.util.Log
import com.lumovault.core.database.entities.MediaItemEntity
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.util.PriorityQueue
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

data class UploadTask(
    val id: String,
    val mediaItem: MediaItemEntity,
    val priority: Int = 0, // Lower = higher priority
    val status: TaskStatus = TaskStatus.PENDING,
    val progress: Float = 0f,
    val retryCount: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
    val startedAt: Long? = null,
    val completedAt: Long? = null,
    val failedAt: Long? = null,
    val error: String? = null,
) : Comparable<UploadTask> {
    override fun compareTo(other: UploadTask): Int {
        return priority.compareTo(other.priority)
    }
}

enum class TaskStatus {
    PENDING,
    UPLOADING,
    COMPLETED,
    FAILED,
    CANCELLED,
}

data class UploadQueueState(
    val pendingTasks: List<UploadTask> = emptyList(),
    val activeTasks: List<UploadTask> = emptyList(),
    val completedTasks: List<UploadTask> = emptyList(),
    val failedTasks: List<UploadTask> = emptyList(),
    val isPaused: Boolean = false,
) {
    val totalCount: Int get() = pendingTasks.size + activeTasks.size
    val completedCount: Int get() = completedTasks.size
    val failedCount: Int get() = failedTasks.size
}

class UploadQueue {
    private val pendingQueue = PriorityQueue<UploadTask>()
    private val allTasks = ConcurrentHashMap<String, UploadTask>()
    private val taskIdCounter = AtomicInteger(0)

    private val _state = MutableStateFlow(UploadQueueState())
    val state: StateFlow<UploadQueueState> = _state.asStateFlow()

    @Synchronized
    fun enqueue(items: List<MediaItemEntity>, dedupByHash: Boolean = true) {
        val existingHashes = if (dedupByHash) {
            allTasks.values.map { it.mediaItem.fileHash }.toSet()
        } else {
            emptySet()
        }

        for (item in items) {
            if (dedupByHash && item.fileHash in existingHashes) continue
            if (item.localId in allTasks) continue

            val taskId = "upload_${item.localId}_${taskIdCounter.incrementAndGet()}"
            val task = UploadTask(
                id = taskId,
                mediaItem = item,
                priority = computePriority(item),
            )

            pendingQueue.add(task)
            allTasks[taskId] = task
        }

        updateState()
        Log.d(TAG, "Enqueued ${items.size} items, queue size: ${pendingQueue.size}")
    }

    @Synchronized
    fun dequeue(): UploadTask? {
        val task = pendingQueue.poll() ?: return null
        val updated = task.copy(
            status = TaskStatus.UPLOADING,
            startedAt = System.currentTimeMillis(),
        )
        allTasks[task.id] = updated
        updateState()
        return updated
    }

    @Synchronized
    fun complete(taskId: String) {
        val task = allTasks[taskId] ?: return
        val updated = task.copy(
            status = TaskStatus.COMPLETED,
            completedAt = System.currentTimeMillis(),
            progress = 1f,
        )
        allTasks[taskId] = updated
        updateState()
    }

    @Synchronized
    fun fail(taskId: String, error: String, retryable: Boolean = true) {
        val task = allTasks[taskId] ?: return
        if (retryable && task.retryCount < MAX_RETRIES) {
            val updated = task.copy(
                status = TaskStatus.PENDING,
                retryCount = task.retryCount + 1,
                error = error,
                // Exponential backoff delay
                priority = task.priority + (task.retryCount + 1) * 10,
            )
            allTasks[taskId] = updated
            pendingQueue.add(updated)
        } else {
            val updated = task.copy(
                status = TaskStatus.FAILED,
                failedAt = System.currentTimeMillis(),
                error = error,
            )
            allTasks[taskId] = updated
        }
        updateState()
    }

    @Synchronized
    fun cancel(taskId: String) {
        val task = allTasks[taskId] ?: return
        val updated = task.copy(status = TaskStatus.CANCELLED)
        allTasks[taskId] = updated
        pendingQueue.remove(task)
        updateState()
    }

    @Synchronized
    fun cancelAll() {
        pendingQueue.clear()
        allTasks.values.forEach { task ->
            if (task.status == TaskStatus.PENDING || task.status == TaskStatus.UPLOADING) {
                allTasks[task.id] = task.copy(status = TaskStatus.CANCELLED)
            }
        }
        updateState()
    }

    @Synchronized
    fun updateProgress(taskId: String, progress: Float) {
        val task = allTasks[taskId] ?: return
        val updated = task.copy(progress = progress)
        allTasks[taskId] = updated
        updateState()
    }

    @Synchronized
    fun pause() {
        _state.update { it.copy(isPaused = true) }
    }

    @Synchronized
    fun resume() {
        _state.update { it.copy(isPaused = false) }
    }

    fun isDuplicate(fileHash: String): Boolean {
        return allTasks.values.any {
            it.mediaItem.fileHash == fileHash && it.status != TaskStatus.CANCELLED
        }
    }

    fun pendingCount(): Int = pendingQueue.size

    private fun computePriority(item: MediaItemEntity): Int {
        // Prioritize by creation date (newer = higher priority = lower number)
        return (System.currentTimeMillis() - item.createdAt).toInt().coerceIn(0, Int.MAX_VALUE)
    }

    private fun updateState() {
        val tasks = allTasks.values.toList()
        _state.value = UploadQueueState(
            pendingTasks = tasks.filter { it.status == TaskStatus.PENDING },
            activeTasks = tasks.filter { it.status == TaskStatus.UPLOADING },
            completedTasks = tasks.filter { it.status == TaskStatus.COMPLETED },
            failedTasks = tasks.filter { it.status == TaskStatus.FAILED },
            isPaused = _state.value.isPaused,
        )
    }

    companion object {
        private const val TAG = "UploadQueue"
        private const val MAX_RETRIES = 3
    }
}
