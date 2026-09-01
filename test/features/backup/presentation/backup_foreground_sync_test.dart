import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumovault/core/di/backup_providers.dart';
import 'package:lumovault/core/di/tdlib_providers.dart';
import 'package:lumovault/features/backup/presentation/widgets/backup_foreground_sync.dart';
import 'package:lumovault/features/settings/data/models/app_settings.dart';
import 'package:lumovault/features/settings/data/repositories/settings_repository.dart';
import 'package:lumovault/features/settings/presentation/providers/settings_providers.dart';

import '../../../helpers/fake_backup_engine.dart';
import '../../../helpers/stub_auth_service.dart';

/// Counts scan/backup calls instead of silently no-oping like the base fake,
/// so tests can assert that a sync actually ran (and that startBackup was
/// reached only once authenticated).
class _SpyBackupEngine extends FakeBackupEngineNotifier {
  int scanCalls = 0;
  int startCalls = 0;

  @override
  Future<void> scanAndEnqueue() async {
    scanCalls++;
  }

  @override
  Future<void> startBackup() async {
    startCalls++;
  }
}

/// In-memory stand-in for [SettingsRepository] whose futures resolve from
/// already-completed values — no platform channel involved.
///
/// The real repository's secure-storage channel never responds inside the
/// flutter test VM, so seeded settings were applied nondeterministically (and
/// an await on the read chain could hang the harness forever).
class _StubSettingsRepository implements SettingsRepository {
  _StubSettingsRepository(this._settings);

  AppSettings _settings;
  final _changeController = StreamController<AppSettings>.broadcast();

  @override
  Stream<AppSettings> get changes => _changeController.stream;

  @override
  Stream<Object> get errors => const Stream<Object>.empty();

  @override
  AppSettings get current => _settings;

  @override
  Future<AppSettings> getSettings() async => _settings;

  @override
  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    _changeController.add(settings);
  }

  @override
  Future<void> updateField(
    AppSettings Function(AppSettings current) updater,
  ) async {
    _settings = updater(_settings);
    _changeController.add(_settings);
  }

  @override
  Future<bool> isOnboardingCompleted() async => _settings.onboardingCompleted;

  @override
  Future<void> completeOnboarding() async {
    _settings = _settings.copyWith(onboardingCompleted: true);
    _changeController.add(_settings);
  }

  @override
  Future<void> setStorageChannelId(int channelId) async {
    _settings = _settings.copyWith(storageChannelId: channelId);
    _changeController.add(_settings);
  }

  @override
  Future<void> resetToDefaults() async {
    _settings = const AppSettings();
    _changeController.add(_settings);
  }

  @override
  void dispose() => _changeController.close();
}

Future<ProviderContainer> _pumpSync(
  WidgetTester tester, {
  required StubAuthService authService,
  required _SpyBackupEngine engine,
  AppSettings settings = const AppSettings(onboardingCompleted: true),
}) async {
  final container = ProviderContainer(
    overrides: [
      authServiceProvider.overrideWithValue(authService),
      backupEngineProvider.overrideWith((ref) => engine),
      settingsRepositoryProvider.overrideWithValue(
        _StubSettingsRepository(settings),
      ),
    ],
  );
  addTearDown(container.dispose);

  // Settle the settings notifier's async _init() BEFORE mounting: the
  // widget's post-frame sync reads appSettingsProvider synchronously, and
  // until the notifier lands it holds constructor defaults
  // (onboardingCompleted: false), so the sync would silently early-return.
  // Flush microtasks only — Future.delayed must NOT be used here: the
  // testWidgets body runs in a FakeAsync zone where fake timers never
  // advance without a pump, so awaiting one hangs the test forever.
  container.read(appSettingsProvider);
  await Future<void>.value();
  await Future<void>.value();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const BackupForegroundSync(child: SizedBox.shrink()),
    ),
  );
  // Let the post-frame initial sync run.
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'auth landing true drains the queue without another lifecycle event',
    (tester) async {
      // Regression: the post-frame sync ran before the TDLib session restore
      // finished, so items were enqueued but startBackup() was skipped
      // (isAuthenticated still false) — photos sat "in queue" forever until
      // the user manually resumed. The auth listener must drain the queue
      // the moment the session lands.
      final authService = StubAuthService(simulateDelay: Duration.zero);
      final engine = _SpyBackupEngine();

      await _pumpSync(tester, authService: authService, engine: engine);

      // Initial sync scanned and enqueued, but nothing drained: not signed
      // in yet.
      expect(engine.scanCalls, 1);
      expect(engine.startCalls, 0);

      // Simulate the session restore landing (verifyCode transitions the
      // stub to authenticated). runAsync is required: the stub's internal
      // `Future.delayed(Duration.zero)` is a fake timer that would never
      // fire inside the test body's FakeAsync zone — awaiting it directly
      // hangs the test forever. runAsync runs it in the real async zone.
      await tester.runAsync(() => authService.verifyCode('000000'));
      await tester.pumpAndSettle();

      expect(engine.startCalls, 1);
    },
  );

  testWidgets('unauthenticated syncs never drain the queue', (tester) async {
    final authService = StubAuthService(simulateDelay: Duration.zero);
    final engine = _SpyBackupEngine();

    await _pumpSync(tester, authService: authService, engine: engine);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(engine.scanCalls, 1);
    expect(engine.startCalls, 0);
  });

  testWidgets('onboarding incomplete: no sync at all', (tester) async {
    final authService = StubAuthService(simulateDelay: Duration.zero);
    final engine = _SpyBackupEngine();

    await _pumpSync(
      tester,
      authService: authService,
      engine: engine,
      settings: const AppSettings(onboardingCompleted: false),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(engine.scanCalls, 0);
    expect(engine.startCalls, 0);
  });
}
