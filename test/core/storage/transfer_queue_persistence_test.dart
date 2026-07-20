import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/upload_task.dart';
import 'package:lumovault/features/gallery/data/models/transfer_error.dart';
import 'package:lumovault/core/storage/transfer_queue_persistence.dart';

void main() {
  group('TransferQueuePersistence', () {
    late TransferQueuePersistence persistence;

    setUp(() {
      persistence = TransferQueuePersistence.instance;
    });

    test('mergeQueues returns live tasks when persisted is empty', () {
      final live = [
        _createTask(id: '1', status: UploadStatus.queued),
        _createTask(id: '2', status: UploadStatus.uploading),
      ];

      final merged = persistence.mergeQueues(live: live, persisted: []);

      expect(merged.length, equals(2));
    });

    test('mergeQueues adds persisted tasks not in live', () {
      final live = [_createTask(id: '1', status: UploadStatus.queued)];
      final persisted = [
        _createTask(id: '2', status: UploadStatus.queued),
        _createTask(id: '3', status: UploadStatus.failed),
      ];

      final merged = persistence.mergeQueues(live: live, persisted: persisted);

      expect(merged.length, equals(3));
    });

    test('mergeQueues skips completed persisted tasks', () {
      final live = <UploadTask>[];
      final persisted = [
        _createTask(id: '1', status: UploadStatus.completed),
        _createTask(id: '2', status: UploadStatus.queued),
      ];

      final merged = persistence.mergeQueues(live: live, persisted: persisted);

      expect(merged.length, equals(1));
      expect(merged.first.id, equals('2'));
    });

    test('mergeQueues resets uploading tasks to queued', () {
      final live = <UploadTask>[];
      final persisted = [
        _createTask(id: '1', status: UploadStatus.uploading, progress: 0.5),
      ];

      final merged = persistence.mergeQueues(live: live, persisted: persisted);

      expect(merged.length, equals(1));
      expect(merged.first.status, equals(UploadStatus.queued));
      expect(merged.first.progress, equals(0));
    });

    test('mergeQueues deduplicates by task id', () {
      final live = [_createTask(id: '1', status: UploadStatus.queued)];
      final persisted = [
        _createTask(id: '1', status: UploadStatus.failed),
        _createTask(id: '2', status: UploadStatus.queued),
      ];

      final merged = persistence.mergeQueues(live: live, persisted: persisted);

      expect(merged.length, equals(2));
      // The live version should be kept.
      expect(merged.first.status, equals(UploadStatus.queued));
    });

    test('mergeQueues keeps paused persisted tasks', () {
      final live = <UploadTask>[];
      final persisted = [_createTask(id: '1', status: UploadStatus.paused)];

      final merged = persistence.mergeQueues(live: live, persisted: persisted);

      // Paused tasks are not kept (only queued and failed).
      expect(merged.length, equals(0));
    });
  });

  group('UploadTask serialization', () {
    test('copyWith preserves fields', () {
      final task = _createTask(
        id: '1',
        status: UploadStatus.queued,
        progress: 0.5,
        retryCount: 2,
      );

      final updated = task.copyWith(
        status: UploadStatus.uploading,
        progress: 0.75,
      );

      expect(updated.id, equals('1'));
      expect(updated.status, equals(UploadStatus.uploading));
      expect(updated.progress, equals(0.75));
      expect(updated.retryCount, equals(2));
    });

    test('isTerminal is true for completed and failed', () {
      final completed = _createTask(id: '1', status: UploadStatus.completed);
      final failed = _createTask(id: '2', status: UploadStatus.failed);
      final queued = _createTask(id: '3', status: UploadStatus.queued);

      expect(completed.isTerminal, isTrue);
      expect(failed.isTerminal, isTrue);
      expect(queued.isTerminal, isFalse);
    });

    test('canRetry is true for failed with low retry count', () {
      final task = _createTask(
        id: '1',
        status: UploadStatus.failed,
        retryCount: 1,
      );

      expect(task.canRetry, isTrue);
    });

    test('canRetry is false for completed', () {
      final task = _createTask(
        id: '1',
        status: UploadStatus.completed,
        retryCount: 0,
      );

      expect(task.canRetry, isFalse);
    });

    test('canRetry is false for high retry count', () {
      final task = _createTask(
        id: '1',
        status: UploadStatus.failed,
        retryCount: 5,
      );

      expect(task.canRetry, isFalse);
    });

    test('equality based on id, mediaItemId, and status', () {
      final a = _createTask(
        id: '1',
        mediaItemId: 'm1',
        status: UploadStatus.queued,
      );
      final b = _createTask(
        id: '1',
        mediaItemId: 'm1',
        status: UploadStatus.queued,
      );
      final c = _createTask(
        id: '1',
        mediaItemId: 'm1',
        status: UploadStatus.failed,
      );

      expect(a, equals(b));
      expect(a == c, isFalse);
    });
  });

  group('TransferError', () {
    test('displayMessage returns correct message for each category', () {
      expect(
        TransferError(
          category: TransferErrorCategory.network,
          message: 'Network error',
          occurredAt: DateTime(2024),
        ).displayMessage,
        contains('Network error'),
      );

      expect(
        TransferError(
          category: TransferErrorCategory.storageFull,
          message: 'Storage full',
          occurredAt: DateTime(2024),
        ).displayMessage,
        contains('storage is full'),
      );

      expect(
        TransferError(
          category: TransferErrorCategory.authExpired,
          message: 'Auth expired',
          occurredAt: DateTime(2024),
        ).displayMessage,
        contains('Session expired'),
      );
    });

    test('fromTdLibError creates correct category', () {
      final error = TransferError.fromTdLibError(
        'NETWORK_ERROR',
        'Connection failed',
      );

      expect(error.category, equals(TransferErrorCategory.network));
      expect(error.retryable, isTrue);
    });

    test('copyWith preserves fields', () {
      final error = TransferError(
        category: TransferErrorCategory.network,
        message: 'Original',
        occurredAt: DateTime(2024),
      );

      final updated = error.copyWith(message: 'Updated');

      expect(updated.message, equals('Updated'));
      expect(updated.category, equals(TransferErrorCategory.network));
    });

    test('equality based on category and message', () {
      final a = TransferError(
        category: TransferErrorCategory.network,
        message: 'Error',
        occurredAt: DateTime(2024),
      );
      final b = TransferError(
        category: TransferErrorCategory.network,
        message: 'Error',
        occurredAt: DateTime(2025),
      );

      expect(a, equals(b));
    });
  });
}

UploadTask _createTask({
  required String id,
  String? mediaItemId,
  UploadStatus status = UploadStatus.queued,
  double progress = 0,
  int retryCount = 0,
}) {
  return UploadTask(
    id: id,
    mediaItemId: mediaItemId ?? 'media_$id',
    localFilePath: '/path/to/file_$id.jpg',
    fileName: 'file_$id.jpg',
    fileSize: 1024,
    fileHash: 'hash_$id',
    status: status,
    progress: progress,
    retryCount: retryCount,
    createdAt: DateTime(2024),
  );
}
