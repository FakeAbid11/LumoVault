package com.lumovault.core.di

import android.content.Context
import com.lumovault.core.storage.EncryptedSettingsStore
import com.lumovault.core.tdlib.TdLibClient
import com.lumovault.core.tdlib.TdLibConfig
import com.lumovault.core.tdlib.TdLibConnectionManager
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object TdLibModule {

    @Provides
    @Singleton
    fun provideTdLibConfig(): TdLibConfig {
        return TdLibConfig(
            apiId = TdLibConfig.API_ID,
            apiHash = TdLibConfig.API_HASH,
            storageChannelName = TdLibConfig.STORAGE_CHANNEL_NAME,
            storageChannelDescription = TdLibConfig.STORAGE_CHANNEL_DESCRIPTION,
            maxFileSizeBytes = TdLibConfig.MAX_FILE_SIZE_BYTES,
            databaseKeyLength = TdLibConfig.DATABASE_KEY_LENGTH
        )
    }

    @Provides
    @Singleton
    fun provideTdLibClient(
        @ApplicationContext context: Context,
        config: TdLibConfig
    ): TdLibClient {
        return TdLibClient(context, config)
    }

    @Provides
    @Singleton
    fun provideTdLibConnectionManager(
        client: TdLibClient,
        encryptedSettings: EncryptedSettingsStore
    ): TdLibConnectionManager {
        return TdLibConnectionManager(
            client = client,
            databaseKeyProvider = { encryptedSettings.getDatabaseKey() }
        )
    }
}
