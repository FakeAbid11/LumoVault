package com.lumovault.core.auth

import android.util.Log
import com.lumovault.core.storage.EncryptedSettingsStore
import com.lumovault.core.tdlib.TdLibConnectionManager
import com.lumovault.core.tdlib.TdLibException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.security.SecureRandom
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

@Singleton
class TelegramAuthRepository @Inject constructor(
    private val connectionManager: TdLibConnectionManager,
    private val encryptedSettings: EncryptedSettingsStore,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _authState = MutableStateFlow(AuthState.UNAUTHENTICATED)
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    /**
     * Check if the user is already authenticated by trying to connect.
     */
    suspend fun checkExistingAuth(): Boolean {
        return try {
            val key = encryptedSettings.getDatabaseKey() ?: generateDatabaseKey()
            encryptedSettings.setDatabaseKey(key)
            connectionManager.connect(key)
            // If connect succeeds, user is already authenticated
            _authState.value = AuthState.AUTHENTICATED
            true
        } catch (e: Exception) {
            Log.d(TAG, "Not authenticated: ${e.message}")
            _authState.value = AuthState.UNAUTHENTICATED
            false
        }
    }

    /**
     * Send phone number to TDLib for authentication.
     */
    suspend fun sendPhoneNumber(phoneNumber: String): Result<Unit> {
        return try {
            val key = encryptedSettings.getDatabaseKey() ?: generateDatabaseKey()
            encryptedSettings.setDatabaseKey(key)

            if (!connectionManager.isConnected) {
                connectionManager.connect(key)
            }

            connectionManager.sendRequest(
                "setAuthenticationPhoneNumber",
                mapOf(
                    "phone_number" to phoneNumber,
                    "settings" to mapOf(
                        "allow_flash_call" to false,
                        "allow_sms_retriever_api" to false,
                    )
                )
            )
            _authState.value = AuthState.PHONE_REQUESTED
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "sendPhoneNumber failed", e)
            Result.failure(e)
        }
    }

    /**
     * Submit the verification code.
     */
    suspend fun submitCode(code: String): Result<Unit> {
        return try {
            connectionManager.sendRequest(
                "checkAuthenticationCode",
                mapOf("code" to code)
            )
            _authState.value = AuthState.CODE_REQUESTED
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "submitCode failed", e)
            Result.failure(e)
        }
    }

    /**
     * Submit the 2FA password.
     */
    suspend fun submitPassword(password: String): Result<Unit> {
        return try {
            connectionManager.sendRequest(
                "checkAuthenticationPassword",
                mapOf("password" to password)
            )
            _authState.value = AuthState.AUTHENTICATED
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "submitPassword failed", e)
            Result.failure(e)
        }
    }

    /**
     * Process TDLib authorization state updates.
     */
    fun handleAuthorizationState(state: Map<String, dynamic>) {
        val type = state["@type"] as? String ?: return
        when (type) {
            "authorizationStateWaitPhoneNumber" -> {
                _authState.value = AuthState.PHONE_REQUESTED
            }
            "authorizationStateWaitCode" -> {
                _authState.value = AuthState.CODE_REQUESTED
            }
            "authorizationStateWaitPassword" -> {
                _authState.value = AuthState.PASSWORD_REQUESTED
            }
            "authorizationStateReady" -> {
                _authState.value = AuthState.AUTHENTICATED
            }
            "authorizationStateLoggingOut" -> {
                _authState.value = AuthState.UNAUTHENTICATED
            }
            "authorizationStateClosed" -> {
                _authState.value = AuthState.UNAUTHENTICATED
            }
        }
    }

    private fun generateDatabaseKey(): String {
        val chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        val random = SecureRandom()
        return (1..32).map { chars[random.nextInt(chars.length)] }.joinToString("")
    }

    companion object {
        private const val TAG = "TelegramAuthRepo"
    }
}
