package com.lumovault.feature.metadata.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.lumovault.feature.metadata.repository.MetadataSyncResult
import com.lumovault.feature.metadata.viewmodel.MetadataViewModel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MetadataSyncScreen(
    onBack: () -> Unit,
    viewModel: MetadataViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Metadata Sync") },
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(
                imageVector = Icons.Default.CloudSync,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.primary,
            )

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "Metadata Sync",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "Keep your photo metadata in sync with your Telegram backup",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Stats card
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
                        Text("Unsynced Items", style = MaterialTheme.typography.bodyLarge)
                        Text(
                            uiState.unsyncedCount.toString(),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }

                    if (uiState.lastSyncTime > 0) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text("Last Sync", style = MaterialTheme.typography.bodyMedium)
                            Text(
                                SimpleDateFormat("MMM dd, HH:mm", Locale.getDefault())
                                    .format(Date(uiState.lastSyncTime)),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                    }
                }
            }

            // Sync result
            uiState.syncResult?.let { result ->
                Spacer(modifier = Modifier.height(16.dp))
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = androidx.compose.material3.CardDefaults.cardColors(
                        containerColor = when (result) {
                            is MetadataSyncResult.Success -> MaterialTheme.colorScheme.primaryContainer
                            is MetadataSyncResult.Error -> MaterialTheme.colorScheme.errorContainer
                            is MetadataSyncResult.NothingToSync -> MaterialTheme.colorScheme.surfaceVariant
                        }
                    ),
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = when (result) {
                                is MetadataSyncResult.Success -> Icons.Default.CheckCircle
                                is MetadataSyncResult.Error -> Icons.Default.Error
                                is MetadataSyncResult.NothingToSync -> Icons.Default.CheckCircle
                            },
                            contentDescription = null,
                            tint = when (result) {
                                is MetadataSyncResult.Success -> MaterialTheme.colorScheme.primary
                                is MetadataSyncResult.Error -> MaterialTheme.colorScheme.error
                                is MetadataSyncResult.NothingToSync -> MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        )
                        androidx.compose.foundation.layout.Spacer(modifier = Modifier.size(12.dp))
                        Text(
                            text = when (result) {
                                is MetadataSyncResult.Success -> "Synced ${result.syncedCount} items in ${result.totalPartitions} partitions"
                                is MetadataSyncResult.Error -> result.message
                                is MetadataSyncResult.NothingToSync -> "Nothing to sync"
                            },
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // Sync button
            Button(
                onClick = { viewModel.syncNow() },
                modifier = Modifier.fillMaxWidth(),
                enabled = !uiState.isSyncing && uiState.unsyncedCount > 0,
            ) {
                if (uiState.isSyncing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        color = MaterialTheme.colorScheme.onPrimary,
                        strokeWidth = 2.dp,
                    )
                } else {
                    Text("Sync Now")
                }
            }
        }
    }
}
