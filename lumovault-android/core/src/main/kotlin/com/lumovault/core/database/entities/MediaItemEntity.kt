package com.lumovault.core.database.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "media_items",
    indices = [
        Index("file_hash"),
        Index("created_at"),
        Index("status"),
        Index("is_favorite"),
        Index("is_trashed", "trashed_at"),
        Index("album_name")
    ]
)
data class MediaItemEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    @ColumnInfo(name = "local_id") val localId: String,
    @ColumnInfo(name = "file_hash") val fileHash: String,
    @ColumnInfo(name = "telegram_message_id") val telegramMessageId: String? = null,
    @ColumnInfo(name = "telegram_file_id") val telegramFileId: String? = null,
    @ColumnInfo(name = "file_path") val filePath: String = "",
    @ColumnInfo(name = "file_name") val fileName: String = "",
    @ColumnInfo(name = "mime_type") val mimeType: String = "",
    @ColumnInfo(name = "file_size") val fileSize: Long = 0,
    @ColumnInfo(name = "width") val width: Int = 0,
    @ColumnInfo(name = "height") val height: Int = 0,
    @ColumnInfo(name = "duration_ms") val durationMs: Int? = null,
    @ColumnInfo(name = "created_at") val createdAt: Long = 0L,
    @ColumnInfo(name = "modified_at") val modifiedAt: Long = 0L,
    @ColumnInfo(name = "scanned_at") val scannedAt: Long = 0L,
    @ColumnInfo(name = "uploaded_at") val uploadedAt: Long? = null,
    @ColumnInfo(name = "backed_up_at") val backedUpAt: Long? = null,
    @ColumnInfo(name = "status") val status: Int = 0,
    @ColumnInfo(name = "error_message") val errorMessage: String? = null,
    @ColumnInfo(name = "is_favorite") val isFavorite: Boolean = false,
    @ColumnInfo(name = "is_hidden") val isHidden: Boolean = false,
    @ColumnInfo(name = "is_archived") val isArchived: Boolean = false,
    @ColumnInfo(name = "is_trashed") val isTrashed: Boolean = false,
    @ColumnInfo(name = "trashed_at") val trashedAt: Long? = null,
    @ColumnInfo(name = "is_excluded") val isExcluded: Boolean = false,
    @ColumnInfo(name = "album_name") val albumName: String? = null,
    @ColumnInfo(name = "device_folder") val deviceFolder: String? = null,
    @ColumnInfo(name = "description") val description: String? = null,
    @ColumnInfo(name = "tags") val tags: String = "[]",
    @ColumnInfo(name = "ai_labels") val aiLabels: String = "[]",
    @ColumnInfo(name = "thumbnail_path") val thumbnailPath: String? = null,
    @ColumnInfo(name = "latitude") val latitude: Double? = null,
    @ColumnInfo(name = "longitude") val longitude: Double? = null,
    @ColumnInfo(name = "is_location_user_set") val isLocationUserSet: Boolean = false,
) {
    companion object {
        const val STATUS_PENDING = 0
        const val STATUS_UPLOADING = 1
        const val STATUS_UPLOADED = 2
        const val STATUS_UPLOADED_WITH_ERROR = 3
        const val STATUS_FAILED = 4

        val isTelegram: (MediaItemEntity) -> Boolean = { item ->
            item.telegramMessageId != null &&
                (item.filePath.isEmpty() || item.filePath.startsWith("telegram://"))
        }
    }
}
