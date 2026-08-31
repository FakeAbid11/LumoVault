package com.lumovault.core.database.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index

@Entity(
    tableName = "face_persons",
    primaryKeys = ["face_id", "person_id"],
    indices = [Index("person_id")]
)
data class FacePersonEntity(
    @ColumnInfo(name = "face_id") val faceId: Long,
    @ColumnInfo(name = "person_id") val personId: Long,
    @ColumnInfo(name = "assigned_at") val assignedAt: Long = 0L,
)
