package com.lumovault.feature.restore.model

enum class RestorePhase {
    DETECTING_CHANNEL,
    DOWNLOADING_MANIFEST,
    DOWNLOADING_METADATA,
    REBUILDING_DATABASE,
    DOWNLOADING_THUMBNAILS,
    COMPLETED,
    FAILED,
}

data class RestoreProgress(
    val phase: RestorePhase = RestorePhase.DETECTING_CHANNEL,
    val overallProgress: Float = 0f,
    val totalItems: Int = 0,
    val completedItems: Int = 0,
    val failedItems: Int = 0,
    val skippedItems: Int = 0,
    val currentFileName: String? = null,
    val currentPhaseDescription: String = "",
    val totalBytes: Long = 0,
    val downloadedBytes: Long = 0,
    val startedAt: Long? = null,
    val estimatedCompletion: Long? = null,
    val error: String? = null,
    val isPaused: Boolean = false,
    val manifestInfo: ManifestInfo? = null,
) {
    val progress: Float
        get() = if (totalItems > 0) completedItems.toFloat() / totalItems else 0f

    val progressPercentage: Int
        get() = (progress * 100).toInt()
}

data class ManifestInfo(
    val app: String = "LumoVault",
    val schemaVersion: Int = 0,
    val created: Long = 0,
    val deviceHash: String = "",
    val totalMedia: Int = 0,
    val totalSizeBytes: Long = 0,
    val lastSync: Long = 0,
)
