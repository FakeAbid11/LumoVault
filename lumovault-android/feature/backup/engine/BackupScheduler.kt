package com.lumovault.feature.backup.engine

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.util.Log
import com.lumovault.core.storage.EncryptedSettingsStore
import com.lumovault.feature.backup.model.BackupSettings
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class BackupScheduler @Inject constructor(
    @ApplicationContext private val context: Context,
    private val encryptedSettings: EncryptedSettingsStore,
) {
    private val connectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val batteryManager =
        context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager

    fun canRunBackup(settings: BackupSettings): Boolean {
        if (!settings.isAutoBackupEnabled) return false

        if (settings.wifiOnly && !isOnWifi()) {
            Log.d(TAG, "Skipping backup: not on WiFi")
            return false
        }

        if (settings.chargingOnly && !isCharging()) {
            Log.d(TAG, "Skipping backup: not charging")
            return false
        }

        if (getBatteryPercentage() < MIN_BATTERY_LEVEL) {
            Log.d(TAG, "Skipping backup: battery too low (${getBatteryPercentage()}%)")
            return false
        }

        return true
    }

    fun isOnWifi(): Boolean {
        val network = connectivityManager.activeNetwork ?: return false
        val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }

    fun isCharging(): Boolean {
        return batteryManager.isCharging
    }

    fun getBatteryPercentage(): Int {
        return batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
    }

    companion object {
        private const val TAG = "BackupScheduler"
        private const val MIN_BATTERY_LEVEL = 20
    }
}
