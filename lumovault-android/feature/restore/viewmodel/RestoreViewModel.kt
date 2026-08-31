package com.lumovault.feature.restore.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lumovault.feature.restore.engine.RestoreEngine
import com.lumovault.feature.restore.model.RestorePhase
import com.lumovault.feature.restore.model.RestoreProgress
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class RestoreUiState(
    val progress: RestoreProgress = RestoreProgress(),
    val error: String? = null,
)

@HiltViewModel
class RestoreViewModel @Inject constructor(
    private val restoreEngine: RestoreEngine,
) : ViewModel() {

    private val _uiState = MutableStateFlow(RestoreUiState())
    val uiState: StateFlow<RestoreUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            restoreEngine.progress.collect { progress ->
                _uiState.update { it.copy(progress = progress) }
            }
        }
    }

    fun startRestore() {
        restoreEngine.startRestore()
    }

    fun pauseRestore() {
        restoreEngine.pauseRestore()
    }

    fun resumeRestore() {
        restoreEngine.resumeRestore()
    }

    fun cancelRestore() {
        restoreEngine.cancelRestore()
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
