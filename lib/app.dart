import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/channel_scan_providers.dart';
import 'core/error_handling/error_boundary.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/app_lock/presentation/widgets/app_lock_gate.dart';
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

    // Activate the auto channel scan — this provider watches auth state
    // and triggers a scan of the existing backup channel when the user
    // becomes authenticated. `listen` (rather than `watch`) is used so
    // scan progress updates do not rebuild the root widget.
    ref.listen(autoChannelScanProvider, (previous, next) {});

    return ErrorBoundary(
      child: MaterialApp.router(
        title: 'LumoVault',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: router,
        builder: (context, child) =>
            AppLockGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
