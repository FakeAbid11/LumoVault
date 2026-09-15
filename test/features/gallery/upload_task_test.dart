import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/upload_task.dart';
import 'package:lumovault/features/gallery/data/models/transfer_error.dart';

void main() {
  group('UploadTask', () {
    test('default values are correct', () {
      final task = UploadTask(
        id: '1',
        mediaItemId: 'media_1',
        localFilePath: '/path/test.jpg',
        fileName: 'test.jpg',
        fileSize: 1000,
        fileHash: 'hash1',
        createdAt: DateTime(2026, 7, 14),
      );

      expect(task.status, UploadStatus.queued);
      expect(task.progress, 0.0);
      expect(task.retryCount, 0);
      expect(task.error, isNull);
      expect(task.telegramFileId, isNull);
      expect(task.telegramMessageId, isNull);
    });

    test('isTerminal returns true for completed and failed', () {
      final completedTask = UploadTask(
        id: '1',
        mediaItemId: 'media_1',
        localFilePath: '/path/test.jpg',
        fileName: 'test.jpg',
        fileSize: 1000,
        fileHash: 'hash1',
        createdAt: DateTime(2026, 7, 14),
        status: UploadStatus.completed,
      );

      final failedTask = UploadTask(
        id: '2',
        mediaItemId: 'media_2',
        localFilePath: '/path/test2.jpg',
        fileName: 'test2.jpg',
        fileSize: 2000,
        fileHash: 'hash2',
        createdAt: DateTime(2026, 7, 14),
        status: UploadStatus.failed,
      );

      final uploadingTask = UploadTask(
        id: '3',
        mediaItemId: 'media_3',
        localFilePath: '/path/test3.jpg',
        fileName: 'test3.jpg',
        fileSize: 3000,
        fileHash: 'hash3',
        createdAt: DateTime(2026, 7, 14),
        status: UploadStatus.uploading,
      );

      expect(completedTask.isTerminal, true);
      expect(failedTask.isTerminal, true);
      expect(uploadingTask.isTerminal, false);
    });

    test('canRetry returns true for failed tasks under retry limit', () {
      final task = UploadTask(
        id: '1',
        mediaItemId: 'media_1',
        localFilePath: '/path/test.jpg',
        fileName: 'test.jpg',
        fileSize: 1000,
        fileHash: 'hash1',
        createdAt: DateTime(2026, 7, 14),
        status: UploadStatus.failed,
        retryCount: 2,
      );

      expect(task.canRetry, true);
    });

    test('canRetry returns false for failed tasks at retry limit', () {
      final task = UploadTask(
        id: '1',
        mediaItemId: 'media_1',
        localFilePath: '/path/test.jpg',
        fileName: 'test.jpg',
        fileSize: 1000,
        fileHash: 'hash1',
        createdAt: DateTime(2026, 7, 14),
        status: UploadStatus.failed,
        retryCount: 3,
      );

      expect(task.canRetry, false);
    });

    test('copyWith creates new instance with updated fields', () {
      final task = UploadTask(
        id: '1',
        mediaItemId: 'media_1',
        localFilePath: '/path/test.jpg',
        fileName: 'test.jpg',
        fileSize: 1000,
        fileHash: 'hash1',
        createdAt: DateTime(2026, 7, 14),
      );

      final updated = task.copyWith(
        status: UploadStatus.uploading,
        progress: 0.5,
      );

      expect(updated.status, UploadStatus.uploading);
      expect(updated.progress, 0.5);
      expect(task.status, UploadStatus.queued);
      expect(task.progress, 0.0);
    });

    test('equality based on id, mediaItemId, and status', () {
      final task1 = UploadTask(
        id: '1',
        mediaItemId: 'media_1',
        localFilePath: '/path/test.jpg',
        fileName: 'test.jpg',
        fileSize: 1000,
        fileHash: 'hash1',
        createdAt: DateTime(2026, 7, 14),
        status: UploadStatus.queued,
      );

      final task2 = UploadTask(
        id: '1',
        mediaItemId: 'media_1',
        localFilePath: '/path/test2.jpg',
        fileName: 'test2.jpg',
        fileSize: 2000,
        fileHash: 'hash2',
        createdAt: DateTime(2026, 7, 14),
        status: UploadStatus.queued,
      );

      final task3 = UploadTask(
        id: '1',
        mediaItemId: 'media_1',
        localFilePath: '/path/test3.jpg',
        fileName: 'test3.jpg',
        fileSize: 3000,
        fileHash: 'hash3',
        createdAt: DateTime(2026, 7, 14),
        status: UploadStatus.uploading,
      );

      expect(task1, equals(task2));
      expect(task1, isNot(equals(task3)));
    });

    test('clearError removes error on copyWith', () {
      final task = UploadTask(
        id: '1',
        mediaItemId: 'media_1',
        localFilePath: '/path/test.jpg',
        fileName: 'test.jpg',
        fileSize: 1000,
        fileHash: 'hash1',
        createdAt: DateTime(2026, 7, 14),
        error: TransferError(
          category: TransferErrorCategory.network,
          message: 'Network error',
          occurredAt: DateTime(2026, 7, 14),
        ),
      );

      final cleared = task.copyWith(clearError: () => null);

      expect(cleared.error, isNull);
    });
  });
}
