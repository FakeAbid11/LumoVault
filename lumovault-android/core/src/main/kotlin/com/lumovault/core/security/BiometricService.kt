package com.lumovault.core.security

import android.content.Context
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

enum class BiometricState {
    AVAILABLE,
    NOT_AVAILABLE,
    HARDWARE_UNAVAILABLE,
    NONE_ENROLLED,
}

@Singleton
class BiometricService @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val _state = MutableStateFlow(BiometricState.NOT_AVAILABLE)
    val state: StateFlow<BiometricState> = _state.asStateFlow()

    private val authResult = Channel<BiometricResult>()

    init {
        checkBiometricAvailability()
    }

    private fun checkBiometricAvailability() {
        val biometricManager = BiometricManager.from(context)
        _state.value = when (biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)) {
            BiometricManager.BIOMETRIC_SUCCESS -> BiometricState.AVAILABLE
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> BiometricState.HARDWARE_UNAVAILABLE
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> BiometricState.NONE_ENROLLED
            else -> BiometricState.NOT_AVAILABLE
        }
    }

    fun authenticate(
        activity: FragmentActivity,
        title: String = "Authenticate",
        subtitle: String = "Verify your identity",
    ): Channel<BiometricResult> {
        val resultChannel = Channel<BiometricResult>()

        val executor = ContextCompat.getMainExecutor(context)
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                super.onAuthenticationSucceeded(result)
                resultChannel.trySend(BiometricResult.SUCCESS)
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                super.onAuthenticationError(errorCode, errString)
                resultChannel.trySend(BiometricResult.ERROR(errString.toString()))
            }

            override fun onAuthenticationFailed() {
                super.onAuthenticationFailed()
                resultChannel.trySend(BiometricResult.FAILED)
            }
        }

        val prompt = BiometricPrompt(activity, executor, callback)
        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setNegativeButtonText("Cancel")
            .build()

        prompt.authenticate(promptInfo)
        return resultChannel
    }

    fun isAvailable(): Boolean {
        return _state.value == BiometricState.AVAILABLE
    }
}

sealed class BiometricResult {
    object SUCCESS : BiometricResult()
    object FAILED : BiometricResult()
    data class ERROR(val message: String) : BiometricResult()
}
