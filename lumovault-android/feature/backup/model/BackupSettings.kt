package com.lumovault.feature.backup.model

data class BackupSettings(
    val isAutoBackupEnabled: Boolean = false,
    val wifiOnly: Boolean = true,
    val chargingOnly: Boolean = false,
    val maxFileSizeBytes: Long = 2L * 1024 * 1024 * 1024, // 2GB
    val backupPhotos: Boolean = true,
    val backupVideos: Boolean = true,
    val includedFolders: Set<String> = emptySet(),
    val excludedFolders: Set<String> = emptySet(),
    val excludedFileHashes: Set<String> = emptySet(),
    val uploadBatchSize: Int = 5,
    val uploadDelayMs: Long = 500L,
    val lastBackupAt: Long? = null,
    val lastScanAt: Long? = null,
)

data class BackupStats(
    val totalItems: Int = 0,
    val backedUpItems: Int = 0,
    val pendingItems: Int = 0,
    val failedItems: Int = 0,
    val uploadingItems: Int = 0,
    val totalBytes: Long = 0,
    val backedUpBytes: Long = 0,
) {
    val progress: Float
        get() = if (totalItems > 0) backedUpItems.toFloat() / totalItems else 0f

    val progressPercentage: Int
        get() = (progress * 100).toInt()
}

enum class BackupStatus {
    IDLE,
    SCANNING,
    UPLOADING,
    PAUSED,
    COMPLETED,
    FAILED,
}
