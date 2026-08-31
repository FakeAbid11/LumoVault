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
    private val faceDetectionService: FaceDetectionService,
    private val faceGroupingService: FaceGroupingService,
) {
    private val faceEntries = mutableListOf<FaceEntry>()
    private val people = mutableListOf<Person>()

    /**
     * Get all people sorted by photo count.
     */
    suspend fun getPeople(): List<Person> = withContext(Dispatchers.IO) {
        people.sortedByDescending { it.faceCount }
    }

    /**
     * Get a person by ID.
     */
    suspend fun getPerson(id: String): Person? {
        return people.find { it.id == id }
    }

    /**
     * Get all face entries for a person.
     */
    suspend fun getPersonFaces(personId: String): List<FaceEntry> {
        return faceEntries.filter { it.personId == personId }
    }

    /**
     * Process all media items for face detection and grouping.
     */
    suspend fun processAllMedia() = withContext(Dispatchers.IO) {
        val items = mediaDao.getAllItems()
        var processedCount = 0

        for (item in items) {
            if (item.mimeType.startsWith("video/")) continue

            try {
                val faces = faceDetectionService.detectFaces(item.filePath)
                if (faces.isEmpty()) continue

                val bitmap = faceDetectionService.getFaceThumbnail(faces.first().faceBitmap)

                val entry = FaceEntry(
                    id = "face_${item.localId}_${System.currentTimeMillis()}",
                    personId = "", // Will be assigned after clustering
                    mediaItemId = item.localId,
                    filePath = item.filePath,
                    thumbnailPath = item.filePath, // Use original as thumbnail for now
                    embedding = faceGroupingService.generateEmbedding(
                        faces.first(),
                        faces.first().boundingBox.width(),
                        faces.first().boundingBox.height(),
                    ),
                    detectedAt = System.currentTimeMillis(),
                )
                faceEntries.add(entry)
                processedCount++
            } catch (e: Exception) {
                Log.e(TAG, "Failed to process ${item.localId}", e)
            }
        }

        // Cluster faces into people
        clusterFaces()
        Log.i(TAG, "Processed $processedCount items, found ${people.size} people")
    }

    /**
     * Cluster all face entries into people.
     */
    fun clusterFaces() {
        val embeddings = faceEntries.mapNotNull { it.embedding }
        if (embeddings.isEmpty()) return

        val clusters = faceGroupingService.clusterFaces(embeddings)

        people.clear()
        for ((index, cluster) in clusters.withIndex()) {
            val personId = "person_${index}_${System.currentTimeMillis()}"

            // Assign faces to this person
            for (faceIndex in cluster.faceIndices) {
                if (faceIndex < faceEntries.size) {
                    faceEntries[faceIndex] = faceEntries[faceIndex].copy(personId = personId)
                }
            }

            // Find most recent photo for this person
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

    /**
     * Rename a person.
     */
    suspend fun renamePerson(personId: String, newName: String) {
        val index = people.indexOfFirst { it.id == personId }
        if (index >= 0) {
            people[index] = people[index].copy(name = newName)
        }
    }

    /**
     * Merge two people into one.
     */
    suspend fun mergePeople(targetId: String, sourceId: String) {
        val target = people.find { it.id == targetId } ?: return
        val source = people.find { it.id == sourceId } ?: return

        // Reassign faces
        faceEntries.forEach { entry ->
            if (entry.personId == sourceId) {
                val updated = entry.copy(personId = targetId)
                faceEntries[faceEntries.indexOf(entry)] = updated
            }
        }

        // Merge embeddings
        if (target.embedding != null && source.embedding != null) {
            val merged = faceGroupingService.mergeEmbeddings(
                target.embedding,
                target.faceCount,
                source.embedding,
            )
            people.removeAll { it.id == sourceId }

            val mergedIndex = people.indexOfFirst { it.id == targetId }
            if (mergedIndex >= 0) {
                people[mergedIndex] = target.copy(
                    faceCount = target.faceCount + source.faceCount,
                    embedding = merged,
                )
            }
        }
    }

    /**
     * Delete a person and all their face entries.
     */
    suspend fun deletePerson(personId: String) {
        people.removeAll { it.id == personId }
        faceEntries.removeAll { it.personId == personId }
    }

    companion object {
        private const val TAG = "PeopleRepository"
    }
}
