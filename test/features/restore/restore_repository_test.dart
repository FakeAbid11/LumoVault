import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/restore/data/repositories/restore_repository.dart';
import 'package:lumovault/features/restore/data/models/restore_progress.dart';

void main() {
  group('RestoreRepository', () {
    test(
      'ChannelDetectionResult hasBackup returns true for existing channel',
      () {
        const result = ChannelDetectionResult(
          channelId: 123,
          isNewChannel: false,
        );
        expect(result.hasBackup, isTrue);
        expect(result.hasError, isFalse);
        expect(result.isNew, isFalse);
      },
    );

    test('ChannelDetectionResult hasBackup returns false for new channel', () {
      const result = ChannelDetectionResult(channelId: 123, isNewChannel: true);
      expect(result.hasBackup, isFalse);
      expect(result.isNew, isTrue);
    });

    test('ChannelDetectionResult hasError returns true when error is set', () {
      const result = ChannelDetectionResult(error: 'Failed to connect');
      expect(result.hasError, isTrue);
      expect(result.hasBackup, isFalse);
    });

    test('ChannelMessage captionMetadata parses valid JSON', () {
      const message = ChannelMessage(
        messageId: 1,
        fileId: 100,
        fileName: 'photo.jpg',
        caption: '{"mid":"123","h":"abc123","ct":"2026-01-15T00:00:00Z"}',
      );

      final metadata = message.captionMetadata;
      expect(metadata, isNotNull);
      expect(metadata!.mediaItemId, '123');
      expect(metadata.fileHash, 'abc123');
    });

    test('ChannelMessage captionMetadata returns null for null caption', () {
      const message = ChannelMessage(
        messageId: 1,
        fileId: 100,
        fileName: 'photo.jpg',
        caption: null,
      );
      expect(message.captionMetadata, isNull);
    });

    test('ChannelMessage captionMetadata returns null for empty caption', () {
      const message = ChannelMessage(
        messageId: 1,
        fileId: 100,
        fileName: 'photo.jpg',
        caption: '',
      );
      expect(message.captionMetadata, isNull);
    });

    test('DownloadedFile stores metadata correctly', () {
      const file = DownloadedFile(
        filePath: '/path/to/file.jpg',
        fileName: 'file.jpg',
      );
      expect(file.filePath, '/path/to/file.jpg');
      expect(file.fileName, 'file.jpg');
      expect(file.metadata, isNull);
    });

    test('RestoreError.network creates retryable error', () {
      final error = RestoreError.network(message: 'No connection');
      expect(error.category, RestoreErrorCategory.network);
      expect(error.retryable, isTrue);
      expect(error.message, 'No connection');
    });

    test('RestoreError.channelNotFound creates non-retryable error', () {
      final error = RestoreError.channelNotFound();
      expect(error.category, RestoreErrorCategory.channelNotFound);
      expect(error.retryable, isFalse);
    });

    test('RestoreError.manifestCorrupted creates non-retryable error', () {
      final error = RestoreError.manifestCorrupted();
      expect(error.category, RestoreErrorCategory.manifestCorrupted);
      expect(error.retryable, isFalse);
    });

    test('RestoreError.storageFull creates non-retryable error', () {
      final error = RestoreError.storageFull();
      expect(error.category, RestoreErrorCategory.storageFull);
      expect(error.retryable, isFalse);
    });

    test('RestoreError.authExpired creates non-retryable error', () {
      final error = RestoreError.authExpired();
      expect(error.category, RestoreErrorCategory.authExpired);
      expect(error.retryable, isFalse);
    });

    test('RestoreError.cancelled creates non-retryable error', () {
      final error = RestoreError.cancelled();
      expect(error.category, RestoreErrorCategory.cancelled);
      expect(error.retryable, isFalse);
    });
  });
}
