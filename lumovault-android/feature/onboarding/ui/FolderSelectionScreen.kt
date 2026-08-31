package com.lumovault.feature.onboarding.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

data class DeviceFolder(
    val path: String,
    val name: String,
    val photoCount: Int = 0,
)

@Composable
fun FolderSelectionScreen(
    availableFolders: List<DeviceFolder>,
    onFoldersSelected: (Set<String>) -> Unit,
    onNext: () -> Unit,
) {
    var selectedFolders by remember { mutableStateOf(setOf<String>()) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
    ) {
        Text(
            text = "Select Folders",
            style = MaterialTheme.typography.headlineLarge,
            color = MaterialTheme.colorScheme.onSurface,
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Choose which folders to back up. You can change this later.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(modifier = Modifier.height(24.dp))

        // Select All / Deselect All
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Checkbox(
                checked = selectedFolders.size == availableFolders.size,
                onCheckedChange = { checked ->
                    selectedFolders = if (checked) {
                        availableFolders.map { it.path }.toSet()
                    } else {
                        emptySet()
                    }
                },
            )
            Text(
                text = if (selectedFolders.size == availableFolders.size) "Deselect All" else "Select All",
                style = MaterialTheme.typography.bodyMedium,
            )
        }

        LazyColumn(
            modifier = Modifier.weight(1f),
        ) {
            items(availableFolders) { folder ->
                FolderItem(
                    folder = folder,
                    isSelected = folder.path in selectedFolders,
                    onToggle = { checked ->
                        selectedFolders = if (checked) {
                            selectedFolders + folder.path
                        } else {
                            selectedFolders - folder.path
                        }
                    },
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        Button(
            onClick = {
                onFoldersSelected(selectedFolders)
                onNext()
            },
            modifier = Modifier.fillMaxWidth(),
            enabled = selectedFolders.isNotEmpty(),
        ) {
            Text("Continue")
        }
    }
}

@Composable
private fun FolderItem(
    folder: DeviceFolder,
    isSelected: Boolean,
    onToggle: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Checkbox(
            checked = isSelected,
            onCheckedChange = onToggle,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = folder.name,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "${folder.photoCount} photos",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
