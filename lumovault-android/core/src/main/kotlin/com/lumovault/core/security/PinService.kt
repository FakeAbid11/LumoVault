package com.lumovault.core.security

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PinService @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)

    private val prefs: SharedPreferences = EncryptedSharedPreferences.create(
        "lumovault_security",
        masterKeyAlias,
        context,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    fun isPinSet(): Boolean {
        return prefs.contains(KEY_PIN_HASH)
    }

    fun setPin(pin: String) {
        val hash = hashPin(pin)
        prefs.edit().putString(KEY_PIN_HASH, hash).apply()
    }

    fun verifyPin(pin: String): Boolean {
        val stored = prefs.getString(KEY_PIN_HASH, null) ?: return false
        return hashPin(pin) == stored
    }

    fun clearPin() {
        prefs.edit().remove(KEY_PIN_HASH).apply()
    }

    fun getPinAttemptCount(): Int {
        return prefs.getInt(KEY_ATTEMPT_COUNT, 0)
    }

    fun incrementAttemptCount() {
        val count = getPinAttemptCount() + 1
        prefs.edit().putInt(KEY_ATTEMPT_COUNT, count).apply()
    }

    fun resetAttemptCount() {
        prefs.edit().putInt(KEY_ATTEMPT_COUNT, 0).apply()
    }

    fun getLockoutDuration(): Long {
        val attempts = getPinAttemptCount()
        return when {
            attempts >= 10 -> 30 * 60 * 1000L // 30 minutes
            attempts >= 5 -> 5 * 60 * 1000L // 5 minutes
            attempts >= 3 -> 60 * 1000L // 1 minute
            else -> 0L
        }
    }

    private fun hashPin(pin: String): String {
        val salt = "lumovault_salt_v1"
        val bytes = (salt + pin + salt).toByteArray()
        val md = java.security.MessageDigest.getInstance("SHA-256")
        val digest = md.digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }

    companion object {
        private const val KEY_PIN_HASH = "pin_hash"
        private const val KEY_ATTEMPT_COUNT = "attempt_count"
    }
}
