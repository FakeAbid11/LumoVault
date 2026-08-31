package com.lumovault.feature.gallery.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lumovault.core.database.entities.MediaItemEntity
import com.lumovault.feature.gallery.repository.GalleryRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class GalleryUiState(
    val isLoading: Boolean = true,
    val isScanning: Boolean = false,
    val scanProgress: Pair<Int, Int>? = null,
    val timeline: List<MediaItemEntity> = emptyList(),
    val favorites: List<MediaItemEntity> = emptyList(),
    val trashed: List<MediaItemEntity> = emptyList(),
    val hidden: List<MediaItemEntity> = emptyList(),
    val archived: List<MediaItemEntity> = emptyList(),
    val searchResults: List<MediaItemEntity> = emptyList(),
    val selectedItems: Set<String> = emptySet(),
    val isSelectionMode: Boolean = false,
    val error: String? = null,
)

@HiltViewModel
class GalleryViewModel @Inject constructor(
    private val galleryRepository: GalleryRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(GalleryUiState())
    val uiState: StateFlow<GalleryUiState> = _uiState.asStateFlow()

    val timeline: StateFlow<List<MediaItemEntity>> = galleryRepository.getTimeline()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val favorites: StateFlow<List<MediaItemEntity>> = galleryRepository.getFavorites()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val trashed: StateFlow<List<MediaItemEntity>> = galleryRepository.getTrashed()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    init {
        loadTimeline()
    }

    fun loadTimeline() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            try {
                // Timeline is collected via StateFlow above
                _uiState.update { it.copy(isLoading = false) }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(isLoading = false, error = e.message ?: "Failed to load timeline")
                }
            }
        }
    }

    fun scanDevice(folders: Set<String>? = null) {
        viewModelScope.launch {
            _uiState.update { it.copy(isScanning = true, error = null) }
            try {
                galleryRepository.scanDevice(folders)
                _uiState.update { it.copy(isScanning = false) }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(isScanning = false, error = e.message ?: "Scan failed")
                }
            }
        }
    }

    fun search(query: String) {
        viewModelScope.launch {
            if (query.isBlank()) {
                _uiState.update { it.copy(searchResults = emptyList()) }
                return@launch
            }
            galleryRepository.search(query).collect { results ->
                _uiState.update { it.copy(searchResults = results) }
            }
        }
    }

    fun toggleFavorite(localId: String) {
        viewModelScope.launch {
            galleryRepository.toggleFavorite(localId)
        }
    }

    fun moveToTrash(localId: String) {
        viewModelScope.launch {
            galleryRepository.moveToTrash(localId)
        }
    }

    fun restoreFromTrash(localId: String) {
        viewModelScope.launch {
            galleryRepository.restoreFromTrash(localId)
        }
    }

    fun permanentDelete(localId: String) {
        viewModelScope.launch {
            galleryRepository.permanentDelete(localId)
        }
    }

    fun toggleHidden(localId: String) {
        viewModelScope.launch {
            galleryRepository.toggleHidden(localId)
        }
    }

    fun toggleArchive(localId: String) {
        viewModelScope.launch {
            galleryRepository.toggleArchive(localId)
        }
    }

    fun toggleSelectionMode() {
        _uiState.update {
            it.copy(
                isSelectionMode = !it.isSelectionMode,
                selectedItems = emptySet(),
            )
        }
    }

    fun toggleItemSelection(localId: String) {
        _uiState.update { state ->
            val newSelected = if (localId in state.selectedItems) {
                state.selectedItems - localId
            } else {
                state.selectedItems + localId
            }
            state.copy(
                selectedItems = newSelected,
                isSelectionMode = newSelected.isNotEmpty(),
            )
        }
    }

    fun selectAll() {
        viewModelScope.launch {
            val allIds = timeline.value.map { it.localId }.toSet()
            _uiState.update { it.copy(selectedItems = allIds) }
        }
    }

    fun deselectAll() {
        _uiState.update { it.copy(selectedItems = emptySet(), isSelectionMode = false) }
    }

    fun batchMoveToTrash() {
        viewModelScope.launch {
            val ids = _uiState.value.selectedItems.toList()
            ids.forEach { galleryRepository.moveToTrash(it) }
            _uiState.update { it.copy(selectedItems = emptySet(), isSelectionMode = false) }
        }
    }

    fun batchToggleFavorite() {
        viewModelScope.launch {
            val ids = _uiState.value.selectedItems.toList()
            ids.forEach { galleryRepository.toggleFavorite(it) }
            _uiState.update { it.copy(selectedItems = emptySet(), isSelectionMode = false) }
        }
    }

    fun batchToggleHidden() {
        viewModelScope.launch {
            val ids = _uiState.value.selectedItems.toList()
            ids.forEach { galleryRepository.toggleHidden(it) }
            _uiState.update { it.copy(selectedItems = emptySet(), isSelectionMode = false) }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
