package com.lumovault.app.navigation

import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.lumovault.feature.onboarding.ui.OnboardingScreen
import com.lumovault.feature.gallery.ui.local.LocalScreen
import com.lumovault.feature.gallery.ui.timeline.TimelineScreen
import com.lumovault.feature.gallery.ui.search.SearchScreen
import com.lumovault.feature.gallery.ui.viewer.MediaViewerScreen
import com.lumovault.feature.gallery.ui.viewer.TelegramMediaViewerScreen
import com.lumovault.feature.backup.ui.BackupDashboardScreen
import com.lumovault.feature.backup.ui.BackupSettingsScreen
import com.lumovault.feature.restore.ui.RestoreScreen
import com.lumovault.feature.metadata.ui.MetadataSyncScreen
import com.lumovault.feature.people.ui.PeopleScreen
import com.lumovault.feature.people.ui.PersonDetailScreen
import com.lumovault.feature.map.ui.MapScreen
import com.lumovault.feature.settings.ui.SettingsScreen
import com.lumovault.feature.settings.ui.StorageStatsScreen
import com.lumovault.feature.settings.ui.MediaCollectionScreen
import com.lumovault.feature.settings.ui.MediaCollectionType
import com.lumovault.feature.settings.ui.AboutScreen
import com.lumovault.feature.settings.ui.PrivacySettingsScreen
import com.lumovault.feature.settings.ui.GeneralSettingsScreen
import com.lumovault.feature.settings.ui.MediaSettingsScreen
import com.lumovault.feature.settings.ui.StorageSettingsScreen
import com.lumovault.feature.settings.ui.AppearanceSettingsScreen
import com.lumovault.feature.settings.ui.NotificationSettingsScreen
import com.lumovault.feature.settings.ui.DeveloperSettingsScreen
import com.lumovault.feature.settings.ui.AccountScreen
import com.lumovault.feature.settings.ui.StorageInsightsScreen
import com.lumovault.feature.security.ui.AppLockScreen
import com.lumovault.feature.security.ui.PinSetupScreen

@Composable
fun LumoVaultNavGraph() {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    val showBottomBar = currentRoute in bottomNavItems.map { it.screen.route }

    Scaffold(
        bottomBar = {
            if (showBottomBar) {
                AppShell(
                    currentRoute = currentRoute,
                    onNavigate = { screen ->
                        navController.navigate(screen.route) {
                            popUpTo(navController.graph.findStartDestination().id) {
                                saveState = true
                            }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                )
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Timeline.route,
            modifier = Modifier.padding(innerPadding),
            enterTransition = {
                slideIntoContainer(
                    AnimatedContentTransitionScope.SlideDirection.Left,
                    animationSpec = tween(300)
                )
            },
            exitTransition = {
                slideOutOfContainer(
                    AnimatedContentTransitionScope.SlideDirection.Left,
                    animationSpec = tween(300)
                )
            },
            popEnterTransition = {
                slideIntoContainer(
                    AnimatedContentTransitionScope.SlideDirection.Right,
                    animationSpec = tween(300)
                )
            },
            popExitTransition = {
                slideOutOfContainer(
                    AnimatedContentTransitionScope.SlideDirection.Right,
                    animationSpec = tween(300)
                )
            },
        ) {
            // Main tabs
            composable(Screen.Local.route) {
                LocalScreen(
                    onMediaClick = { id ->
                        navController.navigate(Screen.MediaViewer.createRoute(id))
                    },
                    onMediaLongClick = { /* Handled by ViewModel */ },
                )
            }
            composable(Screen.Timeline.route) {
                TimelineScreen(
                    onMediaClick = { id ->
                        navController.navigate(Screen.MediaViewer.createRoute(id))
                    },
                )
            }
            composable(Screen.Map.route) {
                MapScreen(
                    onMediaClick = { id ->
                        navController.navigate(Screen.MediaViewer.createRoute(id))
                    },
                )
            }
            composable(Screen.People.route) {
                PeopleScreen(
                    onPersonClick = { id ->
                        navController.navigate(Screen.PersonDetail.createRoute(id))
                    },
                )
            }
            composable(Screen.Settings.route) {
                SettingsScreen(
                    onNavigate = { route ->
                        navController.navigate(route)
                    },
                )
            }

            // Onboarding
            composable(Screen.Welcome.route) {
                OnboardingScreen(
                    onComplete = {
                        navController.navigate(Screen.Timeline.route) {
                            popUpTo(Screen.Welcome.route) { inclusive = true }
                        }
                    },
                )
            }
            composable(Screen.Permissions.route) {
                // Handled within OnboardingScreen
            }
            composable(Screen.BackgroundPermissions.route) {
                // Handled within OnboardingScreen
            }
            composable(Screen.Folders.route) {
                // Handled within OnboardingScreen
            }
            composable(Screen.TelegramConnect.route) {
                // Handled within OnboardingScreen
            }

            // Sub-screens
            composable(Screen.Restore.route) {
                RestoreScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.RestoreProgress.route) {
                RestoreScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.Search.route) {
                SearchScreen(
                    onMediaClick = { id ->
                        navController.navigate(Screen.MediaViewer.createRoute(id))
                    },
                )
            }
            composable(
                route = Screen.MediaViewer.route,
                arguments = listOf(navArgument("id") { type = androidx.navigation.NavType.StringType }),
            ) { backStackEntry ->
                val mediaId = backStackEntry.arguments?.getString("id") ?: return@composable
                MediaViewerScreen(
                    mediaId = mediaId,
                    onBack = { navController.popBackStack() },
                )
            }
            composable(
                route = Screen.TelegramMediaViewer.route,
                arguments = listOf(navArgument("id") { type = androidx.navigation.NavType.StringType }),
            ) { backStackEntry ->
                val mediaId = backStackEntry.arguments?.getString("id") ?: return@composable
                TelegramMediaViewerScreen(
                    mediaId = mediaId,
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.LocationPicker.route) {
                com.lumovault.feature.map.ui.LocationPickerScreen(
                    onBack = { navController.popBackStack() },
                    onLocationPicked = { lat, lon -> navController.popBackStack() },
                )
            }
            composable(
                route = Screen.PersonDetail.route,
                arguments = listOf(navArgument("id") { type = androidx.navigation.NavType.StringType }),
            ) { backStackEntry ->
                val personId = backStackEntry.arguments?.getString("id") ?: return@composable
                PersonDetailScreen(
                    personId = personId,
                    onBack = { navController.popBackStack() },
                    onMediaClick = { mediaId ->
                        navController.navigate(Screen.MediaViewer.createRoute(mediaId))
                    },
                )
            }

            // Settings sub-screens
            composable(Screen.Account.route) {
                AccountScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.BackupDashboard.route) {
                BackupDashboardScreen(
                    onNavigateToSettings = {
                        navController.navigate(Screen.BackupSettings.route)
                    },
                    onNavigateToStats = {
                        navController.navigate(Screen.StorageStats.route)
                    },
                )
            }
            composable(Screen.BackupSettings.route) {
                BackupSettingsScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.StorageStats.route) {
                StorageStatsScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.Hidden.route) {
                MediaCollectionScreen(
                    title = "Hidden Photos",
                    type = MediaCollectionType.HIDDEN,
                    onBack = { navController.popBackStack() },
                    onMediaClick = { id ->
                        navController.navigate(Screen.MediaViewer.createRoute(id))
                    },
                )
            }
            composable(Screen.Archive.route) {
                MediaCollectionScreen(
                    title = "Archive",
                    type = MediaCollectionType.ARCHIVE,
                    onBack = { navController.popBackStack() },
                    onMediaClick = { id ->
                        navController.navigate(Screen.MediaViewer.createRoute(id))
                    },
                )
            }
            composable(Screen.Trash.route) {
                MediaCollectionScreen(
                    title = "Trash",
                    type = MediaCollectionType.TRASH,
                    onBack = { navController.popBackStack() },
                    onMediaClick = { id ->
                        navController.navigate(Screen.MediaViewer.createRoute(id))
                    },
                )
            }
            composable(Screen.Duplicates.route) {
                MediaCollectionScreen(
                    title = "Duplicates",
                    type = MediaCollectionType.DUPLICATES,
                    onBack = { navController.popBackStack() },
                    onMediaClick = { id ->
                        navController.navigate(Screen.MediaViewer.createRoute(id))
                    },
                )
            }
            composable(Screen.About.route) {
                AboutScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.GeneralSettings.route) {
                GeneralSettingsScreen(onBack = { navController.popBackStack() })
            }
            composable(Screen.MediaSettings.route) {
                MediaSettingsScreen(onBack = { navController.popBackStack() })
            }
            composable(Screen.StorageSettings.route) {
                StorageSettingsScreen(onBack = { navController.popBackStack() })
            }
            composable(Screen.StorageInsights.route) {
                StorageInsightsScreen(onBack = { navController.popBackStack() })
            }
            composable(Screen.MetadataSync.route) {
                MetadataSyncScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.AppearanceSettings.route) {
                AppearanceSettingsScreen(onBack = { navController.popBackStack() })
            }
            composable(Screen.PrivacySettings.route) {
                PrivacySettingsScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.NotificationSettings.route) {
                NotificationSettingsScreen(onBack = { navController.popBackStack() })
            }
            composable(Screen.DeveloperSettings.route) {
                DeveloperSettingsScreen(onBack = { navController.popBackStack() })
            }
            composable(Screen.AppLock.route) {
                AppLockScreen(
                    onUnlocked = {
                        navController.navigate(Screen.Settings.route) {
                            popUpTo(Screen.AppLock.route) { inclusive = true }
                        }
                    },
                )
            }
        }
    }
}
