import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/di/database_providers.dart';
import 'core/di/gallery_providers.dart';
import 'core/error_handling/global_error_handler.dart';
import 'core/error_handling/crash_reporter.dart';
import 'features/onboarding/presentation/providers/onboarding_provider.dart';
import 'features/settings/presentation/providers/settings_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize crash reporter (Sentry in prod, console in debug).
  final crashReporter = CrashReporterFactory.create(
    sentryDsn: const String.fromEnvironment('SENTRY_DSN', defaultValue: ''),
  );

  // Set up global error handling.
  GlobalErrorHandler.initialize(reporter: crashReporter);

  // Open the drift database once and share it across the app via a provider
  // override so every consumer uses the same connection.
  final database = AppDatabase();

  // Build the root container up front so we can hydrate the in-memory gallery
  // read model from persisted data before the first frame reads the timeline.
  final container = ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(database)],
  );
  await container.read(galleryRepositoryProvider).hydrate();

  // The router's initial route depends on onboardingCompletedProvider, which
  // is in-memory only and defaults to false on every cold start. Load the
  // persisted flag now so a returning user doesn't get sent through
  // onboarding again just because the app process restarted.
  final onboardingCompleted = await container
      .read(settingsRepositoryProvider)
      .isOnboardingCompleted();
  container.read(onboardingCompletedProvider.notifier).state =
      onboardingCompleted;

  // Run app inside error-catching zone, reusing the warmed-up container.
  GlobalErrorHandler.runAppWithZone(
    UncontrolledProviderScope(
      container: container,
      child: const LumoVaultApp(),
    ),
  );
}
