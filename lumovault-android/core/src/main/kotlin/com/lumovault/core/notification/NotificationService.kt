package com.lumovault.core.notification

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.lumovault.app.MainActivity
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class NotificationService @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    init {
        createChannels()
    }

    private fun createChannels() {
        val channels = listOf(
            NotificationChannel(
                CHANNEL_BACKUP,
                "Backup",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows backup progress"
            },
            NotificationChannel(
                CHANNEL_RESTORE,
                "Restore",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows restore progress"
            },
            NotificationChannel(
                CHANNEL_GENERAL,
                "General",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "General notifications"
            },
        )

        notificationManager.createNotificationChannels(channels)
    }

    fun showBackupProgress(completed: Int, total: Int, percent: Int) {
        val intent = Intent(context, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_BACKUP)
            .setSmallIcon(android.R.drawable.ic_menu_upload)
            .setContentTitle("Backing up photos")
            .setContentText("$completed / $total photos")
            .setProgress(100, percent, false)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .build()

        notificationManager.notify(NOTIFICATION_BACKUP, notification)
    }

    fun cancelBackupProgress() {
        notificationManager.cancel(NOTIFICATION_BACKUP)
    }

    fun showRestoreProgress(completed: Int, total: Int, percent: Int) {
        val intent = Intent(context, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_RESTORE)
            .setSmallIcon(android.R.drawable.ic_menu_download)
            .setContentTitle("Restoring photos")
            .setContentText("$completed / $total photos")
            .setProgress(100, percent, false)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .build()

        notificationManager.notify(NOTIFICATION_RESTORE, notification)
    }

    fun cancelRestoreProgress() {
        notificationManager.cancel(NOTIFICATION_RESTORE)
    }

    fun showBackupComplete(count: Int) {
        val intent = Intent(context, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_BACKUP)
            .setSmallIcon(android.R.drawable.ic_menu_upload)
            .setContentTitle("Backup complete")
            .setContentText("$count photos backed up")
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(NOTIFICATION_BACKUP_COMPLETE, notification)
    }

    fun showError(title: String, message: String) {
        val intent = Intent(context, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_GENERAL)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(message)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        notificationManager.notify(NOTIFICATION_ERROR, notification)
    }

    companion object {
        const val CHANNEL_BACKUP = "backup"
        const val CHANNEL_RESTORE = "restore"
        const val CHANNEL_GENERAL = "general"

        private const val NOTIFICATION_BACKUP = 1001
        private const val NOTIFICATION_BACKUP_COMPLETE = 1002
        private const val NOTIFICATION_RESTORE = 1003
        private const val NOTIFICATION_ERROR = 1004
    }
}
