import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/notifications/notification_service.dart';
import 'package:lumovault/features/settings/data/models/app_settings.dart';

void main() {
  group('NotificationService', () {
    late NotificationService service;

    setUp(() {
      service = NotificationService();
    });

    test('isTypeEnabled respects backupProgressNotification', () {
      const settings = AppSettings(backupProgressNotification: false);
      expect(
        service.isTypeEnabled(settings, NotificationType.backupProgress),
        isFalse,
      );
    });

    test('isTypeEnabled respects backupCompletedNotification', () {
      const settings = AppSettings(backupCompletedNotification: false);
      expect(
        service.isTypeEnabled(settings, NotificationType.backupCompleted),
        isFalse,
      );
    });

    test('isTypeEnabled respects backupFailedNotification', () {
      const settings = AppSettings(backupFailedNotification: false);
      expect(
        service.isTypeEnabled(settings, NotificationType.backupFailed),
        isFalse,
      );
    });

    test('isTypeEnabled respects restoreCompletedNotification', () {
      const settings = AppSettings(restoreCompletedNotification: false);
      expect(
        service.isTypeEnabled(settings, NotificationType.restoreCompleted),
        isFalse,
      );
    });

    test('isTypeEnabled respects storageWarningNotification', () {
      const settings = AppSettings(storageWarningNotification: false);
      expect(
        service.isTypeEnabled(settings, NotificationType.storageWarning),
        isFalse,
      );
    });

    test('isTypeEnabled returns true when all are enabled', () {
      const settings = AppSettings();
      expect(
        service.isTypeEnabled(settings, NotificationType.backupProgress),
        isTrue,
      );
      expect(
        service.isTypeEnabled(settings, NotificationType.backupCompleted),
        isTrue,
      );
      expect(
        service.isTypeEnabled(settings, NotificationType.backupFailed),
        isTrue,
      );
      expect(
        service.isTypeEnabled(settings, NotificationType.restoreCompleted),
        isTrue,
      );
      expect(
        service.isTypeEnabled(settings, NotificationType.storageWarning),
        isTrue,
      );
    });

    test('methods do not throw before initialization', () async {
      // All methods should be no-ops when not initialized.
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
  });
}
