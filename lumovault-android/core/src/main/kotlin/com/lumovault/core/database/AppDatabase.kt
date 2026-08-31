package com.lumovault.core.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.lumovault.core.database.converters.EmbeddingConverter
import com.lumovault.core.database.converters.StringListConverter
import com.lumovault.core.database.daos.FaceDao
import com.lumovault.core.database.daos.MediaDao
import com.lumovault.core.database.entities.FaceEntity
import com.lumovault.core.database.entities.FacePersonEntity
import com.lumovault.core.database.entities.FaceScanEntity
import com.lumovault.core.database.entities.MediaItemEntity
import com.lumovault.core.database.entities.PersonEntity

@Database(
    entities = [
        MediaItemEntity::class,
        FaceEntity::class,
        PersonEntity::class,
        FacePersonEntity::class,
        FaceScanEntity::class,
    ],
    version = AppDatabase.SCHEMA_VERSION,
    exportSchema = true,
)
@TypeConverters(StringListConverter::class, EmbeddingConverter::class)
abstract class AppDatabase : RoomDatabase() {

    abstract fun mediaDao(): MediaDao
    abstract fun faceDao(): FaceDao

    companion object {
        const val DATABASE_NAME = "lumovault.sqlite"
        const val SCHEMA_VERSION = 13

        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE media_items ADD COLUMN is_hidden INTEGER NOT NULL DEFAULT 0")
            }
        }

        val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE media_items ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0")
            }
        }

        val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE media_items ADD COLUMN is_trashed INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE media_items ADD COLUMN trashed_at INTEGER")
                db.execSQL("CREATE INDEX idx_media_items_trashed_trashed_at ON media_items(is_trashed, trashed_at)")
            }
        }

        val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE media_items ADD COLUMN is_excluded INTEGER NOT NULL DEFAULT 0")
            }
        }

        val MIGRATION_5_6 = object : Migration(5, 6) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE media_items ADD COLUMN album_name TEXT")
                db.execSQL("CREATE INDEX idx_media_items_album_name ON media_items(album_name)")
            }
        }

        val MIGRATION_6_7 = object : Migration(6, 7) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE media_items ADD COLUMN device_folder TEXT")
            }
        }

        val MIGRATION_7_8 = object : Migration(7, 8) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE media_items ADD COLUMN description TEXT")
                db.execSQL("ALTER TABLE media_items ADD COLUMN tags TEXT NOT NULL DEFAULT '[]'")
            }
        }

        val MIGRATION_8_9 = object : Migration(8, 9) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("CREATE TABLE IF NOT EXISTS faces (")
                db.execSQL("id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,")
                db.execSQL("media_item_id TEXT NOT NULL,")
                db.execSQL("bounding_box_x REAL NOT NULL,")
                db.execSQL("bounding_box_y REAL NOT NULL,")
                db.execSQL("bounding_box_width REAL NOT NULL,")
                db.execSQL("bounding_box_height REAL NOT NULL,")
                db.execSQL("landmarks TEXT NOT NULL DEFAULT '{}',")
                db.execSQL("embedding TEXT NOT NULL DEFAULT '[]',")
                db.execSQL("confidence REAL NOT NULL,")
                db.execSQL("thumbnail_path TEXT,")
                db.execSQL("person_id INTEGER,")
                db.execSQL("created_at INTEGER NOT NULL)")
                db.execSQL("CREATE INDEX idx_faces_media_item_id ON faces(media_item_id)")
                db.execSQL("CREATE INDEX idx_faces_person_id ON faces(person_id)")

                db.execSQL("CREATE TABLE IF NOT EXISTS people (")
                db.execSQL("id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,")
                db.execSQL("name TEXT,")
                db.execSQL("thumbnail_face_id INTEGER,")
                db.execSQL("created_at INTEGER NOT NULL,")
                db.execSQL("updated_at INTEGER NOT NULL,")
                db.execSQL("centroid_embedding TEXT NOT NULL DEFAULT '[]')")

                db.execSQL("CREATE TABLE IF NOT EXISTS face_persons (")
                db.execSQL("face_id INTEGER NOT NULL,")
                db.execSQL("person_id INTEGER NOT NULL,")
                db.execSQL("assigned_at INTEGER NOT NULL,")
                db.execSQL("PRIMARY KEY(face_id, person_id))")
                db.execSQL("CREATE INDEX idx_face_persons_person_id ON face_persons(person_id)")

                db.execSQL("CREATE TABLE IF NOT EXISTS face_scans (")
                db.execSQL("media_item_id TEXT NOT NULL PRIMARY KEY,")
                db.execSQL("scanned_at INTEGER NOT NULL,")
                db.execSQL("face_count INTEGER NOT NULL DEFAULT 0)")
            }
        }

        val MIGRATION_9_10 = object : Migration(9, 10) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE media_items ADD COLUMN thumbnail_path TEXT")
            }
        }

        val MIGRATION_10_11 = object : Migration(10, 11) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE media_items ADD COLUMN latitude REAL")
                db.execSQL("ALTER TABLE media_items ADD COLUMN longitude REAL")
                db.execSQL("ALTER TABLE media_items ADD COLUMN is_location_user_set INTEGER NOT NULL DEFAULT 0")
            }
        }

        val MIGRATION_11_12 = object : Migration(11, 12) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE media_items ADD COLUMN error_message TEXT")
            }
        }

        val MIGRATION_12_13 = object : Migration(12, 13) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE media_items ADD COLUMN ai_labels TEXT NOT NULL DEFAULT '[]'")
            }
        }

        val allMigrations = arrayOf(
            MIGRATION_1_2,
            MIGRATION_2_3,
            MIGRATION_3_4,
            MIGRATION_4_5,
            MIGRATION_5_6,
            MIGRATION_6_7,
            MIGRATION_7_8,
            MIGRATION_8_9,
            MIGRATION_9_10,
            MIGRATION_10_11,
            MIGRATION_11_12,
            MIGRATION_12_13,
        )
    }
}
