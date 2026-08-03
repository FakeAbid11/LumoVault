import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumovault/features/settings/data/models/app_settings.dart';

void main() {
  group('AppSettings', () {
    group('defaults', () {
      test('returns correct default values', () {
        const settings = AppSettings();

        expect(settings.languageCode, 'en');
        expect(settings.onboardingCompleted, false);
        expect(settings.autoBackupEnabled, true);
        expect(settings.wifiOnly, true);
        expect(settings.chargingOnly, false);
        expect(settings.minBatteryLevel, 20);
        expect(settings.backgroundBackupEnabled, true);
        expect(settings.maxParallelUploads, 3);
        expect(settings.backupVideos, true);
        expect(settings.backupPhotos, true);
        expect(settings.includedFolders, isEmpty);
        expect(settings.excludedFolders, isEmpty);
        expect(settings.excludedAlbums, isEmpty);
        expect(settings.excludedFileHashes, isEmpty);
        expect(settings.uploadBatchSize, 10);
        expect(settings.uploadDelayMs, 2000);
        expect(settings.maxFileSizeBytes, 0);
        expect(settings.storageChannelId, isNull);
        expect(settings.maxCacheSizeMB, 500);
        expect(settings.trashDurationDays, 30);
        expect(settings.themeMode, ThemeMode.system);
        expect(settings.useDynamicColor, false);
        expect(settings.gridSize, GridSize.medium);
        expect(settings.compactMode, false);
        expect(settings.animationsEnabled, true);
        expect(settings.biometricLockEnabled, false);
        expect(settings.pinLockEnabled, false);
        expect(settings.pinHash, isNull);
        expect(settings.hideSensitiveAlbums, false);
        expect(settings.requireAuthOnAppOpen, false);
        expect(settings.clearClipboardAfterShare, true);
        expect(settings.backupProgressNotification, true);
        expect(settings.backupCompletedNotification, true);
        expect(settings.backupFailedNotification, true);
        expect(settings.restoreCompletedNotification, true);
        expect(settings.storageWarningNotification, true);
      });

      test('factory defaults() returns same as const constructor', () {
        expect(AppSettings.defaults(), equals(const AppSettings()));
      });
    });

    group('copyWith', () {
      test('updates individual fields', () {
        const original = AppSettings();
        final updated = original.copyWith(autoBackupEnabled: false);

        expect(updated.autoBackupEnabled, false);
        expect(updated.wifiOnly, original.wifiOnly);
      });

      test('updates theme mode', () {
        const original = AppSettings();
        final updated = original.copyWith(themeMode: ThemeMode.dark);

        expect(updated.themeMode, ThemeMode.dark);
      });

      test('updates grid size', () {
        const original = AppSettings();
        final updated = original.copyWith(gridSize: GridSize.small);

        expect(updated.gridSize, GridSize.small);
      });

      test('clears pinHash with clearPinHash', () {
        const original = AppSettings(pinHash: 'abc123');
        final updated = original.copyWith(clearPinHash: true);

        expect(updated.pinHash, isNull);
      });

      test('preserves other fields when updating', () {
        const original = AppSettings(
          languageCode: 'es',
          autoBackupEnabled: false,
          maxParallelUploads: 5,
        );
        final updated = original.copyWith(wifiOnly: false);

        expect(updated.languageCode, 'es');
        expect(updated.autoBackupEnabled, false);
        expect(updated.maxParallelUploads, 5);
        expect(updated.wifiOnly, false);
      });
    });

    group('GridSize', () {
      test('small has 3 columns', () {
        expect(GridSize.small.columns, 3);
      });

      test('medium has 2 columns', () {
        expect(GridSize.medium.columns, 2);
      });

      test('large has 1 column', () {
        expect(GridSize.large.columns, 1);
      });
    });

    group('serialization', () {
      test('toJsonString and fromJsonString roundtrip', () {
        const original = AppSettings(
          languageCode: 'es',
          autoBackupEnabled: false,
          maxParallelUploads: 5,
          themeMode: ThemeMode.dark,
          gridSize: GridSize.large,
          pinHash: 'test_hash',
          storageChannelId: 12345,
        );

        final json = original.toJsonString();
        final restored = AppSettings.fromJsonString(json);

        expect(restored, equals(original));
      });

      test('fromJsonString returns defaults for invalid JSON', () {
        final restored = AppSettings.fromJsonString('not valid json');

        expect(restored, equals(const AppSettings()));
      });

      test('fromJsonString handles empty JSON object', () {
        final restored = AppSettings.fromJsonString('{}');

        expect(restored, equals(const AppSettings()));
      });

      test('fromJsonString handles partial JSON', () {
        const json = '{"languageCode": "fr", "autoBackupEnabled": false}';
        final restored = AppSettings.fromJsonString(json);

        expect(restored.languageCode, 'fr');
        expect(restored.autoBackupEnabled, false);
        // All other fields should be defaults
        expect(restored.wifiOnly, true);
      });

      test('fromJsonString handles null values gracefully', () {
        const json = '{"languageCode": null, "autoBackupEnabled": null}';
        final restored = AppSettings.fromJsonString(json);

        expect(restored.languageCode, 'en');
        expect(restored.autoBackupEnabled, true);
      });
    });

    group('equality', () {
      test('equal settings are equal', () {
        const a = AppSettings(languageCode: 'en', autoBackupEnabled: false);
        const b = AppSettings(languageCode: 'en', autoBackupEnabled: false);

        expect(a, equals(b));
      });

      test('different settings are not equal', () {
        const a = AppSettings(autoBackupEnabled: true);
        const b = AppSettings(autoBackupEnabled: false);

        expect(a, isNot(equals(b)));
      });

      test('same instance is identical', () {
        const a = AppSettings();

        expect(a, equals(a));
        expect(identical(a, a), isTrue);
      });
    });
  });
}
