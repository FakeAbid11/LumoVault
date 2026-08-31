package com.lumovault.feature.gallery.repository

import android.util.Log
import com.lumovault.core.database.daos.MediaDao
import com.lumovault.core.database.entities.MediaItemEntity
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class GalleryRepository @Inject constructor(
    private val mediaDao: MediaDao,
    private val mediaScanner: MediaScanner,
) {
    // --- Timeline ---
    fun getTimeline(): Flow<List<MediaItemEntity>> = mediaDao.timeline()

    fun getTimelinePage(limit: Int, offset: Int): Flow<List<MediaItemEntity>> =
        mediaDao.timelinePage(limit, offset)

    // --- Albums ---
    fun getAlbums(): Flow<List<String>> = mediaDao.albumNames()

    fun getAlbumPhotos(album: String): Flow<List<MediaItemEntity>> = mediaDao.byAlbum(album)

    // --- Favorites ---
    fun getFavorites(): Flow<List<MediaItemEntity>> = mediaDao.favorites()

    // --- Trash ---
    fun getTrashed(): Flow<List<MediaItemEntity>> = mediaDao.trashed()

    // --- Hidden ---
    fun getHidden(): Flow<List<MediaItemEntity>> = mediaDao.hidden()

    // --- Archived ---
    fun getArchived(): Flow<List<MediaItemEntity>> = mediaDao.archived()

    // --- Search ---
    fun search(query: String): Flow<List<MediaItemEntity>> = mediaDao.search(query)

    // --- Single item ---
    suspend fun getByLocalId(localId: String): MediaItemEntity? = mediaDao.byLocalId(localId)

    suspend fun getByLocalIds(localIds: List<String>): List<MediaItemEntity> =
        mediaDao.byLocalIds(localIds)

    // --- Backup ---
    fun getPendingBackup(): Flow<List<MediaItemEntity>> = mediaDao.pendingBackup()

    suspend fun markUploaded(localId: String) {
        val item = mediaDao.byLocalId(localId) ?: return
        mediaDao.update(
            item.copy(
                status = MediaItemEntity.STATUS_UPLOADED,
                uploadedAt = System.currentTimeMillis(),
                backedUpAt = System.currentTimeMillis(),
            )
        )
    }

    suspend fun markFailed(localId: String, error: String) {
        val item = mediaDao.byLocalId(localId) ?: return
        mediaDao.update(
            item.copy(
                status = MediaItemEntity.STATUS_FAILED,
                errorMessage = error,
            )
        )
    }

    // --- Favorites ---
    suspend fun toggleFavorite(localId: String) {
        val item = mediaDao.byLocalId(localId) ?: return
        mediaDao.update(item.copy(isFavorite = !item.isFavorite))
    }

    // --- Trash ---
    suspend fun moveToTrash(localId: String) {
        val item = mediaDao.byLocalId(localId) ?: return
        mediaDao.update(
            item.copy(
                isTrashed = true,
                trashedAt = System.currentTimeMillis(),
            )
        )
    }

    suspend fun restoreFromTrash(localId: String) {
        val item = mediaDao.byLocalId(localId) ?: return
        mediaDao.update(
            item.copy(
                isTrashed = false,
                trashedAt = null,
            )
        )
    }

    suspend fun permanentDelete(localId: String) {
        mediaDao.deleteByLocalIds(listOf(localId))
    }

    // --- Hidden ---
    suspend fun toggleHidden(localId: String) {
        val item = mediaDao.byLocalId(localId) ?: return
        mediaDao.update(item.copy(isHidden = !item.isHidden))
    }

    // --- Archive ---
    suspend fun toggleArchive(localId: String) {
        val item = mediaDao.byLocalId(localId) ?: return
        mediaDao.update(item.copy(isArchived = !item.isArchived))
    }

    // --- Description ---
    suspend fun updateDescription(localId: String, description: String) {
        val item = mediaDao.byLocalId(localId) ?: return
        mediaDao.update(item.copy(description = description))
    }

    // --- Tags ---
    suspend fun updateTags(localId: String, tags: List<String>) {
        val item = mediaDao.byLocalId(localId) ?: return
        val json = org.json.JSONArray(tags).toString()
        mediaDao.update(item.copy(tags = json))
    }

    // --- AI Labels ---
    suspend fun updateAiLabels(localId: String, labels: List<String>) {
        val item = mediaDao.byLocalId(localId) ?: return
        val json = org.json.JSONArray(labels).toString()
        mediaDao.update(item.copy(aiLabels = json))
    }

    // --- Location ---
    suspend fun updateLocation(localId: String, latitude: Double, longitude: Double, userSet: Boolean = true) {
        val item = mediaDao.byLocalId(localId) ?: return
        mediaDao.update(
            item.copy(
                latitude = latitude,
                longitude = longitude,
                isLocationUserSet = userSet,
            )
        )
    }

    // --- Scan ---
    suspend fun scanDevice(folders: Set<String>? = null) {
        val existingItems = mediaDao.all().associateBy { it.localId }
        val scannedItems = mediaScanner.scanFolders(folders)

        val newItems = scannedItems.filter { it.localId !in existingItems }

        if (newItems.isNotEmpty()) {
            mediaDao.upsertAll(newItems)
            Log.i(TAG, "Added ${newItems.size} new items")
        }

        // Remove items that no longer exist on device
        val scannedIds = scannedItems.map { it.localId }.toSet()
        val staleIds = existingItems.keys.filter { it !in scannedIds }
        if (staleIds.isNotEmpty()) {
            mediaDao.deleteByLocalIds(staleIds)
            Log.i(TAG, "Removed ${staleIds.size} stale items")
        }
    }

    suspend fun getDuplicateGroups(): List<List<MediaItemEntity>> {
        val duplicates = mediaDao.duplicateHashes()
        return duplicates.map { result ->
            mediaDao.byHash(result.fileHash)?.let { listOf(it) } ?: emptyList()
        }.filter { it.isNotEmpty() }
    }

    suspend fun totalCount(): Int = mediaDao.count()

    companion object {
        private const val TAG = "GalleryRepository"
    }
}
