package com.lumovault.core.device

import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.StatFs
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

enum class DeviceBrand {
    XIAOMI,
    SAMSUNG,
    HUAWEI,
    ONEPLUS,
    OPPO,
    REALME,
    OTHER;

    companion object {
        fun fromManufacturer(manufacturer: String): DeviceBrand {
            return when (manufacturer.lowercase()) {
                "xiaomi", "redmi", "poco" -> XIAOMI
                "samsung" -> SAMSUNG
                "huawei", "honor" -> HUAWEI
                "oneplus" -> ONEPLUS
                "oppo" -> OPPO
                "realme" -> REALME
                else -> OTHER
            }
        }
    }
}

@Singleton
class DeviceInfoService @Inject constructor(
    @Suppress("unused") private val context: Context,
) {
    val manufacturer: String = Build.MANUFACTURER
    val model: String = Build.MODEL
    val brand: DeviceBrand = DeviceBrand.fromManufacturer(manufacturer)
    val sdkVersion: Int = Build.VERSION.SDK_INT
    val releaseVersion: String = Build.VERSION.RELEASE
    val supportedAbis: List<String> = Build.SUPPORTED_ABIS.toList()

    val needsBackgroundPermissionGuide: Boolean
        get() = brand in listOf(
            DeviceBrand.XIAOMI,
            DeviceBrand.HUAWEI,
            DeviceBrand.ONEPLUS,
            DeviceBrand.OPPO,
            DeviceBrand.REALME,
        )

    fun getStorageInfo(): StorageInfo {
        val stat = StatFs(Environment.getDataDirectory().path)
        val totalBytes = stat.totalBytes
        val availableBytes = stat.availableBytes
        val usedBytes = totalBytes - availableBytes
        return StorageInfo(
            totalBytes = totalBytes,
            usedBytes = usedBytes,
            availableBytes = availableBytes,
        )
    }
}

data class StorageInfo(
    val totalBytes: Long,
    val usedBytes: Long,
    val availableBytes: Long,
) {
    val usedPercentage: Float
        get() = if (totalBytes > 0) usedBytes.toFloat() / totalBytes else 0f
}
