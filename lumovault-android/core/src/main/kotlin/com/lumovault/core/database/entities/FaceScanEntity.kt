package com.lumovault.core.database.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "face_scans")
data class FaceScanEntity(
    @PrimaryKey @ColumnInfo(name = "media_item_id") val mediaItemId: String,
    @ColumnInfo(name = "scanned_at") val scannedAt: Long = 0L,
    @ColumnInfo(name = "face_count") val faceCount: Int = 0,
)
