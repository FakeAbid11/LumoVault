package com.lumovault.feature.people.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lumovault.feature.people.repository.FaceEntry
import com.lumovault.feature.people.repository.PeopleRepository
import com.lumovault.feature.people.repository.Person
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class PeopleUiState(
    val people: List<Person> = emptyList(),
    val selectedPerson: Person? = null,
    val personFaces: List<FaceEntry> = emptyList(),
    val isProcessing: Boolean = false,
    val error: String? = null,
    val showRenameDialog: Boolean = false,
    val showMergeDialog: Boolean = false,
)

@HiltViewModel
class PeopleViewModel @Inject constructor(
    private val peopleRepository: PeopleRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(PeopleUiState())
    val uiState: StateFlow<PeopleUiState> = _uiState.asStateFlow()

    init {
        loadPeople()
    }

    fun loadPeople() {
        viewModelScope.launch {
            val people = peopleRepository.getPeople()
            _uiState.update { it.copy(people = people) }
        }
    }

    fun selectPerson(personId: String) {
        viewModelScope.launch {
            val person = peopleRepository.getPerson(personId)
            val faces = peopleRepository.getPersonFaces(personId)
            _uiState.update {
                it.copy(
                    selectedPerson = person,
                    personFaces = faces,
                )
            }
        }
    }

    fun clearSelection() {
        _uiState.update {
            it.copy(
                selectedPerson = null,
                personFaces = emptyList(),
            )
        }
    }

    fun startProcessing() {
        viewModelScope.launch {
            _uiState.update { it.copy(isProcessing = true) }
            try {
                peopleRepository.processAllMedia()
                loadPeople()
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            } finally {
                _uiState.update { it.copy(isProcessing = false) }
            }
        }
    }

    fun renamePerson(personId: String, newName: String) {
        viewModelScope.launch {
            peopleRepository.renamePerson(personId, newName)
            loadPeople()
            _uiState.update { it.copy(showRenameDialog = false) }
        }
    }

    fun showRenameDialog() {
        _uiState.update { it.copy(showRenameDialog = true) }
    }

    fun hideRenameDialog() {
        _uiState.update { it.copy(showRenameDialog = false) }
    }

    fun mergePeople(targetId: String, sourceId: String) {
        viewModelScope.launch {
            peopleRepository.mergePeople(targetId, sourceId)
            loadPeople()
            _uiState.update { it.copy(showMergeDialog = false, selectedPerson = null) }
        }
    }

    fun showMergeDialog() {
        _uiState.update { it.copy(showMergeDialog = true) }
    }

    fun hideMergeDialog() {
        _uiState.update { it.copy(showMergeDialog = false) }
    }

    fun deletePerson(personId: String) {
        viewModelScope.launch {
            peopleRepository.deletePerson(personId)
            loadPeople()
            _uiState.update { it.copy(selectedPerson = null, personFaces = emptyList()) }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
