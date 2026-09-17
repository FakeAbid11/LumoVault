import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/restore/data/repositories/channel_scan_service.dart';

void main() {
  group('ChannelScanResult', () {
    test('constructor sets all fields correctly', () {
      const result = ChannelScanResult(
        totalItems: 100,
        newItems: 50,
        skippedItems: 30,
        failedThumbnails: 5,
        hasBackup: true,
        error: null,
      );

      expect(result.totalItems, 100);
      expect(result.newItems, 50);
      expect(result.skippedItems, 30);
      expect(result.failedThumbnails, 5);
      expect(result.hasBackup, isTrue);
      expect(result.hasError, isFalse);
    });

    test('hasError is true when error message is provided', () {
      const result = ChannelScanResult(
        totalItems: 0,
        newItems: 0,
        skippedItems: 0,
        failedThumbnails: 0,
        hasBackup: false,
        error: 'TDLib connection failed',
      );

      expect(result.hasError, isTrue);
      expect(result.error, 'TDLib connection failed');
    });

    test('hasBackup is true even with errors', () {
      const result = ChannelScanResult(
        totalItems: 10,
        newItems: 5,
        skippedItems: 3,
        failedThumbnails: 2,
        hasBackup: true,
        error: 'Partial thumbnail failure',
      );

      expect(result.hasBackup, isTrue);
      expect(result.hasError, isTrue);
    });

    test('zero items result with no backup', () {
      const result = ChannelScanResult(
        totalItems: 0,
        newItems: 0,
        skippedItems: 0,
        failedThumbnails: 0,
        hasBackup: false,
      );

      expect(result.totalItems, 0);
      expect(result.hasBackup, isFalse);
    });
  });

  group('MediaItem.isTelegram', () {
    MediaItem makeItem({
      String? telegramMessageId,
      String filePath = '/some/local/path.jpg',
    }) {
      return MediaItem(
        localId: 'test_123',
        fileHash: 'abc123',
        telegramMessageId: telegramMessageId,
        filePath: filePath,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024,
        width: 800,
        height: 600,
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        scannedAt: DateTime(2026, 1, 15),
      );
    }

    test('returns false for local items with no telegramMessageId', () {
      final item = makeItem();
      expect(item.isTelegram, isFalse);
    });

    test(
      'returns false for local items with telegramMessageId but valid path',
      () {
        final item = makeItem(
          telegramMessageId: '123',
          filePath: '/storage/emulated/0/DCIM/photo.jpg',
        );
        expect(item.isTelegram, isFalse);
      },
    );

    test(
      'returns true when telegramMessageId is set and filePath is empty',
      () {
        final item = makeItem(telegramMessageId: '456', filePath: '');
        expect(item.isTelegram, isTrue);
      },
    );

    test(
      'returns true when telegramMessageId is set and filePath starts with telegram://',
      () {
        final item = makeItem(
          telegramMessageId: '789',
          filePath: 'telegram://789',
        );
        expect(item.isTelegram, isTrue);
      },
    );

    test(
      'returns false when telegramMessageId is null even with telegram:// path',
      () {
        final item = makeItem(filePath: 'telegram://789');
        // No telegramMessageId set, so isTelegram should be false
        expect(item.isTelegram, isFalse);
      },
    );
  });

  group('MediaItem.status', () {
    test('default status is pending', () {
      final item = MediaItem(
        localId: 'test',
        fileHash: 'hash',
        filePath: '/path',
        fileName: 'file.jpg',
        mimeType: 'image/jpeg',
        fileSize: 100,
        width: 100,
        height: 100,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        scannedAt: DateTime.now(),
      );
      expect(item.status, MediaStatus.pending);
    });

    test('status can be set to uploaded', () {
      final item = MediaItem(
        localId: 'test',
        fileHash: 'hash',
        filePath: '/path',
        fileName: 'file.jpg',
        mimeType: 'image/jpeg',
        fileSize: 100,
        width: 100,
        height: 100,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        scannedAt: DateTime.now(),
        status: MediaStatus.uploaded,
      );
      expect(item.status, MediaStatus.uploaded);
    });
  });
}
