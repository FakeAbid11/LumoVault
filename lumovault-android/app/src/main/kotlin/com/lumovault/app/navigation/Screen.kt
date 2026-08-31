package com.lumovault.app.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Collections
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Timeline
import androidx.compose.ui.graphics.vector.ImageVector

sealed class Screen(val route: String) {
    // Onboarding
    data object Welcome : Screen("onboarding/welcome")
    data object Permissions : Screen("onboarding/permissions")
    data object BackgroundPermissions : Screen("onboarding/background-permissions")
    data object Folders : Screen("onboarding/folders")
    data object TelegramConnect : Screen("onboarding/telegram")

    // Main tabs
    data object Local : Screen("local")
    data object Timeline : Screen("timeline")
    data object Map : Screen("map")
    data object People : Screen("people")
    data object Settings : Screen("settings")

    // Sub-screens
    data object Restore : Screen("restore")
    data object RestoreProgress : Screen("restore/progress")
    data object Search : Screen("gallery/search")
    data object MediaViewer : Screen("gallery/media/{id}") {
        fun createRoute(id: String) = "gallery/media/$id"
    }
    data object TelegramMediaViewer : Screen("gallery/telegram-media/{id}") {
        fun createRoute(id: String) = "gallery/telegram-media/$id"
    }
    data object LocationPicker : Screen("gallery/pick-location")
    data object PersonDetail : Screen("people/{id}") {
        fun createRoute(id: String) = "people/$id"
    }
    data object Account : Screen("settings/account")
    data object BackupDashboard : Screen("settings/backup")
    data object BackupSettings : Screen("settings/backup/settings")
    data object StorageStats : Screen("settings/backup/stats")
    data object Hidden : Screen("settings/hidden")
    data object Archive : Screen("settings/archive")
    data object Trash : Screen("settings/trash")
    data object Duplicates : Screen("settings/duplicates")
    data object About : Screen("settings/about")
    data object GeneralSettings : Screen("settings/general")
    data object MediaSettings : Screen("settings/media")
    data object StorageSettings : Screen("settings/storage")
    data object StorageInsights : Screen("settings/storage-insights")
    data object AppearanceSettings : Screen("settings/appearance")
    data object PrivacySettings : Screen("settings/privacy")
    data object NotificationSettings : Screen("settings/notifications")
    data object DeveloperSettings : Screen("settings/developer")
    data object MetadataSync : Screen("settings/metadata-sync")
    data object AppLock : Screen("app-lock")
}

data class BottomNavItem(
    val screen: Screen,
    val label: String,
    val icon: ImageVector,
)

val bottomNavItems = listOf(
    BottomNavItem(Screen.Local, "Local", Icons.Default.Collections),
    BottomNavItem(Screen.Timeline, "Timeline", Icons.Default.Timeline),
    BottomNavItem(Screen.Map, "Map", Icons.Default.Map),
    BottomNavItem(Screen.People, "People", Icons.Default.People),
    BottomNavItem(Screen.Settings, "Settings", Icons.Default.Settings),
)
