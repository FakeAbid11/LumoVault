package com.lumovault.feature.restore.engine

import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Persists the set of already-restored file hashes for differential resume.
 * On restore restart, items whose hash is already in this set are skipped.
 */
@Singleton
class RestoreStateStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val prefs: SharedPreferences = context.getSharedPreferences(
        "lumovault_restore_state",
        Context.MODE_PRIVATE,
    )

    fun getRestoredHashes(): Set<String> {
        return prefs.getStringSet(KEY_RESTORED_HASHES, emptySet()) ?: emptySet()
    }

    fun addRestoredHash(hash: String) {
        val current = getRestoredHashes().toMutableSet()
        current.add(hash)
        prefs.edit().putStringSet(KEY_RESTORED_HASHES, current).apply()
    }

    fun addRestoredHashes(hashes: Set<String>) {
        val current = getRestoredHashes().toMutableSet()
        current.addAll(hashes)
        prefs.edit().putStringSet(KEY_RESTORED_HASHES, current).apply()
    }

    fun isRestored(hash: String): Boolean {
        return hash in getRestoredHashes()
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    fun getRestoredCount(): Int {
        return getRestoredHashes().size
    }

    companion object {
        private const val KEY_RESTORED_HASHES = "restored_hashes"
    }
}
