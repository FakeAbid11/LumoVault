package com.lumovault.feature.map.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocationPickerScreen(
    initialLatitude: Double? = null,
    initialLongitude: Double? = null,
    onBack: () -> Unit,
    onLocationPicked: (Double, Double) -> Unit,
) {
    var selectedLat by remember { mutableStateOf(initialLatitude ?: 0.0) }
    var selectedLon by remember { mutableStateOf(initialLongitude ?: 0.0) }

    Column(modifier = Modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text("Pick Location") },
            navigationIcon = {
                IconButton(onClick = onBack) {
                    Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                }
            },
            actions = {
                IconButton(
                    onClick = {
                        if (selectedLat != 0.0 && selectedLon != 0.0) {
                            onLocationPicked(selectedLat, selectedLon)
                        }
                    },
                ) {
                    Icon(Icons.Default.Check, contentDescription = "Confirm")
                }
            },
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
        ) {
            Text(
                text = "Tap on the map to select a location",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Map placeholder
            Text(
                text = "Map would be displayed here with Mapbox",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "Selected: ${String.format("%.4f", selectedLat)}, ${String.format("%.4f", selectedLon)}",
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = MaterialTheme.typography.titleMedium.fontWeight,
            )
        }
    }
}
