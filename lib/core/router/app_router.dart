import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../features/archive/presentation/screens/archive_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/phone_input_screen.dart';
import '../../features/auth/presentation/screens/code_verification_screen.dart';
import '../../features/auth/presentation/screens/two_factor_screen.dart';
import '../../features/backup/presentation/screens/backup_dashboard_screen.dart';
import '../../features/backup/presentation/screens/storage_stats_screen.dart';
import '../../features/favorites/presentation/screens/favorites_screen.dart';
import '../../features/gallery/presentation/screens/albums_screen.dart';
import '../../features/gallery/presentation/screens/album_detail_screen.dart';
import '../../features/gallery/presentation/screens/timeline_screen.dart';
import '../../features/gallery/presentation/screens/search_screen.dart';
import '../../features/gallery/presentation/screens/media_viewer_screen.dart';
import '../../features/hidden/presentation/screens/hidden_album_screen.dart';
import '../../features/onboarding/presentation/providers/onboarding_provider.dart';
import '../../features/onboarding/presentation/screens/welcome_screen.dart';
import '../../features/onboarding/presentation/screens/permissions_screen.dart';
import '../../features/onboarding/presentation/screens/folder_selection_screen.dart';
import '../../features/onboarding/presentation/screens/initial_scan_screen.dart';
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

/// Page transition: slide from right.
CustomTransitionPage<void> _slideFromRight(Widget child, GoRouterState state) {
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

/// Application router configuration.
///
/// [initialLocation] is determined by [onboardingCompletedProvider].
/// On first launch it points to `/onboarding/welcome`, otherwise to `/timeline`.
GoRouter createRouter(bool onboardingCompleted) {
  return GoRouter(
    initialLocation: onboardingCompleted ? '/timeline' : '/onboarding/welcome',
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
        path: '/onboarding/scan',
        pageBuilder: (context, state) =>
            _slideFromRight(const InitialScanScreen(), state),
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
          // ── Tab 1: Timeline ──────────────────────────────────
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

          // ── Tab 2: Albums ────────────────────────────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/albums',
                pageBuilder: (context, state) => CustomTransitionPage<void>(
                  key: state.pageKey,
                  child: const AlbumsScreen(),
                  transitionDuration: Duration.zero,
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return child;
                      },
                ),
              ),
            ],
          ),

          // ── Tab 3: Favorites ─────────────────────────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/favorites',
                pageBuilder: (context, state) => CustomTransitionPage<void>(
                  key: state.pageKey,
                  child: const FavoritesScreen(),
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

      // ── Auth flow ────────────────────────────────────────────
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) =>
            _slideFromRight(const LoginScreen(), state),
      ),
      GoRoute(
        path: '/login/phone',
        pageBuilder: (context, state) =>
            _slideFromRight(const PhoneInputScreen(), state),
      ),
      GoRoute(
        path: '/login/code',
        pageBuilder: (context, state) =>
            _slideFromRight(const CodeVerificationScreen(), state),
      ),
      GoRoute(
        path: '/login/two-factor',
        pageBuilder: (context, state) =>
            _slideFromRight(const TwoFactorScreen(), state),
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

      // ── Albums sub-screens ───────────────────────────────────
      GoRoute(
        path: '/albums/detail/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return _slideFromRight(AlbumDetailScreen(albumId: id), state);
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
}

/// Legacy getter for backward compatibility.
final goRouter = createRouter(false);

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
