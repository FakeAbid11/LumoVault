package com.lumovault.feature.security.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lumovault.core.security.BiometricService
import com.lumovault.core.security.BiometricState
import com.lumovault.core.security.PinService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class AppLockState(
    val biometricState: BiometricState = BiometricState.NOT_AVAILABLE,
    val isPinSet: Boolean = false,
    val pinInput: String = "",
    val isVerifying: Boolean = false,
    val isLocked: Boolean = true,
    val error: String? = null,
    val attemptCount: Int = 0,
    val lockoutDuration: Long = 0L,
    val showPinSetup: Boolean = false,
)

@HiltViewModel
class AppLockViewModel @Inject constructor(
    private val biometricService: BiometricService,
    private val pinService: PinService,
) : ViewModel() {

    private val _uiState = MutableStateFlow(AppLockState())
    val uiState: StateFlow<AppLockState> = _uiState.asStateFlow()

    init {
        loadState()
    }

    fun loadState() {
        _uiState.update {
            it.copy(
                biometricState = biometricService.state.value,
                isPinSet = pinService.isPinSet(),
                attemptCount = pinService.getPinAttemptCount(),
                lockoutDuration = pinService.getLockoutDuration(),
            )
        }
    }

    fun onPinInputChanged(pin: String) {
        _uiState.update { it.copy(pinInput = pin, error = null) }
    }

    fun verifyPin() {
        val pin = _uiState.value.pinInput
        if (pin.length < 4) {
            _uiState.update { it.copy(error = "PIN must be at least 4 digits") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isVerifying = true) }

            val isValid = pinService.verifyPin(pin)
            if (isValid) {
                pinService.resetAttemptCount()
                _uiState.update {
                    it.copy(
                        isLocked = false,
                        isVerifying = false,
                        pinInput = "",
                        attemptCount = 0,
                    )
                }
            } else {
                pinService.incrementAttemptCount()
                val newCount = pinService.getPinAttemptCount()
                val lockout = pinService.getLockoutDuration()
                _uiState.update {
                    it.copy(
                        isVerifying = false,
                        pinInput = "",
                        error = "Incorrect PIN",
                        attemptCount = newCount,
                        lockoutDuration = lockout,
                    )
                }
            }
        }
    }

    fun setupPin(pin: String) {
        if (pin.length < 4) {
            _uiState.update { it.copy(error = "PIN must be at least 4 digits") }
            return
        }

        pinService.setPin(pin)
        _uiState.update {
            it.copy(
                isPinSet = true,
                showPinSetup = false,
                isLocked = false,
                pinInput = "",
            )
        }
    }

    fun showPinSetup() {
        _uiState.update { it.copy(showPinSetup = true, pinInput = "", error = null) }
    }

    fun hidePinSetup() {
        _uiState.update { it.copy(showPinSetup = false) }
    }

    fun biometricSuccess() {
        _uiState.update { it.copy(isLocked = false) }
    }

    fun biometricError(message: String) {
        _uiState.update { it.copy(error = message) }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun lock() {
        _uiState.update { it.copy(isLocked = true, pinInput = "") }
    }

    fun clearPin() {
        pinService.clearPin()
        _uiState.update { it.copy(isPinSet = false, isLocked = true) }
    }
}
