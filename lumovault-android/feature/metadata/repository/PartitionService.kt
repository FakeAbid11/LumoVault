package com.lumovault.feature.metadata.repository

import com.lumovault.core.database.entities.MediaItemEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.ceil

/**
 * Splits metadata into fixed-size partitions (~200KB each) that fit in Telegram captions.
 */
@Singleton
class PartitionService @Inject constructor() {

    companion object {
        const val TARGET_PARTITION_SIZE = 200 * 1024
        const val MAX_ITEMS_PER_PARTITION = 500
    }

    /**
     * Encode a list of media items into partitions, each under the target size.
     */
    suspend fun createPartitions(
        items: List<MediaItemEntity>,
    ): Result<List<MetadataPartition>> = withContext(Dispatchers.Default) {
        try {
            val sorted = items.sortedBy { it.createdAt }
            val partitions = mutableListOf<MetadataPartition>()

            var i = 0
            while (i < sorted.size) {
                val partitionItems = mutableListOf<MediaItemEntity>()
                var currentSize = 0
                var count = 0

                while (i < sorted.size && count < MAX_ITEMS_PER_PARTITION) {
                    val item = sorted[i]
                    val encoded = encodeItem(item)
                    val encodedSize = encoded.toByteArray().size

                    if (currentSize + encodedSize > TARGET_PARTITION_SIZE && partitionItems.isNotEmpty()) {
                        break
                    }

                    partitionItems.add(item)
                    currentSize += encodedSize
                    count++
                    i++
                }

                partitions.add(
                    MetadataPartition(
                        index = partitions.size,
                        items = partitionItems,
                        totalSize = currentSize,
                    )
                )
            }

            Result.success(partitions)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Decode items from a partition caption text.
     */
    fun decodePartition(caption: String): List<MetadataItem> {
        if (!caption.startsWith("LUMOVAULT_V2|")) return emptyList()

        return try {
            val itemsStr = caption.removePrefix("LUMOVAULT_V2|")
            val items = mutableListOf<MetadataItem>()

            for (line in itemsStr.lines()) {
                if (line.isBlank()) continue
                val kvPairs = mutableMapOf<String, String>()
                for (kv in line.split("|")) {
                    val parts = kv.split(":", limit = 2)
                    if (parts.size == 2) kvPairs[parts[0]] = parts[1]
                }

                if (kvPairs.containsKey("h")) {
                    items.add(
                        MetadataItem(
                            fileHash = kvPairs["h"] ?: "",
                            createdAt = kvPairs["c"]?.toLongOrNull() ?: 0L,
                            modifiedAt = kvPairs["m"]?.toLongOrNull() ?: 0L,
                            fileSize = kvPairs["s"]?.toLongOrNull() ?: 0L,
                            mimeType = kvPairs["t"] ?: "image/jpeg",
                            width = kvPairs["w"]?.toIntOrNull() ?: 0,
                            height = kvPairs["he"]?.toIntOrNull() ?: 0,
                        )
                    )
                }
            }
            items
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun encodeItem(item: MediaItemEntity): String {
        return listOf(
            "h:${item.fileHash}",
            "c:${item.createdAt}",
            "m:${item.modifiedAt}",
            "s:${item.fileSize}",
            "t:${item.mimeType}",
            "w:${item.width}",
            "he:${item.height}",
        ).joinToString("|")
    }
}

data class MetadataPartition(
    val index: Int,
    val items: List<MediaItemEntity>,
    val totalSize: Int,
) {
    val caption: String
        get() = buildString {
            append("LUMOVAULT_V2|")
            items.forEach { item ->
                append("h:${item.fileHash}")
                append("|c:${item.createdAt}")
                append("|m:${item.modifiedAt}")
                append("|s:${item.fileSize}")
                append("|t:${item.mimeType}")
                append("|w:${item.width}")
                append("|he:${item.height}")
                append("\n")
            }
        }
}

data class MetadataItem(
    val fileHash: String,
    val createdAt: Long,
    val modifiedAt: Long,
    val fileSize: Long,
    val mimeType: String,
    val width: Int,
    val height: Int,
)
