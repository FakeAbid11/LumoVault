import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/channel_scan_providers.dart';
import 'core/error_handling/error_boundary.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_motion.dart';
import 'core/theme/app_theme.dart';
import 'features/app_lock/presentation/widgets/app_lock_gate.dart';
import 'features/backup/presentation/widgets/backup_foreground_sync.dart';
import 'features/people/presentation/widgets/face_scan_background_handoff.dart';
import 'features/settings/presentation/providers/settings_providers.dart';

/// Root widget for the LumoVault application.
///
/// Watches [routerProvider] — the router is created once and reused across
/// rebuilds (e.g. theme changes), so navigation state is never lost.
/// Listens to [autoChannelScanProvider] to trigger a channel scan on auth.
/// Wraps the entire app in an [ErrorBoundary] for crash resilience.
class LumoVaultApp extends ConsumerWidget {
  const LumoVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(settingsThemeModeProvider);
    final useDynamicColor = ref.watch(settingsDynamicColorProvider);
    final animationsEnabled = ref.watch(settingsAnimationsProvider);

    // Keep the router/theme's global motion flag in sync with the setting.
    // The router builds transition pages lazily and reads this static rather
    // than a provider (see [AppMotion]).
    AppMotion.enabled = animationsEnabled;

    // Activate the auto channel scan — this provider watches auth state
    // and triggers a scan of the existing backup channel when the user
    // becomes authenticated. `listen` (rather than `watch`) is used so
    // scan progress updates do not rebuild the root widget.
    ref.listen(autoChannelScanProvider, (previous, next) {});

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // Only apply wallpaper-derived schemes when the user opted in AND the
        // platform actually provides them (Android 12+); otherwise fall back
        // to the branded seed themes.
        final light = useDynamicColor ? lightDynamic?.harmonized() : null;
        final dark = useDynamicColor ? darkDynamic?.harmonized() : null;

        return ErrorBoundary(
          child: MaterialApp.router(
            title: 'LumoVault',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(
              dynamicScheme: light,
              animationsEnabled: animationsEnabled,
            ),
            darkTheme: AppTheme.dark(
              dynamicScheme: dark,
              animationsEnabled: animationsEnabled,
            ),
            themeMode: themeMode,
            routerConfig: router,
            builder: (context, child) => BackupForegroundSync(
              child: FaceScanBackgroundHandoff(
                child: AppLockGate(child: child ?? const SizedBox.shrink()),
              ),
            ),
          ),
        );
      },
    );
  }
}
