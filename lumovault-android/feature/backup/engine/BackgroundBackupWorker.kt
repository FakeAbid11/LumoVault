package com.lumovault.feature.backup.engine

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.lumovault.feature.backup.model.BackupSettings
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit

@HiltWorker
class BackgroundBackupWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted workerParams: WorkerParameters,
    private val backupEngine: BackupEngine,
    private val backupScheduler: BackupScheduler,
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        Log.i(TAG, "Background backup worker started")

        val settings = BackupSettings(
            isAutoBackupEnabled = true,
            wifiOnly = true,
            chargingOnly = false,
            backupPhotos = true,
            backupVideos = true,
        )

        if (!backupScheduler.canRunBackup(settings)) {
            Log.i(TAG, "Backup conditions not met, skipping")
            return Result.success()
        }

        return try {
            backupEngine.startBackup(settings)
            // Wait for backup to complete
            while (backupEngine.status.value == BackupStatus.UPLOADING ||
                backupEngine.status.value == BackupStatus.SCANNING) {
                if (isStopped) {
                    backupEngine.cancelBackup()
                    return Result.success()
                }
                Thread.sleep(1000)
            }

            val finalStatus = backupEngine.status.value
            when (finalStatus) {
                BackupStatus.COMPLETED -> {
                    Log.i(TAG, "Background backup completed")
                    Result.success()
                }
                BackupStatus.FAILED -> {
                    Log.e(TAG, "Background backup failed")
                    Result.retry()
                }
                else -> Result.success()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Background backup error", e)
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "BackgroundBackupWorker"
        private const val WORK_NAME = "lumovault_background_backup"

        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.UNMETERED)
                .setRequiresBatteryNotLow(true)
                .build()

            val workRequest = PeriodicWorkRequestBuilder<BackgroundBackupWorker>(
                15, TimeUnit.MINUTES,
            )
                .setConstraints(constraints)
                .setBackoffCriteria(
                    androidx.work.BackoffPolicy.EXPONENTIAL,
                    30,
                    TimeUnit.SECONDS,
                )
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                workRequest,
            )

            Log.i(TAG, "Background backup scheduled")
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            Log.i(TAG, "Background backup cancelled")
        }
    }
}
