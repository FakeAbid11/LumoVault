import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/di/backup_providers.dart';
import 'package:lumovault/core/storage/isolate_run_lock.dart';
import 'package:lumovault/features/backup/data/models/backup_settings.dart';
import 'package:lumovault/features/backup/engine/background_backup_service.dart';

void main() {
  group('BackgroundBackupSync', () {
    test('registers every task when background backup is on', () async {
      final scheduler = _FakeScheduler();
      final sync = BackgroundBackupSync(scheduler);

      await sync.apply(enabled: true, settings: const BackupSettings());

      expect(scheduler.registeredAll, hasLength(1));
      expect(scheduler.cancelAllCalls, 0);
    });

    test('cancels everything when background backup is off', () async {
      final scheduler = _FakeScheduler();
      final sync = BackgroundBackupSync(scheduler);

      await sync.apply(enabled: false, settings: const BackupSettings());

      expect(scheduler.cancelAllCalls, 1);
      expect(scheduler.registeredAll, isEmpty);
    });

    test('an unchanged settings snapshot does not re-register', () async {
      final scheduler = _FakeScheduler();
      final sync = BackgroundBackupSync(scheduler);

      await sync.apply(enabled: true, settings: const BackupSettings());
      await sync.apply(enabled: true, settings: const BackupSettings());

      expect(scheduler.registeredAll, hasLength(1));
    });

    test(
      'a settings change unrelated to scheduling does not re-register',
      () async {
        final scheduler = _FakeScheduler();
        final sync = BackgroundBackupSync(scheduler);

        await sync.apply(enabled: true, settings: const BackupSettings());
        await sync.apply(
          enabled: true,
          settings: const BackupSettings(uploadDelayMs: 500),
        );

        expect(scheduler.registeredAll, hasLength(1));
      },
    );

    test('a constraint change re-registers', () async {
      final scheduler = _FakeScheduler();
      final sync = BackgroundBackupSync(scheduler);

      await sync.apply(enabled: true, settings: const BackupSettings());
      await sync.apply(
        enabled: true,
        settings: const BackupSettings(wifiOnly: false),
      );

      expect(scheduler.registeredAll, hasLength(2));
      expect(scheduler.registeredAll.last.wifiOnly, isFalse);
    });

    test('toggling background backup off then on re-registers', () async {
      final scheduler = _FakeScheduler();
      final sync = BackgroundBackupSync(scheduler);

      await sync.apply(enabled: true, settings: const BackupSettings());
      await sync.apply(enabled: false, settings: const BackupSettings());
      await sync.apply(enabled: true, settings: const BackupSettings());

      expect(scheduler.registeredAll, hasLength(2));
      expect(scheduler.cancelAllCalls, 1);
    });

    test('a scheduler failure does not escape', () async {
      // No WorkManager on desktop/test hosts — the app must still boot.
      final sync = BackgroundBackupSync(_ThrowingScheduler());

      await expectLater(
        sync.apply(enabled: true, settings: const BackupSettings()),
        completes,
      );
    });
  });

  group('BackgroundTaskRunner.run', () {
    test(
      'an unknown task reports success rather than retrying forever',
      () async {
        final runner = BackgroundTaskRunner(
          containerFactory: ProviderContainer.new,
          runLock: _NeverAcquiringLock(),
        );

        expect(await runner.run('com.lumovault.not_a_task'), isTrue);
      },
    );

    test(
      'a backup task backs off when another isolate holds the lock',
      () async {
        // The container factory throws, so if the lock were acquired the run
        // would fail — proving the lock short-circuits before any work starts.
        final runner = BackgroundTaskRunner(
          containerFactory: () => throw StateError('should not build'),
          runLock: _NeverAcquiringLock(),
        );

        expect(await runner.run(kUploadWorkerTask), isTrue);
        expect(await runner.run(kBackupSchedulerTask), isTrue);
      },
    );

    test('a throwing task is reported as a retryable failure', () async {
      final runner = BackgroundTaskRunner(
        containerFactory: () => throw StateError('boom'),
        runLock: _AlwaysAcquiringLock(),
      );

      expect(await runner.run(kMediaScannerTask), isFalse);
    });

    test('the backup lock is released even when the task throws', () async {
      final lock = _AlwaysAcquiringLock();
      final runner = BackgroundTaskRunner(
        containerFactory: () => throw StateError('boom'),
        runLock: lock,
      );

      await runner.run(kUploadWorkerTask);

      expect(lock.releases, 1);
    });
  });

  group('task names', () {
    test('are unique and namespaced', () {
      const names = [
        kMediaScannerTask,
        kUploadWorkerTask,
        kBackupSchedulerTask,
        kMetadataRepairTask,
        kThumbnailRebuildTask,
      ];

      expect(names.toSet(), hasLength(names.length));
      for (final name in names) {
        expect(name, startsWith('com.lumovault.'));
      }
    });
  });
}

class _FakeScheduler implements BackupTaskScheduler {
  final List<BackupSettings> registeredAll = [];
  int cancelAllCalls = 0;
  final List<String> cancelledTasks = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> registerAllTasks({
    required BackupSettings settings,
    bool promoteScannerToForeground = false,
  }) async {
    registeredAll.add(settings);
  }

  @override
  Future<void> registerMediaScanner({bool promoteToForeground = false}) async {}

  @override
  Future<void> registerUploadWorker({
    bool wifiOnly = true,
    bool chargingOnly = false,
  }) async {}

  @override
  Future<void> registerBackupScheduler({
    required BackupSettings settings,
  }) async {}

  @override
  Future<void> registerMetadataRepair() async {}

  @override
  Future<void> registerThumbnailRebuild() async {}

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
  }

  @override
  Future<void> cancelTask(String taskName) async {
    cancelledTasks.add(taskName);
  }
}

class _ThrowingScheduler extends _FakeScheduler {
  @override
  Future<void> registerAllTasks({
    required BackupSettings settings,
    bool promoteScannerToForeground = false,
  }) async {
    throw StateError('no WorkManager here');
  }
}

/// Stands in for a lock another isolate already owns.
class _NeverAcquiringLock extends IsolateRunLock {
  _NeverAcquiringLock() : super(name: 'test', directory: Directory.systemTemp);

  @override
  Future<bool> tryAcquire({DateTime? now}) async => false;

  @override
  Future<void> release() async {}

  @override
  Future<void> heartbeat({DateTime? now}) async {}
}

class _AlwaysAcquiringLock extends IsolateRunLock {
  _AlwaysAcquiringLock() : super(name: 'test', directory: Directory.systemTemp);

  int releases = 0;

  @override
  Future<bool> tryAcquire({DateTime? now}) async => true;

  @override
  Future<void> release() async {
    releases++;
  }

  @override
  Future<void> heartbeat({DateTime? now}) async {}
}
