package com.lumovault.feature.people.repository

import android.util.Log
import com.lumovault.core.database.daos.MediaDao
import com.lumovault.core.database.entities.MediaItemEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

data class Person(
    val id: String,
    val name: String,
    val faceCount: Int,
    val thumbnailPath: String?,
    val lastSeenAt: Long,
    val embedding: FloatArray? = null,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is Person) return false
        return id == other.id
    }
    override fun hashCode(): Int = id.hashCode()
}

data class FaceEntry(
    val id: String,
    val personId: String,
    val mediaItemId: String,
    val filePath: String,
    val thumbnailPath: String?,
    val embedding: FloatArray?,
    val detectedAt: Long,
)

@Singleton
class PeopleRepository @Inject constructor(
    private val mediaDao: MediaDao,
    private val onnxFaceService: OnnxFaceService,
    private val faceGroupingService: FaceGroupingService,
) {
    private val faceEntries = mutableListOf<FaceEntry>()
    private val people = mutableListOf<Person>()

    suspend fun getPeople(): List<Person> = withContext(Dispatchers.IO) {
        people.sortedByDescending { it.faceCount }
    }

    suspend fun getPerson(id: String): Person? = people.find { it.id == id }

    suspend fun getPersonFaces(personId: String): List<FaceEntry> {
        return faceEntries.filter { it.personId == personId }
    }

    /**
     * Process all media items using ONNX SCRFD detector + ArcFace embedder.
     */
    suspend fun processAllMedia() = withContext(Dispatchers.IO) {
        if (!onnxFaceService.isReady) onnxFaceService.init()

        val items = mediaDao.getAllItems()
        var processedCount = 0

        for (item in items) {
            if (item.mimeType.startsWith("video/")) continue
            if (item.filePath.isBlank()) continue

            try {
                val faces = onnxFaceService.detectAndEmbed(item.filePath)
                for (face in faces) {
                    val entry = FaceEntry(
                        id = "face_${item.localId}_${processedCount}",
                        personId = "",
                        mediaItemId = item.localId,
                        filePath = item.filePath,
                        thumbnailPath = item.filePath,
                        embedding = face.embedding,
                        detectedAt = System.currentTimeMillis(),
                    )
                    faceEntries.add(entry)
                }
                if (faces.isNotEmpty()) processedCount++
            } catch (e: Exception) {
                Log.e(TAG, "Failed to process ${item.localId}", e)
            }
        }

        clusterFaces()
        Log.i(TAG, "Processed $processedCount items, found ${people.size} people")
    }

    /**
     * Cluster faces using average-linkage on 512-dim ArcFace embeddings.
     */
    fun clusterFaces() {
        val embeddings = faceEntries.mapNotNull { it.embedding }
        if (embeddings.isEmpty()) return

        val clusters = faceGroupingService.clusterFaces(embeddings)

        people.clear()
        for ((index, cluster) in clusters.withIndex()) {
            val personId = "person_${index}_${System.currentTimeMillis()}"

            for (faceIndex in cluster.faceIndices) {
                if (faceIndex < faceEntries.size) {
                    faceEntries[faceIndex] = faceEntries[faceIndex].copy(personId = personId)
                }
            }

            val personFaces = faceEntries.filter { it.personId == personId }
            val mostRecent = personFaces.maxByOrNull { it.detectedAt }

            people.add(
                Person(
                    id = personId,
                    name = "Person ${index + 1}",
                    faceCount = personFaces.size,
                    thumbnailPath = mostRecent?.filePath,
                    lastSeenAt = mostRecent?.detectedAt ?: 0L,
                    embedding = cluster.centroid,
                )
            )
        }
    }

    suspend fun renamePerson(personId: String, newName: String) {
        val index = people.indexOfFirst { it.id == personId }
        if (index >= 0) {
            people[index] = people[index].copy(name = newName)
        }
    }

    suspend fun mergePeople(targetId: String, sourceId: String) {
        val target = people.find { it.id == targetId } ?: return
        val source = people.find { it.id == sourceId } ?: return

        faceEntries.forEachIndexed { idx, entry ->
            if (entry.personId == sourceId) {
                faceEntries[idx] = entry.copy(personId = targetId)
            }
        }

        if (target.embedding != null && source.embedding != null) {
            val mergedCluster = faceGroupingService.mergePeople(
                ClusterResult(faceEntries.filter { it.personId == targetId }.map { faceEntries.indexOf(it) }, target.embedding),
                ClusterResult(faceEntries.filter { it.personId == sourceId }.map { faceEntries.indexOf(it) }, source.embedding),
                faceEntries.mapNotNull { it.embedding },
            )
            people.removeAll { it.id == sourceId }
            val mergedIndex = people.indexOfFirst { it.id == targetId }
            if (mergedIndex >= 0) {
                people[mergedIndex] = target.copy(
                    faceCount = faceEntries.count { it.personId == targetId },
                    embedding = mergedCluster.centroid,
                )
            }
        }
    }

    suspend fun deletePerson(personId: String) {
        people.removeAll { it.id == personId }
        faceEntries.removeAll { it.personId == personId }
    }

    companion object {
        private const val TAG = "PeopleRepository"
    }
}
