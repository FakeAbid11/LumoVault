import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/error_handling/error_boundary.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/presentation/providers/onboarding_provider.dart';

/// Root widget for the LumoVault application.
///
/// Watches [onboardingCompletedProvider] to determine the initial route.
/// Wraps the entire app in an [ErrorBoundary] for crash resilience.
class LumoVaultApp extends ConsumerWidget {
  const LumoVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingCompleted = ref.watch(onboardingCompletedProvider);
    final router = createRouter(onboardingCompleted);

    return ErrorBoundary(
      child: MaterialApp.router(
        title: 'LumoVault',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        routerConfig: router,
      ),
    );
  }
}
