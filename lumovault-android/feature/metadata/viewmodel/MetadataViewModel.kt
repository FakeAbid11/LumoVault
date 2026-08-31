package com.lumovault.feature.metadata.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lumovault.feature.metadata.repository.MetadataSyncResult
import com.lumovault.feature.metadata.repository.SyncCoordinator
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class MetadataUiState(
    val isSyncing: Boolean = false,
    val unsyncedCount: Int = 0,
    val lastSyncTime: Long = 0,
    val syncResult: MetadataSyncResult? = null,
    val error: String? = null,
)

@HiltViewModel
class MetadataViewModel @Inject constructor(
    private val syncCoordinator: SyncCoordinator,
) : ViewModel() {

    private val _uiState = MutableStateFlow(MetadataUiState())
    val uiState: StateFlow<MetadataUiState> = _uiState.asStateFlow()

    init {
        refreshStatus()
    }

    fun refreshStatus() {
        viewModelScope.launch {
            val unsynced = syncCoordinator.getUnsyncedCount()
            _uiState.update {
                it.copy(unsyncedCount = unsynced)
            }
        }
    }

    fun syncNow() {
        viewModelScope.launch {
            _uiState.update { it.copy(isSyncing = true, error = null) }
            val result = syncCoordinator.syncNow()
            _uiState.update {
                it.copy(
                    isSyncing = false,
                    syncResult = result,
                    lastSyncTime = System.currentTimeMillis(),
                    error = if (result is MetadataSyncResult.Error) result.message else null,
                )
            }
        }
    }

    fun clearResult() {
        _uiState.update { it.copy(syncResult = null) }
    }
}
