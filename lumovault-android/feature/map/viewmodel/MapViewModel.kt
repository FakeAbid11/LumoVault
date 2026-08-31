package com.lumovault.feature.map.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lumovault.feature.gallery.repository.GalleryRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class MapPhoto(
    val localId: String,
    val filePath: String,
    val latitude: Double,
    val longitude: Double,
    val createdAt: Long,
    val mimeType: String,
)

data class MapCluster(
    val center: Pair<Double, Double>,
    val photos: List<MapPhoto>,
    val count: Int,
)

data class MapUiState(
    val photosWithLocation: List<MapPhoto> = emptyList(),
    val clusters: List<MapCluster> = emptyList(),
    val isLoading: Boolean = false,
    val selectedPhoto: MapPhoto? = null,
    val error: String? = null,
)

@HiltViewModel
class MapViewModel @Inject constructor(
    private val galleryRepository: GalleryRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(MapUiState())
    val uiState: StateFlow<MapUiState> = _uiState.asStateFlow()

    init {
        loadPhotosWithLocation()
    }

    fun loadPhotosWithLocation() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            try {
                val items = galleryRepository.getItemsWithLocation()
                val photos = items.map { item ->
                    MapPhoto(
                        localId = item.localId,
                        filePath = item.filePath,
                        latitude = item.latitude ?: 0.0,
                        longitude = item.longitude ?: 0.0,
                        createdAt = item.createdAt,
                        mimeType = item.mimeType,
                    )
                }.filter { it.latitude != 0.0 && it.longitude != 0.0 }

                val clusters = clusterPhotos(photos)

                _uiState.update {
                    it.copy(
                        photosWithLocation = photos,
                        clusters = clusters,
                        isLoading = false,
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        error = e.message,
                    )
                }
            }
        }
    }

    fun selectPhoto(photo: MapPhoto) {
        _uiState.update { it.copy(selectedPhoto = photo) }
    }

    fun clearSelection() {
        _uiState.update { it.copy(selectedPhoto = null) }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    private fun clusterPhotos(photos: List<MapPhoto>): List<MapCluster> {
        if (photos.isEmpty()) return emptyList()

        val clusters = mutableListOf<MapCluster>()
        val used = mutableSetOf<Int>()

        for (i in photos.indices) {
            if (i in used) continue

            val clusterPhotos = mutableListOf(photos[i])
            used.add(i)

            for (j in i + 1 until photos.size) {
                if (j in used) continue

                val distance = calculateDistance(
                    photos[i].latitude, photos[i].longitude,
                    photos[j].latitude, photos[j].longitude,
                )

                if (distance < 500) { // 500 meters
                    clusterPhotos.add(photos[j])
                    used.add(j)
                }
            }

            if (clusterPhotos.size > 1) {
                val avgLat = clusterPhotos.map { it.latitude }.average()
                val avgLon = clusterPhotos.map { it.longitude }.average()
                clusters.add(
                    MapCluster(
                        center = Pair(avgLat, avgLon),
                        photos = clusterPhotos,
                        count = clusterPhotos.size,
                    )
                )
            }
        }

        return clusters
    }

    private fun calculateDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double,
    ): Double {
        val r = 6371000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2)
        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return r * c
    }
}
