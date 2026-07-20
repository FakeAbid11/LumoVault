import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/backup/data/models/backup_settings.dart';
import 'package:lumovault/features/backup/engine/backup_scheduler.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';

void main() {
  group('BackupScheduler', () {
    group('evaluate', () {
      test('allows backup when all conditions met', () {
        const settings = BackupSettings(
          isAutoBackupEnabled: true,
          wifiOnly: true,
          chargingOnly: false,
        );

        const environment = BackupEnvironment(
          isWifiConnected: true,
          isCharging: false,
          batteryLevel: 50,
          isAutoBackupEnabled: true,
        );

        final result = BackupScheduler.evaluate(
          settings: settings,
          environment: environment,
        );

        expect(result.canProceed, isTrue);
      });

      test('blocks backup when auto backup disabled', () {
        const settings = BackupSettings(isAutoBackupEnabled: false);
        const environment = BackupEnvironment(isAutoBackupEnabled: true);

        final result = BackupScheduler.evaluate(
          settings: settings,
          environment: environment,
        );

        expect(result.canProceed, isFalse);
        expect(result.reason, contains('Auto backup is disabled'));
      });

      test('blocks backup when wifi required but not connected', () {
        const settings = BackupSettings(wifiOnly: true);
        const environment = BackupEnvironment(
          isWifiConnected: false,
          isAutoBackupEnabled: true,
        );

        final result = BackupScheduler.evaluate(
          settings: settings,
          environment: environment,
        );

        expect(result.canProceed, isFalse);
        expect(result.reason, contains('Wi-Fi'));
      });

      test('allows backup when wifi not required', () {
        const settings = BackupSettings(wifiOnly: false);
        const environment = BackupEnvironment(
          isWifiConnected: false,
          isAutoBackupEnabled: true,
        );

        final result = BackupScheduler.evaluate(
          settings: settings,
          environment: environment,
        );

        expect(result.canProceed, isTrue);
      });

      test('blocks backup when charging required but not charging', () {
        const settings = BackupSettings(chargingOnly: true);
        const environment = BackupEnvironment(
          isCharging: false,
          isAutoBackupEnabled: true,
        );

        final result = BackupScheduler.evaluate(
          settings: settings,
          environment: environment,
        );

        expect(result.canProceed, isFalse);
        expect(result.reason, contains('charging'));
      });

      test('blocks backup when battery too low', () {
        const settings = BackupSettings();
        const environment = BackupEnvironment(
          batteryLevel: 15,
          isAutoBackupEnabled: true,
        );

        final result = BackupScheduler.evaluate(
          settings: settings,
          environment: environment,
        );

        expect(result.canProceed, isFalse);
        expect(result.reason, contains('Battery'));
      });

      test('blocks backup when environment auto backup disabled', () {
        const settings = BackupSettings(isAutoBackupEnabled: true);
        const environment = BackupEnvironment(isAutoBackupEnabled: false);

        final result = BackupScheduler.evaluate(
          settings: settings,
          environment: environment,
        );

        expect(result.canProceed, isFalse);
        expect(result.reason, contains('toggle'));
      });
    });

    group('evaluateMediaItem', () {
      test('includes normal media item', () {
        const settings = BackupSettings();
        final item = MediaItem(
          localId: '1',
          fileHash: 'hash1',
          filePath: '/path/test.jpg',
          fileName: 'test.jpg',
          mimeType: 'image/jpeg',
          fileSize: 1024,
          width: 1920,
          height: 1080,
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          scannedAt: DateTime.now(),
        );

        final result = BackupScheduler.evaluateMediaItem(
          item: item,
          settings: settings,
        );

        expect(result.included, isTrue);
      });

      test('excludes user-excluded files', () {
        const settings = BackupSettings();
        final item = MediaItem(
          localId: '1',
          fileHash: 'hash1',
          filePath: '/path/test.jpg',
          fileName: 'test.jpg',
          mimeType: 'image/jpeg',
          fileSize: 1024,
          width: 1920,
          height: 1080,
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          scannedAt: DateTime.now(),
          isExcluded: true,
        );

        final result = BackupScheduler.evaluateMediaItem(
          item: item,
          settings: settings,
        );

        expect(result.included, isFalse);
      });

      test('excludes trashed files', () {
        const settings = BackupSettings();
        final item = MediaItem(
          localId: '1',
          fileHash: 'hash1',
          filePath: '/path/test.jpg',
          fileName: 'test.jpg',
          mimeType: 'image/jpeg',
          fileSize: 1024,
          width: 1920,
          height: 1080,
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          scannedAt: DateTime.now(),
          isTrashed: true,
        );

        final result = BackupScheduler.evaluateMediaItem(
          item: item,
          settings: settings,
        );

        expect(result.included, isFalse);
      });

      test('excludes already uploaded files', () {
        const settings = BackupSettings();
        final item = MediaItem(
          localId: '1',
          fileHash: 'hash1',
          filePath: '/path/test.jpg',
          fileName: 'test.jpg',
          mimeType: 'image/jpeg',
          fileSize: 1024,
          width: 1920,
          height: 1080,
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          scannedAt: DateTime.now(),
          status: MediaStatus.uploaded,
        );

        final result = BackupScheduler.evaluateMediaItem(
          item: item,
          settings: settings,
        );

        expect(result.included, isFalse);
      });

      test('excludes files exceeding max size', () {
        const settings = BackupSettings(maxFileSize: 1024);
        final item = MediaItem(
          localId: '1',
          fileHash: 'hash1',
          filePath: '/path/test.jpg',
          fileName: 'test.jpg',
          mimeType: 'image/jpeg',
          fileSize: 2048,
          width: 1920,
          height: 1080,
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          scannedAt: DateTime.now(),
        );

        final result = BackupScheduler.evaluateMediaItem(
          item: item,
          settings: settings,
        );

        expect(result.included, isFalse);
      });

      test('excludes files in excluded folder', () {
        const settings = BackupSettings(excludedFolders: ['/DCIM/Screenshots']);
        final item = MediaItem(
          localId: '1',
          fileHash: 'hash1',
          filePath: '/DCIM/Screenshots/test.jpg',
          fileName: 'test.jpg',
          mimeType: 'image/jpeg',
          fileSize: 1024,
          width: 1920,
          height: 1080,
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          scannedAt: DateTime.now(),
          deviceFolder: '/DCIM/Screenshots',
        );

        final result = BackupScheduler.evaluateMediaItem(
          item: item,
          settings: settings,
        );

        expect(result.included, isFalse);
      });

      test('excludes files with excluded hash', () {
        const settings = BackupSettings(excludedFileHashes: ['hash1']);
        final item = MediaItem(
          localId: '1',
          fileHash: 'hash1',
          filePath: '/path/test.jpg',
          fileName: 'test.jpg',
          mimeType: 'image/jpeg',
          fileSize: 1024,
          width: 1920,
          height: 1080,
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          scannedAt: DateTime.now(),
        );

        final result = BackupScheduler.evaluateMediaItem(
          item: item,
          settings: settings,
        );

        expect(result.included, isFalse);
      });
    });

    group('filterItemsForBackup', () {
      test('filters items based on settings', () {
        const settings = BackupSettings(
          maxFileSize: 1024 * 1024, // 1MB
          excludedFileHashes: ['excluded_hash'],
        );

        final items = [
          MediaItem(
            localId: '1',
            fileHash: 'hash1',
            filePath: '/path/small.jpg',
            fileName: 'small.jpg',
            mimeType: 'image/jpeg',
            fileSize: 512,
            width: 1920,
            height: 1080,
            createdAt: DateTime.now(),
            modifiedAt: DateTime.now(),
            scannedAt: DateTime.now(),
          ),
          MediaItem(
            localId: '2',
            fileHash: 'excluded_hash',
            filePath: '/path/excluded.jpg',
            fileName: 'excluded.jpg',
            mimeType: 'image/jpeg',
            fileSize: 512,
            width: 1920,
            height: 1080,
            createdAt: DateTime.now(),
            modifiedAt: DateTime.now(),
            scannedAt: DateTime.now(),
          ),
          MediaItem(
            localId: '3',
            fileHash: 'hash3',
            filePath: '/path/large.jpg',
            fileName: 'large.jpg',
            mimeType: 'image/jpeg',
            fileSize: 2 * 1024 * 1024, // 2MB
            width: 1920,
            height: 1080,
            createdAt: DateTime.now(),
            modifiedAt: DateTime.now(),
            scannedAt: DateTime.now(),
          ),
        ];

        final filtered = BackupScheduler.filterItemsForBackup(
          items: items,
          settings: settings,
        );

        expect(filtered.length, 1);
        expect(filtered[0].localId, '1');
      });
    });

    group('calculateBackoff', () {
      test('first retry is 5 seconds', () {
        final delay = BackupScheduler.calculateBackoff(1);
        expect(delay.inSeconds, 5);
      });

      test('second retry is 10 seconds', () {
        final delay = BackupScheduler.calculateBackoff(2);
        expect(delay.inSeconds, 10);
      });

      test('third retry is 20 seconds', () {
        final delay = BackupScheduler.calculateBackoff(3);
        expect(delay.inSeconds, 20);
      });

      test('backoff caps at 5 minutes', () {
        final delay = BackupScheduler.calculateBackoff(10);
        expect(delay.inMinutes, 5);
      });
    });
  });

  group('BackupSettings', () {
    test('allFoldersIncluded returns true when list is empty', () {
      const settings = BackupSettings();
      expect(settings.allFoldersIncluded, isTrue);
    });

    test('isFolderIncluded returns true when all folders included', () {
      const settings = BackupSettings();
      expect(settings.isFolderIncluded('/DCIM/Camera'), isTrue);
    });

    test('isFolderExcluded returns true when folder in excluded list', () {
      const settings = BackupSettings(excludedFolders: ['/DCIM/Screenshots']);
      expect(settings.isFolderExcluded('/DCIM/Screenshots'), isTrue);
      expect(settings.isFolderExcluded('/DCIM/Camera'), isFalse);
    });

    test('isFileSizeAllowed respects max file size', () {
      const settings = BackupSettings(maxFileSize: 1024);
      expect(settings.isFileSizeAllowed(512), isTrue);
      expect(settings.isFileSizeAllowed(1024), isTrue);
      expect(settings.isFileSizeAllowed(2048), isFalse);
    });

    test('isFileSizeAllowed returns true when no limit', () {
      const settings = BackupSettings();
      expect(settings.isFileSizeAllowed(1024 * 1024 * 1024), isTrue);
    });

    test('copyWith creates new instance with updated fields', () {
      const settings = BackupSettings(wifiOnly: true);
      final updated = settings.copyWith(wifiOnly: false);
      expect(updated.wifiOnly, isFalse);
      expect(settings.wifiOnly, isTrue);
    });
  });
}
