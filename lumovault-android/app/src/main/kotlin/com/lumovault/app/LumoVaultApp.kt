package com.lumovault.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

@HiltAndroidApp
class LumoVaultApp : Application(), Configuration.Provider {

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        val manager = getSystemService(NotificationManager::class.java)

        val backupChannel = NotificationChannel(
            CHANNEL_BACKUP_PROGRESS,
            "Backup Progress",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Shows backup progress"
            setShowBadge(false)
        }

        val backupAlertsChannel = NotificationChannel(
            CHANNEL_BACKUP_ALERTS,
            "Backup Alerts",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Backup completed or failed notifications"
        }

        val restoreChannel = NotificationChannel(
            CHANNEL_RESTORE,
            "Restore",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Shows restore progress"
            setShowBadge(false)
        }

        manager.createNotificationChannels(
            listOf(backupChannel, backupAlertsChannel, restoreChannel)
        )
    }

    companion object {
        const val CHANNEL_BACKUP_PROGRESS = "lumovault_backup_progress"
        const val CHANNEL_BACKUP_ALERTS = "lumovault_backup_alerts"
        const val CHANNEL_RESTORE = "lumovault_restore"
    }
}
