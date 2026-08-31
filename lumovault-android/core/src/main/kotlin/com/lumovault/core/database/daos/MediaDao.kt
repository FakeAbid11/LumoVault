package com.lumovault.core.database.daos

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import com.lumovault.core.database.entities.MediaItemEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface MediaDao {

    @Query("SELECT * FROM media_items ORDER BY created_at DESC")
    fun timeline(): Flow<List<MediaItemEntity>>

    @Query(
        """
        SELECT * FROM media_items 
        ORDER BY created_at DESC 
        LIMIT :limit OFFSET :offset
        """
    )
    fun timelinePage(limit: Int, offset: Int): Flow<List<MediaItemEntity>>

    @Query("SELECT * FROM media_items WHERE album_name = :album ORDER BY created_at DESC")
    fun byAlbum(album: String): Flow<List<MediaItemEntity>>

    @Query("SELECT * FROM media_items WHERE is_favorite = 1 ORDER BY created_at DESC")
    fun favorites(): Flow<List<MediaItemEntity>>

    @Query("SELECT * FROM media_items WHERE is_trashed = 1 ORDER BY trashed_at DESC")
    fun trashed(): Flow<List<MediaItemEntity>>

    @Query(
        """
        SELECT * FROM media_items 
        WHERE file_name LIKE '%' || :query || '%' 
           OR album_name LIKE '%' || :query || '%'
           OR description LIKE '%' || :query || '%'
           OR tags LIKE '%' || :query || '%'
           OR ai_labels LIKE '%' || :query || '%'
        ORDER BY created_at DESC
        """
    )
    fun search(query: String): Flow<List<MediaItemEntity>>

    @Query("SELECT * FROM media_items WHERE local_id = :localId LIMIT 1")
    suspend fun byLocalId(localId: String): MediaItemEntity?

    @Query("SELECT * FROM media_items WHERE local_id IN (:localIds)")
    suspend fun byLocalIds(localIds: List<String>): List<MediaItemEntity>

    @Query("SELECT * FROM media_items WHERE file_hash = :hash LIMIT 1")
    suspend fun byHash(hash: String): MediaItemEntity?

    @Query("SELECT file_hash, COUNT(*) as count FROM media_items GROUP BY file_hash HAVING count > 1")
    suspend fun duplicateHashes(): List<DuplicateHashResult>

    @Query("SELECT DISTINCT album_name FROM media_items WHERE album_name IS NOT NULL ORDER BY album_name")
    fun albumNames(): Flow<List<String>>

    @Query("SELECT * FROM media_items ORDER BY created_at DESC")
    suspend fun all(): List<MediaItemEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(item: MediaItemEntity): Long

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(items: List<MediaItemEntity>)

    @Transaction
    suspend fun replaceAll(items: List<MediaItemEntity>) {
        deleteAll()
        upsertAll(items)
    }

    @Update
    suspend fun update(item: MediaItemEntity)

    @Query("UPDATE media_items SET uploaded_at = :uploadedAt, backed_up_at = :backedUpAt, status = :status WHERE local_id = :localId")
    suspend fun updateBackupStatus(
        localId: String,
        uploadedAt: Long?,
        backedUpAt: Long?,
        status: Int
    )

    @Query("DELETE FROM media_items WHERE local_id IN (:localIds)")
    suspend fun deleteByLocalIds(localIds: List<String>)

    @Query("DELETE FROM media_items")
    suspend fun deleteAll()

    @Query("SELECT COUNT(*) FROM media_items")
    suspend fun count(): Int

    @Query("SELECT * FROM media_items WHERE is_hidden = 1 ORDER BY created_at DESC")
    fun hidden(): Flow<List<MediaItemEntity>>

    @Query("SELECT * FROM media_items WHERE is_archived = 1 ORDER BY created_at DESC")
    fun archived(): Flow<List<MediaItemEntity>>

    @Query(
        """
        SELECT * FROM media_items 
        WHERE is_trashed = 0 
          AND is_hidden = 0 
          AND is_archived = 0 
          AND is_excluded = 0 
          AND (telegram_message_id IS NULL OR (file_path != '' AND file_path NOT LIKE 'telegram://%'))
          AND status != 2
        ORDER BY created_at DESC
        """
    )
    fun pendingBackup(): Flow<List<MediaItemEntity>>
}

data class DuplicateHashResult(
    val fileHash: String,
    val count: Int,
)
