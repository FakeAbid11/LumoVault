import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/notifications/notification_backend.dart';
import 'package:lumovault/core/notifications/notification_service.dart';
import 'package:lumovault/features/settings/data/models/app_settings.dart';

void main() {
  group('NotificationService.initialize', () {
    test('creates a channel for every notification type', () async {
      final backend = _FakeBackend();
      final service = NotificationService(backend: backend);

      await service.initialize();

      expect(service.isInitialized, isTrue);
      expect(
        backend.createdChannels,
        hasLength(NotificationType.values.length),
      );
      expect(
        backend.createdChannels.toSet(),
        NotificationService.channels.values.map((s) => s.id).toSet(),
      );
    });

    test('is idempotent', () async {
      final backend = _FakeBackend();
      final service = NotificationService(backend: backend);

      await service.initialize();
      await service.initialize();

      expect(backend.initializeCalls, 1);
    });

    test('stays inert when the backend is unavailable', () async {
      final backend = _FakeBackend(available: false);
      final service = NotificationService(backend: backend);

      await service.initialize();

      expect(service.isInitialized, isFalse);
      expect(backend.createdChannels, isEmpty);
    });
  });

  group('NotificationService posting', () {
    late _FakeBackend backend;
    late NotificationService service;

    setUp(() async {
      backend = _FakeBackend();
      service = NotificationService(backend: backend);
      await service.initialize();
    });

    test('backup progress posts an ongoing progress notification', () async {
      await service.showBackupProgress(
        current: 3,
        total: 10,
        fileName: 'IMG_0042.jpg',
      );

      final request = backend.shown.single;
      expect(request.channelId, 'backup_progress');
      expect(request.id, NotificationService.backupProgressNotificationId);
      expect(request.ongoing, isTrue);
      expect(request.showProgress, isTrue);
      expect(request.progress, 3);
      expect(request.maxProgress, 10);
      expect(request.indeterminate, isFalse);
      expect(request.title, contains('30%'));
      expect(request.body, contains('IMG_0042.jpg'));
    });

    test('progress with an unknown total is indeterminate', () async {
      await service.showBackupProgress(
        current: 0,
        total: 0,
        fileName: 'IMG_0001.jpg',
      );

      expect(backend.shown.single.indeterminate, isTrue);
    });

    test(
      'progress re-posts under the same id so it updates in place',
      () async {
        await service.showBackupProgress(
          current: 1,
          total: 4,
          fileName: 'a.jpg',
        );
        await service.showBackupProgress(
          current: 2,
          total: 4,
          fileName: 'b.jpg',
        );

        expect(backend.shown.map((r) => r.id).toSet(), hasLength(1));
      },
    );

    test('completion cancels the progress notification first', () async {
      await service.showBackupCompleted(totalFiles: 12, totalBytes: 5 << 20);

      expect(
        backend.cancelled,
        contains(NotificationService.backupProgressNotificationId),
      );
      final request = backend.shown.single;
      expect(request.channelId, 'backup_completed');
      expect(request.ongoing, isFalse);
      expect(request.body, contains('12 items'));
      expect(request.body, contains('MB'));
    });

    test('completion singularises a one-item run', () async {
      await service.showBackupCompleted(totalFiles: 1, totalBytes: 512);

      expect(backend.shown.single.body, '1 item · 512 B');
    });

    test('failure posts at high priority with the reason', () async {
      await service.showBackupFailed(reason: 'Network lost', failedCount: 3);

      final request = backend.shown.single;
      expect(request.channelId, 'backup_failed');
      expect(request.priority, NotificationPriority.high);
      expect(request.title, contains('3 items'));
      expect(request.body, 'Network lost');
    });

    test('restore completion posts a summary', () async {
      await service.showRestoreCompleted(totalFiles: 7);

      final request = backend.shown.single;
      expect(request.channelId, 'restore_completed');
      expect(request.body, contains('7 items'));
    });

    test('storage warning posts at high priority', () async {
      await service.showStorageWarning(reason: 'Less than 1 GB free');

      final request = backend.shown.single;
      expect(request.channelId, 'storage_warning');
      expect(request.priority, NotificationPriority.high);
      expect(request.body, 'Less than 1 GB free');
    });

    test('cancelAll clears everything', () async {
      await service.cancelAll();
      expect(backend.cancelAllCalls, 1);
    });
  });

  group('NotificationService settings gating', () {
    test('a disabled category is not posted', () async {
      final backend = _FakeBackend();
      final service = NotificationService(backend: backend)
        ..updateSettings(const AppSettings(backupProgressNotification: false));
      await service.initialize();

      await service.showBackupProgress(current: 1, total: 2, fileName: 'a.jpg');

      expect(backend.shown, isEmpty);
    });

    test('other categories still post when one is disabled', () async {
      final backend = _FakeBackend();
      final service = NotificationService(backend: backend)
        ..updateSettings(const AppSettings(backupProgressNotification: false));
      await service.initialize();

      await service.showBackupCompleted(totalFiles: 1, totalBytes: 1);

      expect(backend.shown, hasLength(1));
    });

    test(
      'a disabled completion still clears the progress notification',
      () async {
        final backend = _FakeBackend();
        final service = NotificationService(backend: backend)
          ..updateSettings(
            const AppSettings(backupCompletedNotification: false),
          );
        await service.initialize();

        await service.showBackupCompleted(totalFiles: 1, totalBytes: 1);

        expect(backend.shown, isEmpty);
        expect(
          backend.cancelled,
          contains(NotificationService.backupProgressNotificationId),
        );
      },
    );

    test('updated settings take effect on the next post', () async {
      final backend = _FakeBackend();
      final service = NotificationService(backend: backend);
      await service.initialize();

      await service.showStorageWarning(reason: 'first');
      service.updateSettings(
        const AppSettings(storageWarningNotification: false),
      );
      await service.showStorageWarning(reason: 'second');

      expect(backend.shown, hasLength(1));
      expect(backend.shown.single.body, 'first');
    });
  });

  group('NotificationService before initialization', () {
    test('nothing is posted and nothing throws', () async {
      final backend = _FakeBackend();
      final service = NotificationService(backend: backend);

      await service.showBackupProgress(
        current: 1,
        total: 10,
        fileName: 'test.jpg',
      );
      await service.showBackupCompleted(totalFiles: 5, totalBytes: 1024);
      await service.showBackupFailed(reason: 'Error', failedCount: 1);
      await service.showRestoreCompleted(totalFiles: 5);
      await service.showStorageWarning(reason: 'Low space');
      await service.cancelAll();
      await service.cancel(1001);

      expect(backend.shown, isEmpty);
      expect(backend.cancelled, isEmpty);
      expect(backend.cancelAllCalls, 0);
      expect(await service.requestPermission(), isFalse);
    });
  });

  group('PluginNotificationBackend.guard', () {
    test('swallows a missing plugin instead of crashing the caller', () async {
      // MissingPluginException does not extend PlatformException, so it needs
      // its own clause — this is the case that reaches the backup engine.
      final result = await PluginNotificationBackend.guard<bool>(
        () async => throw MissingPluginException('no impl'),
        fallback: false,
      );

      expect(result, isFalse);
    });

    test('swallows platform errors', () async {
      final result = await PluginNotificationBackend.guard<bool>(
        () async => throw PlatformException(code: 'error'),
        fallback: false,
      );

      expect(result, isFalse);
    });

    test('passes a successful value through', () async {
      final result = await PluginNotificationBackend.guard<bool>(
        () async => true,
        fallback: false,
      );

      expect(result, isTrue);
    });

    test('does not swallow unrelated errors', () async {
      await expectLater(
        PluginNotificationBackend.guard<bool>(
          () async => throw StateError('bug'),
          fallback: false,
        ),
        throwsStateError,
      );
    });
  });

  group('NotificationService.isTypeEnabled', () {
    final service = NotificationService(backend: _FakeBackend());

    test('respects each per-category toggle', () {
      expect(
        service.isTypeEnabled(
          const AppSettings(backupProgressNotification: false),
          NotificationType.backupProgress,
        ),
        isFalse,
      );
      expect(
        service.isTypeEnabled(
          const AppSettings(backupCompletedNotification: false),
          NotificationType.backupCompleted,
        ),
        isFalse,
      );
      expect(
        service.isTypeEnabled(
          const AppSettings(backupFailedNotification: false),
          NotificationType.backupFailed,
        ),
        isFalse,
      );
      expect(
        service.isTypeEnabled(
          const AppSettings(restoreCompletedNotification: false),
          NotificationType.restoreCompleted,
        ),
        isFalse,
      );
      expect(
        service.isTypeEnabled(
          const AppSettings(storageWarningNotification: false),
          NotificationType.storageWarning,
        ),
        isFalse,
      );
    });

    test('returns true when all are enabled', () {
      const settings = AppSettings();
      for (final type in NotificationType.values) {
        expect(service.isTypeEnabled(settings, type), isTrue, reason: '$type');
      }
    });
  });

  group('NotificationType', () {
    test('has all expected types', () {
      expect(NotificationType.values.length, equals(5));
      expect(
        NotificationType.values.toSet(),
        equals({
          NotificationType.backupProgress,
          NotificationType.backupCompleted,
          NotificationType.backupFailed,
          NotificationType.restoreCompleted,
          NotificationType.storageWarning,
        }),
      );
    });

    test('every type has a channel with a unique notification id', () {
      final ids = <int>{};
      for (final type in NotificationType.values) {
        final spec = NotificationService.channels[type];
        expect(spec, isNotNull, reason: 'no channel for $type');
        expect(ids.add(spec!.notificationId), isTrue, reason: 'duplicate id');
      }
    });
  });
}

class _FakeBackend implements NotificationBackend {
  _FakeBackend({this.available = true});

  final bool available;
  final List<String> createdChannels = [];
  final List<NotificationRequest> shown = [];
  final List<int> cancelled = [];
  int initializeCalls = 0;
  int cancelAllCalls = 0;
  bool permissionGranted = true;

  @override
  Future<bool> initialize() async {
    initializeCalls++;
    return available;
  }

  @override
  Future<void> createChannel({
    required String id,
    required String name,
    required String description,
    required NotificationPriority priority,
  }) async {
    createdChannels.add(id);
  }

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> show(NotificationRequest request) async {
    shown.add(request);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
  }
}
