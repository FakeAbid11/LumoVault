import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../features/archive/presentation/screens/archive_screen.dart';
import '../../features/backup/presentation/screens/backup_dashboard_screen.dart';
import '../../features/backup/presentation/screens/storage_stats_screen.dart';
import '../../features/gallery/data/models/media_item.dart';
import '../../features/gallery/presentation/screens/local_screen.dart';
import '../../features/gallery/presentation/screens/map_screen.dart';
import '../../features/gallery/presentation/screens/timeline_screen.dart';
import '../../features/gallery/presentation/screens/search_screen.dart';
import '../../features/gallery/presentation/screens/media_viewer_screen.dart';
import '../../features/gallery/presentation/screens/telegram_media_viewer_screen.dart';
import '../../features/gallery/presentation/screens/location_picker_screen.dart';
import '../../features/hidden/presentation/screens/hidden_album_screen.dart';
import '../../features/onboarding/presentation/providers/onboarding_provider.dart';
import '../../features/onboarding/presentation/screens/welcome_screen.dart';
import '../../features/onboarding/presentation/screens/permissions_screen.dart';
import '../../features/onboarding/presentation/screens/folder_selection_screen.dart';
import '../../features/onboarding/presentation/screens/telegram_connect_screen.dart';
import '../../features/restore/presentation/screens/restore_screen.dart';
import '../../features/restore/presentation/screens/restore_progress_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/account_screen.dart';
import '../../features/settings/presentation/screens/about_screen.dart';
import '../../features/settings/presentation/screens/general_settings_screen.dart';
import '../../features/backup/presentation/screens/backup_settings_screen_v2.dart';
import '../../features/settings/presentation/screens/media_settings_screen.dart';
import '../../features/settings/presentation/screens/storage_settings_screen.dart';
import '../../features/settings/presentation/screens/appearance_settings_screen.dart';
import '../../features/settings/presentation/screens/privacy_settings_screen.dart';
import '../../features/settings/presentation/screens/notification_settings_screen.dart';
import '../../features/settings/presentation/screens/developer_settings_screen.dart';
import '../../features/trash/presentation/screens/trash_screen.dart';
import '../../shared/widgets/app_shell.dart';
import '../theme/app_motion.dart';

/// Page transition: slide from right.
///
/// Honors [AppMotion.enabled] — when animations are disabled in settings the
/// page appears instantly (no slide, zero duration).
CustomTransitionPage<void> _slideFromRight(Widget child, GoRouterState state) {
  if (!AppMotion.enabled) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          child,
    );
  }
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(1.0, 0.0);
      const end = Offset.zero;
      const curve = Curves.easeInOut;

      final tween = Tween(
        begin: begin,
        end: end,
      ).chain(CurveTween(curve: curve));

      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}

/// Riverpod provider for the application's [GoRouter].
///
/// The router is created exactly once for the lifetime of the app — the
/// root widget must never recreate it (e.g. on theme changes or scan
/// progress), otherwise all navigation state is lost.
///
/// Onboarding gating uses a [redirect] instead of an `initialLocation`
/// branch, driven by a [ValueNotifier] kept in sync with
/// [onboardingCompletedProvider] through `refreshListenable`. That way the
/// router itself never needs to be rebuilt when the user completes
/// onboarding.
final routerProvider = Provider<GoRouter>((ref) {
  final onboardingCompleted = ValueNotifier<bool>(
    ref.read(onboardingCompletedProvider),
  );
  ref.onDispose(onboardingCompleted.dispose);
  ref.listen(onboardingCompletedProvider, (previous, next) {
    onboardingCompleted.value = next;
  });

  return GoRouter(
    initialLocation: onboardingCompleted.value
        ? '/local'
        : '/onboarding/welcome',
    refreshListenable: onboardingCompleted,
    redirect: (context, state) {
      final isOnboardingRoute = state.matchedLocation.startsWith('/onboarding');
      if (!onboardingCompleted.value) {
        return isOnboardingRoute ? null : '/onboarding/welcome';
      }
      return isOnboardingRoute ? '/local' : null;
    },
    errorBuilder: (context, state) => const _RouterErrorScreen(),
    routes: [
      // ── Onboarding flow ─────────────────────────────────────
      GoRoute(
        path: '/onboarding/welcome',
        pageBuilder: (context, state) =>
            _slideFromRight(const WelcomeScreen(), state),
      ),
      GoRoute(
        path: '/onboarding/permissions',
        pageBuilder: (context, state) =>
            _slideFromRight(const PermissionsScreen(), state),
      ),
      GoRoute(
        path: '/onboarding/folders',
        pageBuilder: (context, state) =>
            _slideFromRight(const FolderSelectionScreen(), state),
      ),
      GoRoute(
        path: '/onboarding/telegram',
        pageBuilder: (context, state) =>
            _slideFromRight(const TelegramConnectScreen(), state),
      ),

      // ── Main app shell ──────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          // ── Tab 1: Local (all photos on this device) ─────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/local',
                pageBuilder: (context, state) => CustomTransitionPage<void>(
                  key: state.pageKey,
                  child: const LocalScreen(),
                  transitionDuration: Duration.zero,
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return child;
                      },
                ),
              ),
            ],
          ),

          // ── Tab 2: Timeline (backed-up photos only) ───────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/timeline',
                pageBuilder: (context, state) => CustomTransitionPage<void>(
                  key: state.pageKey,
                  child: const TimelineScreen(),
                  transitionDuration: Duration.zero,
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return child;
                      },
                ),
              ),
            ],
          ),

          // ── Tab 3: Map (photos plotted by GPS location) ──────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                pageBuilder: (context, state) => CustomTransitionPage<void>(
                  key: state.pageKey,
                  child: const MapScreen(),
                  transitionDuration: Duration.zero,
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return child;
                      },
                ),
              ),
            ],
          ),

          // ── Tab 4: Settings ──────────────────────────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) => CustomTransitionPage<void>(
                  key: state.pageKey,
                  child: const SettingsScreen(),
                  transitionDuration: Duration.zero,
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return child;
                      },
                ),
              ),
            ],
          ),
        ],
      ),

      // ── Restore flow ────────────────────────────────────────
      GoRoute(
        path: '/restore',
        pageBuilder: (context, state) =>
            _slideFromRight(const RestoreScreen(), state),
      ),
      GoRoute(
        path: '/restore/progress',
        pageBuilder: (context, state) =>
            _slideFromRight(const RestoreProgressScreen(), state),
      ),

      // ── Gallery sub-screens ──────────────────────────────────
      GoRoute(
        path: '/gallery/search',
        pageBuilder: (context, state) =>
            _slideFromRight(const SearchScreen(), state),
      ),
      GoRoute(
        path: '/gallery/media/:id',
        pageBuilder: (context, state) {
          final extra = state.extra;
          // The Local tab passes an extra `allowDeviceDelete` flag so its
          // viewer can offer "Delete from phone"; every other entry point uses
          // the plain 2-field record below and gets no delete action.
          if (extra
              is ({
                List<AssetEntity> assets,
                int initialIndex,
                bool allowDeviceDelete,
              })) {
            return _slideFromRight(
              MediaViewerScreen(
                assets: extra.assets,
                initialIndex: extra.initialIndex,
                allowDeviceDelete: extra.allowDeviceDelete,
              ),
              state,
            );
          }
          if (extra is ({List<AssetEntity> assets, int initialIndex})) {
            return _slideFromRight(
              MediaViewerScreen(
                assets: extra.assets,
                initialIndex: extra.initialIndex,
              ),
              state,
            );
          }
          // Reached directly (e.g. a deep link) without the asset list a
          // normal tap-from-timeline navigation provides — nothing to
          // preview or swipe through in that case.
          return _slideFromRight(const _MediaViewerUnavailable(), state);
        },
      ),

      GoRoute(
        path: '/gallery/telegram-media/:id',
        pageBuilder: (context, state) {
          final extra = state.extra;
          if (extra is ({List<MediaItem> items, int initialIndex})) {
            return _slideFromRight(
              TelegramMediaViewerScreen(
                items: extra.items,
                initialIndex: extra.initialIndex,
              ),
              state,
            );
          }
          // Reached directly without the item list a timeline tap provides.
          return _slideFromRight(const _MediaViewerUnavailable(), state);
        },
      ),

      // ── Location picker ────────────────────────────────────
      GoRoute(
        path: '/gallery/pick-location',
        pageBuilder: (context, state) {
          final extra = state.extra;
          double? lat;
          double? lng;
          if (extra is Map<String, dynamic>) {
            lat = extra['latitude'] as double?;
            lng = extra['longitude'] as double?;
          }
          return _slideFromRight(
            LocationPickerScreen(initialLatitude: lat, initialLongitude: lng),
            state,
          );
        },
      ),

      // ── Settings sub-screens ─────────────────────────────────
      GoRoute(
        path: '/settings/account',
        pageBuilder: (context, state) =>
            _slideFromRight(const AccountScreen(), state),
      ),
      GoRoute(
        path: '/settings/backup',
        pageBuilder: (context, state) =>
            _slideFromRight(const BackupDashboardScreen(), state),
      ),
      GoRoute(
        path: '/settings/backup/settings',
        pageBuilder: (context, state) =>
            _slideFromRight(const BackupSettingsScreenV2(), state),
      ),
      GoRoute(
        path: '/settings/backup/stats',
        pageBuilder: (context, state) =>
            _slideFromRight(const StorageStatsScreen(), state),
      ),
      GoRoute(
        path: '/settings/hidden',
        pageBuilder: (context, state) =>
            _slideFromRight(const HiddenAlbumScreen(), state),
      ),
      GoRoute(
        path: '/settings/archive',
        pageBuilder: (context, state) =>
            _slideFromRight(const ArchiveScreen(), state),
      ),
      GoRoute(
        path: '/settings/trash',
        pageBuilder: (context, state) =>
            _slideFromRight(const TrashScreen(), state),
      ),
      GoRoute(
        path: '/settings/about',
        pageBuilder: (context, state) =>
            _slideFromRight(const AboutScreen(), state),
      ),
      GoRoute(
        path: '/settings/general',
        pageBuilder: (context, state) =>
            _slideFromRight(const GeneralSettingsScreen(), state),
      ),
      GoRoute(
        path: '/settings/media',
        pageBuilder: (context, state) =>
            _slideFromRight(const MediaSettingsScreen(), state),
      ),
      GoRoute(
        path: '/settings/storage',
        pageBuilder: (context, state) =>
            _slideFromRight(const StorageSettingsScreen(), state),
      ),
      GoRoute(
        path: '/settings/appearance',
        pageBuilder: (context, state) =>
            _slideFromRight(const AppearanceSettingsScreen(), state),
      ),
      GoRoute(
        path: '/settings/privacy',
        pageBuilder: (context, state) =>
            _slideFromRight(const PrivacySettingsScreen(), state),
      ),
      GoRoute(
        path: '/settings/notifications',
        pageBuilder: (context, state) =>
            _slideFromRight(const NotificationSettingsScreen(), state),
      ),
      GoRoute(
        path: '/settings/developer',
        pageBuilder: (context, state) =>
            _slideFromRight(const DeveloperSettingsScreen(), state),
      ),
    ],
  );
});

/// Fallback shown for unrecoverable navigation errors, replacing
/// go_router's default red error screen.
class _RouterErrorScreen extends StatelessWidget {
  const _RouterErrorScreen();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Something went wrong',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Please restart LumoVault to continue.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown for `/gallery/media/:id` when reached without the asset list a
/// normal timeline tap provides (e.g. a raw deep link) — there's nothing to
/// display or swipe through without it.
class _MediaViewerUnavailable extends StatelessWidget {
  const _MediaViewerUnavailable();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text(
          'Open this photo from the timeline to preview it.',
          style: TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
