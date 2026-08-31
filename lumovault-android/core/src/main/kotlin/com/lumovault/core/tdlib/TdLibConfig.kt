package com.lumovault.core.tdlib

data class TdLibConfig(
    val apiId: Int,
    val apiHash: String,
    val storageChannelName: String,
    val storageChannelDescription: String,
    val maxFileSizeBytes: Long,
    val databaseKeyLength: Int,
) {
    companion object {
        const val API_ID = 0 // Set via build config
        const val API_HASH = "" // Set via build config
        const val STORAGE_CHANNEL_NAME = "LumoVault Backup"
        const val STORAGE_CHANNEL_DESCRIPTION = "Private backup storage for LumoVault"
        const val MAX_FILE_SIZE_BYTES = 2L * 1024 * 1024 * 1024 // 2GB
        const val DATABASE_KEY_LENGTH = 32
    }
}
