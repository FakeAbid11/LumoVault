package com.lumovault.core.database.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "faces",
    indices = [
        Index("media_item_id"),
        Index("person_id")
    ]
)
data class FaceEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    @ColumnInfo(name = "media_item_id") val mediaItemId: String,
    @ColumnInfo(name = "bounding_box_x") val boundingBoxX: Double = 0.0,
    @ColumnInfo(name = "bounding_box_y") val boundingBoxY: Double = 0.0,
    @ColumnInfo(name = "bounding_box_width") val boundingBoxWidth: Double = 0.0,
    @ColumnInfo(name = "bounding_box_height") val boundingBoxHeight: Double = 0.0,
    @ColumnInfo(name = "landmarks") val landmarks: String = "{}",
    @ColumnInfo(name = "embedding") val embedding: String = "[]",
    @ColumnInfo(name = "confidence") val confidence: Double = 0.0,
    @ColumnInfo(name = "thumbnail_path") val thumbnailPath: String? = null,
    @ColumnInfo(name = "person_id") val personId: Long? = null,
    @ColumnInfo(name = "created_at") val createdAt: Long = 0L,
)
