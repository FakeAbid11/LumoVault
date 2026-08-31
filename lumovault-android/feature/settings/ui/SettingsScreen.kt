package com.lumovault.feature.settings.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowForwardIos
import androidx.compose.material.icons.filled.Backup
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.hilt.navigation.compose.hiltViewModel
import com.lumovault.feature.settings.viewmodel.SettingsViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onNavigate: (String) -> Unit,
    viewModel: SettingsViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(title = { Text("Settings") })
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
        ) {
            // Account section
            SettingsSection(title = "Account") {
                SettingsItem(
                    icon = Icons.Default.Person,
                    title = "Account",
                    subtitle = uiState.userName.ifEmpty { "Not signed in" },
                    onClick = { onNavigate("settings/account") },
                )
            }

            HorizontalDivider()

            // Backup section
            SettingsSection(title = "Backup & Restore") {
                SettingsItem(
                    icon = Icons.Default.Backup,
                    title = "Backup Dashboard",
                    subtitle = if (uiState.telegramConnected) "Connected" else "Not connected",
                    onClick = { onNavigate("settings/backup") },
                )
                SettingsItem(
                    icon = Icons.Default.Storage,
                    title = "Storage Stats",
                    subtitle = "View storage usage",
                    onClick = { onNavigate("settings/backup/stats") },
                )
                SettingsItem(
                    icon = Icons.Default.Storage,
                    title = "Metadata Sync",
                    subtitle = "Sync photo metadata",
                    onClick = { onNavigate("settings/metadata-sync") },
                )
            }

            HorizontalDivider()

            // Security section
            SettingsSection(title = "Security") {
                SettingsItem(
                    icon = Icons.Default.Lock,
                    title = "App Lock",
                    subtitle = if (uiState.biometricEnabled) "Biometric enabled"
                    else if (uiState.pinEnabled) "PIN enabled"
                    else "Disabled",
                    onClick = { onNavigate("app-lock") },
                )
                SettingsItem(
                    icon = Icons.Default.Security,
                    title = "Privacy Settings",
                    subtitle = "Manage privacy",
                    onClick = { onNavigate("settings/privacy") },
                )
            }

            HorizontalDivider()

            // Media section
            SettingsSection(title = "Media") {
                SettingsItem(
                    icon = Icons.Default.Storage,
                    title = "Hidden Photos",
                    subtitle = "Manage hidden media",
                    onClick = { onNavigate("settings/hidden") },
                )
                SettingsItem(
                    icon = Icons.Default.Storage,
                    title = "Archive",
                    subtitle = "Manage archived media",
                    onClick = { onNavigate("settings/archive") },
                )
                SettingsItem(
                    icon = Icons.Default.Storage,
                    title = "Trash",
                    subtitle = "Recently deleted",
                    onClick = { onNavigate("settings/trash") },
                )
                SettingsItem(
                    icon = Icons.Default.Storage,
                    title = "Duplicates",
                    subtitle = "Find duplicate photos",
                    onClick = { onNavigate("settings/duplicates") },
                )
            }

            HorizontalDivider()

            // Appearance section
            SettingsSection(title = "Appearance") {
                SettingsItem(
                    icon = Icons.Default.Palette,
                    title = "Appearance",
                    subtitle = "Theme, colors, layout",
                    onClick = { onNavigate("settings/appearance") },
                )
            }

            HorizontalDivider()

            // About section
            SettingsSection(title = "About") {
                SettingsItem(
                    icon = Icons.Default.ArrowForwardIos,
                    title = "About LumoVault",
                    subtitle = "Version ${uiState.appVersion}",
                    onClick = { onNavigate("settings/about") },
                )
            }
        }
    }
}

@Composable
private fun SettingsSection(
    title: String,
    content: @Composable () -> Unit,
) {
    Column {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        )
        content()
    }
}

@Composable
private fun SettingsItem(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(subtitle) },
        leadingContent = {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        trailingContent = {
            Icon(
                imageVector = Icons.Default.ArrowForwardIos,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        modifier = Modifier.clickable(onClick = onClick),
    )
}
