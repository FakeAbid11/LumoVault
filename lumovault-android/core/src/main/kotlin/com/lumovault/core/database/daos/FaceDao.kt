package com.lumovault.core.database.daos

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import com.lumovault.core.database.entities.FaceEntity
import com.lumovault.core.database.entities.FacePersonEntity
import com.lumovault.core.database.entities.FaceScanEntity
import com.lumovault.core.database.entities.PersonEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface FaceDao {

    // Face operations
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertFace(face: FaceEntity): Long

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertFaces(faces: List<FaceEntity>)

    @Query("SELECT * FROM faces WHERE media_item_id = :mediaItemId")
    suspend fun facesForMediaItem(mediaItemId: String): List<FaceEntity>

    @Query("SELECT * FROM faces ORDER BY created_at DESC")
    suspend fun allFaces(): List<FaceEntity>

    @Query("SELECT * FROM faces WHERE person_id IS NULL")
    suspend fun unassignedFaces(): List<FaceEntity>

    @Query("UPDATE faces SET person_id = :personId WHERE id = :faceId")
    suspend fun assignFaceToPerson(faceId: Long, personId: Long)

    @Query("UPDATE faces SET person_id = :personId WHERE id IN (:faceIds)")
    suspend fun assignFacesToPerson(faceIds: List<Long>, personId: Long)

    @Query("UPDATE faces SET person_id = NULL WHERE person_id = :personId")
    suspend fun unassignAllFaces(personId: Long)

    @Update
    suspend fun updateFace(face: FaceEntity)

    // Person operations
    @Query("SELECT * FROM people ORDER BY name ASC")
    fun allPeople(): Flow<List<PersonEntity>>

    @Query("SELECT * FROM people ORDER BY name ASC")
    suspend fun allPeopleRows(): List<PersonEntity>

    @Query("SELECT * FROM people WHERE id = :personId LIMIT 1")
    suspend fun personById(personId: Long): PersonEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun createPerson(person: PersonEntity): Long

    @Query("UPDATE people SET name = :name, updated_at = :updatedAt WHERE id = :personId")
    suspend fun updatePersonName(personId: Long, name: String, updatedAt: Long)

    @Query("UPDATE people SET thumbnail_face_id = :faceId, updated_at = :updatedAt WHERE id = :personId")
    suspend fun setPersonThumbnail(personId: Long, faceId: Long, updatedAt: Long)

    @Query("UPDATE people SET centroid_embedding = :embedding, updated_at = :updatedAt WHERE id = :personId")
    suspend fun updateCentroid(personId: Long, embedding: String, updatedAt: Long)

    @Query("DELETE FROM people WHERE id = :personId")
    suspend fun deletePerson(personId: Long)

    @Transaction
    suspend fun mergePersons(targetId: Long, sourceIds: List<Long>) {
        for (sourceId in sourceIds) {
            val faces = facesForPerson(sourceId)
            if (faces.isNotEmpty()) {
                assignFacesToPerson(faces.map { it.id }, targetId)
            }
            deletePerson(sourceId)
        }
    }

    @Query("SELECT f.* FROM faces f WHERE f.person_id = :personId")
    suspend fun facesForPerson(personId: Long): List<FaceEntity>

    @Query("SELECT COUNT(*) FROM faces WHERE media_item_id = :mediaItemId")
    suspend fun faceCount(mediaItemId: String): Int

    @Query("SELECT COUNT(*) FROM faces WHERE person_id IS NOT NULL")
    suspend fun assignedFaceCount(): Int

    // Face scan tracking
    @Query("SELECT COUNT(*) FROM face_scans")
    suspend fun isScanningComplete(): Boolean

    @Query("SELECT media_item_id FROM face_scans")
    suspend fun scannedMediaItemIds(): List<String>

    @Query("SELECT COUNT(DISTINCT media_item_id) FROM face_scans")
    suspend fun scannedMediaItemCount(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun markMediaItemScanned(scan: FaceScanEntity)

    @Query("DELETE FROM face_scans")
    suspend fun clearScanLog()
}
