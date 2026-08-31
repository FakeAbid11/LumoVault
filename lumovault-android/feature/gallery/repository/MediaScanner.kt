package com.lumovault.feature.gallery.repository

import android.content.ContentResolver
import android.content.ContentUris
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import com.lumovault.core.database.entities.MediaItemEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MediaScanner @Inject constructor(
    private val contentResolver: ContentResolver,
) {
    suspend fun scanFolders(
        folders: Set<String>? = null,
        sinceTimestamp: Long? = null,
    ): List<MediaItemEntity> = withContext(Dispatchers.IO) {
        val items = mutableListOf<MediaItemEntity>()

        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        val videoCollection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }

        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.DATA,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.WIDTH,
            MediaStore.MediaColumns.HEIGHT,
            MediaStore.MediaColumns.DURATION,
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.BUCKET_DISPLAY_NAME,
            MediaStore.MediaColumns.RELATIVE_PATH,
        )

        val sortOrder = "${MediaStore.MediaColumns.DATE_ADDED} DESC"

        for (collectionUri in listOf(collection, videoCollection)) {
            val selection = buildString {
                append("${MediaStore.MediaColumns.SIZE} > 0")
                if (sinceTimestamp != null) {
                    append(" AND ${MediaStore.MediaColumns.DATE_MODIFIED} > ${sinceTimestamp / 1000}")
                }
                if (folders != null && folders.isNotEmpty()) {
                    val folderConditions = folders.joinToString(" OR ") {
                        "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE '$it%'"
                    }
                    append(" AND ($folderConditions)")
                }
            }

            try {
                contentResolver.query(
                    collectionUri,
                    projection,
                    selection,
                    null,
                    sortOrder,
                )?.use { cursor ->
                    val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                    val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                    val dataCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                    val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
                    val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                    val widthCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.WIDTH)
                    val heightCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.HEIGHT)
                    val durationCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DURATION)
                    val dateAddedCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED)
                    val dateModifiedCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
                    val bucketCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.BUCKET_DISPLAY_NAME)
                    val relativePathCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.RELATIVE_PATH)

                    while (cursor.moveToNext()) {
                        val id = cursor.getLong(idCol)
                        val name = cursor.getString(nameCol) ?: ""
                        val path = cursor.getString(dataCol) ?: ""
                        val mimeType = cursor.getString(mimeCol) ?: ""
                        val size = cursor.getLong(sizeCol)
                        val width = cursor.getInt(widthCol)
                        val height = cursor.getInt(heightCol)
                        val duration = cursor.getInt(durationCol)
                        val dateAdded = cursor.getLong(dateAddedCol) * 1000
                        val dateModified = cursor.getLong(dateModifiedCol) * 1000
                        val bucket = cursor.getString(bucketCol) ?: ""
                        val relativePath = cursor.getString(relativePathCol) ?: ""

                        val localId = id.toString()
                        val fileHash = computeHash(path)

                        val entity = MediaItemEntity(
                            localId = localId,
                            fileHash = fileHash,
                            filePath = path,
                            fileName = name,
                            mimeType = mimeType,
                            fileSize = size,
                            width = width,
                            height = height,
                            durationMs = if (duration > 0) duration else null,
                            createdAt = dateAdded,
                            modifiedAt = dateModified,
                            scannedAt = System.currentTimeMillis(),
                            albumName = bucket,
                            deviceFolder = relativePath,
                        )

                        items.add(entity)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Scan failed for $collectionUri", e)
            }
        }

        Log.i(TAG, "Scanned ${items.size} media items")
        items
    }

    suspend fun getAvailableFolders(): List<FolderInfo> = withContext(Dispatchers.IO) {
        val folders = mutableMapOf<String, FolderInfo>()

        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        val projection = arrayOf(
            MediaStore.MediaColumns.BUCKET_DISPLAY_NAME,
            MediaStore.MediaColumns.RELATIVE_PATH,
        )

        val sortOrder = "${MediaStore.MediaColumns.BUCKET_DISPLAY_NAME} ASC"

        contentResolver.query(
            collection,
            projection,
            "${MediaStore.MediaColumns.SIZE} > 0",
            null,
            sortOrder,
        )?.use { cursor ->
            val bucketCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.BUCKET_DISPLAY_NAME)
            val pathCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.RELATIVE_PATH)

            while (cursor.moveToNext()) {
                val bucket = cursor.getString(bucketCol) ?: continue
                val path = cursor.getString(pathCol) ?: continue

                if (bucket !in folders) {
                    folders[bucket] = FolderInfo(
                        name = bucket,
                        relativePath = path,
                        photoCount = 0,
                    )
                }
                folders[bucket] = folders[bucket]!!.copy(
                    photoCount = folders[bucket]!!.photoCount + 1,
                )
            }
        }

        folders.values.toList()
    }

    private fun computeHash(filePath: String): String {
        return try {
            val file = java.io.File(filePath)
            if (!file.exists()) return filePath.hashCode().toString()

            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(8192)
                var read: Int
                while (input.read(buffer).also { read = it } != -1) {
                    digest.update(buffer, 0, read)
                }
            }
            digest.digest().joinToString("") { "%02x".format(it) }
        } catch (e: Exception) {
            filePath.hashCode().toString()
        }
    }

    companion object {
        private const val TAG = "MediaScanner"
    }
}

data class FolderInfo(
    val name: String,
    val relativePath: String,
    val photoCount: Int,
)
