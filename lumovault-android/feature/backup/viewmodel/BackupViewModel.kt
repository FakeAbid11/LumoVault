package com.lumovault.feature.backup.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.lumovault.feature.backup.engine.BackupEngine
import com.lumovault.feature.backup.engine.BackgroundBackupWorker
import com.lumovault.feature.backup.model.BackupSettings
import com.lumovault.feature.backup.model.BackupStats
import com.lumovault.feature.backup.model.BackupStatus
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class BackupUiState(
    val status: BackupStatus = BackupStatus.IDLE,
    val stats: BackupStats = BackupStats(),
    val settings: BackupSettings = BackupSettings(),
    val currentItem: String? = null,
    val error: String? = null,
    val isSettingsLoaded: Boolean = false,
)

@HiltViewModel
class BackupViewModel @Inject constructor(
    application: Application,
    private val backupEngine: BackupEngine,
) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow(BackupUiState())
    val uiState: StateFlow<BackupUiState> = _uiState.asStateFlow()

    init {
        // Observe engine state
        viewModelScope.launch {
            backupEngine.status.collect { status ->
                _uiState.update { it.copy(status = status) }
            }
        }

        viewModelScope.launch {
            backupEngine.stats.collect { stats ->
                _uiState.update { it.copy(stats = stats) }
            }
        }

        viewModelScope.launch {
            backupEngine.currentItem.collect { item ->
                _uiState.update { it.copy(currentItem = item) }
            }
        }
    }

    fun startBackup() {
        viewModelScope.launch {
            _uiState.update { it.copy(error = null) }
            backupEngine.startBackup(_uiState.value.settings)
        }
    }

    fun pauseBackup() {
        backupEngine.pauseBackup()
    }

    fun resumeBackup() {
        backupEngine.resumeBackup()
    }

    fun cancelBackup() {
        backupEngine.cancelBackup()
    }

    fun updateSettings(settings: BackupSettings) {
        _uiState.update { it.copy(settings = settings) }

        // Schedule or cancel background backup based on settings
        val context = getApplication<Application>()
        if (settings.isAutoBackupEnabled) {
            BackgroundBackupWorker.schedule(context)
        } else {
            BackgroundBackupWorker.cancel(context)
        }
    }

    fun toggleAutoBackup() {
        val current = _uiState.value.settings
        updateSettings(current.copy(isAutoBackupEnabled = !current.isAutoBackupEnabled))
    }

    fun toggleWifiOnly() {
        val current = _uiState.value.settings
        updateSettings(current.copy(wifiOnly = !current.wifiOnly))
    }

    fun toggleChargingOnly() {
        val current = _uiState.value.settings
        updateSettings(current.copy(chargingOnly = !current.chargingOnly))
    }

    fun toggleBackupPhotos() {
        val current = _uiState.value.settings
        updateSettings(current.copy(backupPhotos = !current.backupPhotos))
    }

    fun toggleBackupVideos() {
        val current = _uiState.value.settings
        updateSettings(current.copy(backupVideos = !current.backupVideos))
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
