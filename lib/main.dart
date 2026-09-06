import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/di/backup_providers.dart';
import 'core/di/database_providers.dart';
import 'core/di/gallery_providers.dart';
import 'core/di/production_providers.dart';
import 'core/error_handling/global_error_handler.dart';
import 'core/error_handling/crash_reporter.dart';
import 'core/logging/app_logger.dart';
import 'core/storage/thumbnail_cache.dart';
import 'features/metadata/presentation/providers/metadata_providers.dart';
import 'features/onboarding/presentation/providers/onboarding_provider.dart';
import 'features/settings/presentation/providers/settings_providers.dart';
import 'package:material_symbols_icons/symbols.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Gate LumoVault's own verbose logs behind the Debug Mode toggle. Installed
  // before any app work so early bootstrap logs honor the setting too; the
  // persisted flag is applied in _bootstrap once settings load.
  AppLogger.install();

  // Initialize crash reporter (Sentry in prod, console in debug).
  final crashReporter = CrashReporterFactory.create(
    sentryDsn: const String.fromEnvironment('SENTRY_DSN', defaultValue: ''),
  );

  // Set up global error handling.
  GlobalErrorHandler.initialize(reporter: crashReporter);

  // Warm up the reporting SDK before any app work begins so that early
  // failures during bootstrap are captured rather than lost.
  await crashReporter.initialize();

  try {
    final container = await _bootstrap();

    // Run app inside error-catching zone, reusing the warmed-up container.
    GlobalErrorHandler.runAppWithZone(
      UncontrolledProviderScope(
        container: container,
        child: const LumoVaultApp(),
      ),
    );
  } catch (error, stackTrace) {
    // Bootstrap failed before the first frame: report it and show a minimal
    // error screen instead of hanging on a frozen splash.
    await crashReporter.recordError(
      error,
      stackTrace,
      reason: 'App bootstrap failed',
      fatal: true,
    );
    await crashReporter.flush();
    runApp(const BootstrapErrorApp());
  }
}

/// Performs all one-time app initialization and returns the root provider
/// container, which [main] reuses for the whole app lifetime.
///
/// Throws on failure so [main] can report the error and render an error UI.
Future<ProviderContainer> _bootstrap() async {
  // Open the drift database once and share it across the app via a provider
  // override so every consumer uses the same connection.
  final database = AppDatabase();

  // Build the root container up front so we can hydrate the in-memory gallery
  // read model from persisted data before the first frame reads the timeline.
  final container = ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(database)],
  );
  await container.read(galleryRepositoryProvider).hydrate();

  // Constructing MetadataIntegration installs the metadata change callback on
  // GalleryRepository. Riverpod providers are lazy, so this read is what
  // actually wires gallery mutations through to the metadata layer — it has to
  // happen before any scan or gallery write.
  container.read(metadataIntegrationProvider);

  // Installs the permanent-delete → channel-revoke callback on
  // GalleryRepository. Providers are lazy, so this read is what wires
  // delete-forever through to deleteMessages(revoke: true) on the storage
  // channel; without it a permanent delete only clears local records.
  container.read(galleryRemoteDeletionProvider);

  // Restores the persisted sync log and hydrates the in-memory metadata store
  // from the partitions on disk.
  await container.read(metadataRepositoryProvider).initialize();

  // Attaches the metadata sync coordinator's 'sync_pending' listener so
  // gallery mutations reach Telegram (manifest + partition files) without any
  // UI involvement. Providers are lazy, so this read is what makes the sync
  // layer live at all.
  container.read(metadataSyncCoordinatorProvider);

  // Activates the live channel listener so a change another device pushes is
  // reconciled without a manual scan (debounced pull). Providers are lazy —
  // this read is what attaches the TDLib update subscription.
  container.read(channelUpdateListenerProvider);

  // Pull side of two-way sync: reconcile any changes another device pushed to
  // the channel while this one was away. Fire-and-forget and self-guarding —
  // if TDLib isn't connected/authenticated yet it resolves to a no-op, and the
  // live channel listener (plus the next app launch) will pull again later.
  unawaited(container.read(metadataSyncCoordinatorProvider).pullNow());

  // The router's initial route depends on onboardingCompletedProvider, which
  // is in-memory only and defaults to false on every cold start. Load the
  // persisted flag now so a returning user doesn't get sent through
  // onboarding again just because the app process restarted.
  final onboardingCompleted = await container
      .read(settingsRepositoryProvider)
      .isOnboardingCompleted();
  container.read(onboardingCompletedProvider.notifier).state =
      onboardingCompleted;

  // Apply the persisted Debug Mode flag to the log gate before the first
  // frame, so early logs honor it without waiting for the settings notifier's
  // async init. The notifier keeps it in sync thereafter.
  AppLogger.verboseEnabled =
      (await container.read(settingsRepositoryProvider).getSettings())
          .debugMode;

  // Persistence failures in the settings repository are never fatal (settings
  // still apply in memory), but they used to be completely silent. Log them
  // from boot so a lost write — e.g. a storageChannelId that would otherwise
  // cause a duplicate backup channel on the next launch — is at least
  // observable.
  container
      .read(settingsRepositoryProvider)
      .errors
      .listen((e) => debugPrint('[Settings] Persistence error: $e'));

  // Register the notification channels before anything tries to post progress.
  await container.read(notificationServiceProvider).initialize();

  // Create the thumbnail cache directory before any widget can write to it.
  // ThumbnailCache.put() no-ops to memory-only when uninitialized, but the
  // disk backing should exist from the very first frame.
  await ThumbnailCache.instance.initialize();

  // Schedules the WorkManager tasks that drive periodic backup. Providers are
  // lazy, so this read is what makes background backup exist at all.
  container.read(backgroundBackupSyncProvider);

  return container;
}

/// Minimal fallback UI shown when app initialization fails before the first
/// frame, so the user sees that something went wrong instead of a frozen
/// splash screen.
class BootstrapErrorApp extends StatelessWidget {
  const BootstrapErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LumoVault',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Symbols.error, size: 48),
                const SizedBox(height: 16),
                Text(
                  'LumoVault could not start.',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please restart the app. If this keeps happening, '
                  'contact support.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
