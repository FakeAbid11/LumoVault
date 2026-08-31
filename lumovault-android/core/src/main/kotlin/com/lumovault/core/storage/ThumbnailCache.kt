package com.lumovault.core.storage

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.io.FileOutputStream
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ThumbnailCache @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val memoryCache = object : LruCache<String, Bitmap>(maxMemorySize()) {
        override fun sizeOf(key: String, value: Bitmap): Int {
            return value.byteCount / 1024
        }
    }

    private val diskCacheDir: File = File(context.cacheDir, "thumbnails").apply {
        mkdirs()
    }

    fun getThumbnail(mediaId: String): Bitmap? {
        // Check memory cache first
        memoryCache.get(mediaId)?.let { return it }

        // Check disk cache
        val file = File(diskCacheDir, "$mediaId.jpg")
        if (file.exists()) {
            val bitmap = BitmapFactory.decodeFile(file.absolutePath)
            if (bitmap != null) {
                memoryCache.put(mediaId, bitmap)
                return bitmap
            }
        }

        return null
    }

    fun putThumbnail(mediaId: String, bitmap: Bitmap) {
        memoryCache.put(mediaId, bitmap)

        // Write to disk cache
        val file = File(diskCacheDir, "$mediaId.jpg")
        try {
            FileOutputStream(file).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
            }
        } catch (_: Exception) {
            // Ignore write errors
        }
    }

    fun removeThumbnail(mediaId: String) {
        memoryCache.remove(mediaId)
        File(diskCacheDir, "$mediaId.jpg").delete()
    }

    fun clear() {
        memoryCache.evictAll()
        diskCacheDir.listFiles()?.forEach { it.delete() }
    }

    fun getDiskCacheSize(): Long {
        return diskCacheDir.listFiles()?.sumOf { it.length() } ?: 0L
    }

    fun evictIfOverSize(maxSizeBytes: Long) {
        val files = diskCacheDir.listFiles()?.sortedByDescending { it.lastModified() } ?: return
        var totalSize = files.sumOf { it.length() }

        for (file in files) {
            if (totalSize <= maxSizeBytes) break
            totalSize -= file.length()
            file.delete()
        }
    }

    private fun maxMemorySize(): Int {
        val maxMemory = (Runtime.getRuntime().maxMemory() / 1024).toInt()
        return maxMemory / 8 // Use 1/8 of available memory
    }
}
