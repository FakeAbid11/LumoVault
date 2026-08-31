package com.lumovault.core.di

import android.content.Context
import androidx.room.Room
import com.lumovault.core.database.AppDatabase
import com.lumovault.core.database.daos.FaceDao
import com.lumovault.core.database.daos.MediaDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase {
        return Room.databaseBuilder(
            context,
            AppDatabase::class.java,
            AppDatabase.DATABASE_NAME
        )
            .addMigrations(*AppDatabase.allMigrations)
            .build()
    }

    @Provides
    fun provideMediaDao(database: AppDatabase): MediaDao = database.mediaDao()

    @Provides
    fun provideFaceDao(database: AppDatabase): FaceDao = database.faceDao()
}
