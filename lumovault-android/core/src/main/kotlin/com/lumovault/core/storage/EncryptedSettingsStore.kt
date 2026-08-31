package com.lumovault.core.storage

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class EncryptedSettingsStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)

    private val encryptedPrefs: SharedPreferences = EncryptedSharedPreferences.create(
        "lumovault_secure_prefs",
        masterKeyAlias,
        context,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    suspend fun getDatabaseKey(): String? {
        return encryptedPrefs.getString(KEY_DATABASE_KEY, null)
    }

    suspend fun setDatabaseKey(key: String) {
        encryptedPrefs.edit().putString(KEY_DATABASE_KEY, key).apply()
    }

    suspend fun getPinHash(): String? {
        return encryptedPrefs.getString(KEY_PIN_HASH, null)
    }

    suspend fun setPinHash(hash: String) {
        encryptedPrefs.edit().putString(KEY_PIN_HASH, hash).apply()
    }

    suspend fun isBiometricLockEnabled(): Boolean {
        return encryptedPrefs.getBoolean(KEY_BIOMETRIC_LOCK, false)
    }

    suspend fun setBiometricLockEnabled(enabled: Boolean) {
        encryptedPrefs.edit().putBoolean(KEY_BIOMETRIC_LOCK, enabled).apply()
    }

    suspend fun isPinLockEnabled(): Boolean {
        return encryptedPrefs.getBoolean(KEY_PIN_LOCK, false)
    }

    suspend fun setPinLockEnabled(enabled: Boolean) {
        encryptedPrefs.edit().putBoolean(KEY_PIN_LOCK, enabled).apply()
    }

    suspend fun getStorageChannelId(): Int? {
        val id = encryptedPrefs.getInt(KEY_STORAGE_CHANNEL_ID, 0)
        return if (id != 0) id else null
    }

    suspend fun setStorageChannelId(channelId: Int) {
        encryptedPrefs.edit().putInt(KEY_STORAGE_CHANNEL_ID, channelId).apply()
    }

    companion object {
        private const val KEY_DATABASE_KEY = "tdlib_database_key"
        private const val KEY_PIN_HASH = "pin_hash"
        private const val KEY_BIOMETRIC_LOCK = "biometric_lock"
        private const val KEY_PIN_LOCK = "pin_lock"
        private const val KEY_STORAGE_CHANNEL_ID = "storage_channel_id"
    }
}
