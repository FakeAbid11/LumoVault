import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/constants/app_constants.dart';

void main() {
  group('AppConstants', () {
    test('appName is not empty', () {
      expect(AppConstants.appName, isNotEmpty);
    });

    test('appName equals LumoVault', () {
      expect(AppConstants.appName, 'LumoVault');
    });

    test('schemaVersion is positive', () {
      expect(AppConstants.schemaVersion, greaterThan(0));
    });

    test('maxRetryAttempts is positive', () {
      expect(AppConstants.maxRetryAttempts, greaterThan(0));
    });

    test('defaultUploadBatchSize is positive', () {
      expect(AppConstants.defaultUploadBatchSize, greaterThan(0));
    });

    test('defaultUploadDelayMs is positive', () {
      expect(AppConstants.defaultUploadDelayMs, greaterThan(0));
    });

    test('thumbnailCacheSizeMB is positive', () {
      expect(AppConstants.thumbnailCacheSizeMB, greaterThan(0));
    });

    test('galleryPageSize is positive', () {
      expect(AppConstants.galleryPageSize, greaterThan(0));
    });

    test('trashRetentionDays is 30', () {
      expect(AppConstants.trashRetentionDays, 30);
    });

    test('mediaScannerIntervalMinutes is 15', () {
      expect(AppConstants.mediaScannerIntervalMinutes, 15);
    });

    test('maxFileSizeBytes is 2GB', () {
      expect(AppConstants.maxFileSizeBytes, 2 * 1024 * 1024 * 1024);
    });
  });
}
