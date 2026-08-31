package com.lumovault.feature.settings.viewmodel

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lumovault.core.storage.EncryptedSettingsStore
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SettingsState(
    val userName: String = "",
    val telegramConnected: Boolean = false,
    val telegramPhoneNumber: String = "",
    val storageChannelId: Int? = null,
    val appVersion: String = "1.0.0",
    val autoBackupEnabled: Boolean = true,
    val darkMode: Boolean = false,
    val biometricEnabled: Boolean = false,
    val pinEnabled: Boolean = false,
    val analyticsEnabled: Boolean = true,
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val encryptedSettings: EncryptedSettingsStore,
) : ViewModel() {

    private val _uiState = MutableStateFlow(SettingsState())
    val uiState: StateFlow<SettingsState> = _uiState.asStateFlow()

    init {
        loadSettings()
    }

    fun loadSettings() {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    telegramConnected = encryptedSettings.getStorageChannelId() != null,
                    storageChannelId = encryptedSettings.getStorageChannelId(),
                )
            }
        }
    }

    fun setUserName(name: String) {
        viewModelScope.launch {
            encryptedSettings.setUserName(name)
            _uiState.update { it.copy(userName = name) }
        }
    }

    fun setDarkMode(enabled: Boolean) {
        _uiState.update { it.copy(darkMode = enabled) }
    }

    fun setBiometricEnabled(enabled: Boolean) {
        _uiState.update { it.copy(biometricEnabled = enabled) }
    }

    fun setPinEnabled(enabled: Boolean) {
        _uiState.update { it.copy(pinEnabled = enabled) }
    }

    fun setAnalyticsEnabled(enabled: Boolean) {
        _uiState.update { it.copy(analyticsEnabled = enabled) }
    }

    fun disconnectTelegram() {
        viewModelScope.launch {
            encryptedSettings.setStorageChannelId(null)
            _uiState.update {
                it.copy(
                    telegramConnected = false,
                    storageChannelId = null,
                )
            }
        }
    }

    fun clearAllData() {
        viewModelScope.launch {
            encryptedSettings.clearAll()
            _uiState.value = SettingsState()
        }
    }
}
