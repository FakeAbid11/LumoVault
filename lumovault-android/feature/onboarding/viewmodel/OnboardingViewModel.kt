package com.lumovault.feature.onboarding.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lumovault.core.auth.AuthState
import com.lumovault.core.auth.TelegramAuthRepository
import com.lumovault.core.permissions.PermissionService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class OnboardingUiState(
    val step: OnboardingStep = OnboardingStep.WELCOME,
    val permissionsGranted: Boolean = false,
    val backgroundPermissionsExplained: Boolean = false,
    val selectedFolders: Set<String> = emptySet(),
    val telegramConnected: Boolean = false,
    val phoneNumber: String = "",
    val verificationCode: String = "",
    val password: String = "",
    val authState: AuthState = AuthState.UNAUTHENTICATED,
    val isLoading: Boolean = false,
    val error: String? = null,
)

enum class OnboardingStep {
    WELCOME,
    PERMISSIONS,
    BACKGROUND_PERMISSIONS,
    FOLDERS,
    TELEGRAM,
}

@HiltViewModel
class OnboardingViewModel @Inject constructor(
    private val permissionService: PermissionService,
    private val authRepository: TelegramAuthRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(OnboardingUiState())
    val uiState: StateFlow<OnboardingUiState> = _uiState.asStateFlow()

    init {
        // Observe auth state changes
        viewModelScope.launch {
            authRepository.authState.collect { state ->
                _uiState.update { it.copy(authState = state) }
                if (state == AuthState.AUTHENTICATED) {
                    _uiState.update { it.copy(telegramConnected = true, isLoading = false) }
                }
            }
        }

        // Check existing permissions
        _uiState.update {
            it.copy(permissionsGranted = permissionService.hasCriticalPermissions())
        }
    }

    fun nextStep() {
        _uiState.update { state ->
            val nextOrdinal = (state.step.ordinal + 1).coerceAtMost(OnboardingStep.entries.last().ordinal)
            state.copy(step = OnboardingStep.entries[nextOrdinal])
        }
    }

    fun previousStep() {
        _uiState.update { state ->
            val prevOrdinal = (state.step.ordinal - 1).coerceAtLeast(0)
            state.copy(step = OnboardingStep.entries[prevOrdinal])
        }
    }

    fun goToStep(step: OnboardingStep) {
        _uiState.update { it.copy(step = step) }
    }

    fun onPermissionsGranted() {
        _uiState.update { it.copy(permissionsGranted = true) }
    }

    fun onBackgroundPermissionsExplained() {
        _uiState.update { it.copy(backgroundPermissionsExplained = true) }
    }

    fun onFoldersSelected(folders: Set<String>) {
        _uiState.update { it.copy(selectedFolders = folders) }
    }

    fun onPhoneNumberChanged(phone: String) {
        _uiState.update { it.copy(phoneNumber = phone, error = null) }
    }

    fun onVerificationCodeChanged(code: String) {
        _uiState.update { it.copy(verificationCode = code, error = null) }
    }

    fun onPasswordChanged(password: String) {
        _uiState.update { it.copy(password = password, error = null) }
    }

    fun sendPhoneNumber() {
        val phone = _uiState.value.phoneNumber
        if (phone.isBlank()) {
            _uiState.update { it.copy(error = "Please enter your phone number") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            val result = authRepository.sendPhoneNumber(phone)
            result.onFailure { e ->
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        error = e.message ?: "Failed to send phone number",
                    )
                }
            }
        }
    }

    fun submitCode() {
        val code = _uiState.value.verificationCode
        if (code.isBlank()) {
            _uiState.update { it.copy(error = "Please enter the verification code") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            val result = authRepository.submitCode(code)
            result.onFailure { e ->
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        error = e.message ?: "Invalid code",
                    )
                }
            }
        }
    }

    fun submitPassword() {
        val password = _uiState.value.password
        if (password.isBlank()) {
            _uiState.update { it.copy(error = "Please enter your password") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            val result = authRepository.submitPassword(password)
            result.onFailure { e ->
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        error = e.message ?: "Incorrect password",
                    )
                }
            }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
