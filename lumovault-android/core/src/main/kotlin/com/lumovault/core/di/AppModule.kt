package com.lumovault.core.di

import android.content.Context
import androidx.work.WorkManager
import com.lumovault.core.device.DeviceInfoService
import com.lumovault.core.notifications.NotificationService
import com.lumovault.core.permissions.PermissionService
import com.lumovault.core.security.BiometricService
import com.lumovault.core.security.PinService
import com.lumovault.core.storage.EncryptedSettingsStore
import com.lumovault.core.storage.ThumbnailCache
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides
    @Singleton
    fun provideEncryptedSettingsStore(@ApplicationContext context: Context): EncryptedSettingsStore {
        return EncryptedSettingsStore(context)
    }

    @Provides
    @Singleton
    fun provideWorkManager(@ApplicationContext context: Context): WorkManager {
        return WorkManager.getInstance(context)
    }

    @Provides
    @Singleton
    fun provideDeviceInfoService(@ApplicationContext context: Context): DeviceInfoService {
        return DeviceInfoService(context)
    }

    @Provides
    @Singleton
    fun providePermissionService(@ApplicationContext context: Context): PermissionService {
        return PermissionService(context)
    }

    @Provides
    @Singleton
    fun provideNotificationService(@ApplicationContext context: Context): NotificationService {
        return NotificationService(context)
    }

    @Provides
    @Singleton
    fun provideBiometricService(@ApplicationContext context: Context): BiometricService {
        return BiometricService(context)
    }

    @Provides
    @Singleton
    fun providePinService(@ApplicationContext context: Context): PinService {
        return PinService(context)
    }

    @Provides
    @Singleton
    fun provideThumbnailCache(@ApplicationContext context: Context): ThumbnailCache {
        return ThumbnailCache(context)
    }
}
