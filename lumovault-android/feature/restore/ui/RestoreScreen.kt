package com.lumovault.feature.restore.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.lumovault.feature.restore.model.RestorePhase
import com.lumovault.feature.restore.viewmodel.RestoreViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RestoreScreen(
    onBack: () -> Unit,
    viewModel: RestoreViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val progress = uiState.progress

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Restore") },
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Status icon
            Icon(
                imageVector = when (progress.phase) {
                    RestorePhase.COMPLETED -> Icons.Default.CheckCircle
                    RestorePhase.FAILED -> Icons.Default.Error
                    else -> Icons.Default.CloudDownload
                },
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = when (progress.phase) {
                    RestorePhase.COMPLETED -> MaterialTheme.colorScheme.primary
                    RestorePhase.FAILED -> MaterialTheme.colorScheme.error
                    else -> MaterialTheme.colorScheme.onSurfaceVariant
                },
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Phase text
            Text(
                text = when (progress.phase) {
                    RestorePhase.DETECTING_CHANNEL -> "Finding backup channel..."
                    RestorePhase.DOWNLOADING_MANIFEST -> "Scanning backup..."
                    RestorePhase.DOWNLOADING_METADATA -> "Loading metadata..."
                    RestorePhase.REBUILDING_DATABASE -> "Restoring to database..."
                    RestorePhase.DOWNLOADING_THUMBNAILS -> "Processing thumbnails..."
                    RestorePhase.COMPLETED -> "Restore Complete!"
                    RestorePhase.FAILED -> "Restore Failed"
                },
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.height(8.dp))

            if (progress.currentPhaseDescription.isNotEmpty()) {
                Text(
                    text = progress.currentPhaseDescription,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Progress card
            if (progress.phase != RestorePhase.DETECTING_CHANNEL && progress.phase != RestorePhase.FAILED) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text("Progress", style = MaterialTheme.typography.titleSmall)
                            Text(
                                "${progress.progressPercentage}%",
                                color = MaterialTheme.colorScheme.primary,
                                style = MaterialTheme.typography.titleSmall,
                            )
                        }

                        Spacer(modifier = Modifier.height(8.dp))

                        LinearProgressIndicator(
                            progress = { progress.progress },
                            modifier = Modifier.fillMaxWidth(),
                        )

                        Spacer(modifier = Modifier.height(12.dp))

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(
                                    progress.totalItems.toString(),
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                )
                                Text("Total", style = MaterialTheme.typography.bodySmall)
                            }
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(
                                    progress.completedItems.toString(),
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                                Text("Restored", style = MaterialTheme.typography.bodySmall)
                            }
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(
                                    progress.skippedItems.toString(),
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                )
                                Text("Skipped", style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
            }

            // Error
            if (progress.phase == RestorePhase.FAILED && progress.error != null) {
                Spacer(modifier = Modifier.height(16.dp))
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                    ),
                ) {
                    Text(
                        text = progress.error!!,
                        modifier = Modifier.padding(16.dp),
                        color = MaterialTheme.colorScheme.onErrorContainer,
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // Controls
            when (progress.phase) {
                RestorePhase.DETECTING_CHANNEL, RestorePhase.FAILED -> {
                    Button(
                        onClick = { viewModel.startRestore() },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(
                            imageVector = Icons.Default.PlayArrow,
                            contentDescription = null,
                            modifier = Modifier.padding(end = 8.dp),
                        )
                        Text("Start Restore")
                    }
                }
                RestorePhase.COMPLETED -> {
                    Button(
                        onClick = onBack,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Done")
                    }
                }
                else -> {
                    if (progress.isPaused) {
                        Button(
                            onClick = { viewModel.resumeRestore() },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text("Resume")
                        }
                    } else {
                        OutlinedButton(
                            onClick = { viewModel.cancelRestore() },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text("Cancel")
                        }
                    }
                }
            }
        }
    }
}
