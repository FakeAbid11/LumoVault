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

    // A field-level round-trip guard. The mergeQueues tests above never
    // compare a task to its own serialized form, so a field that _taskToJson
    // writes without _taskFromJson reading back (or omits entirely) slips
    // through silently — which is exactly how durationMs was lost, leaving a
    // video whose task survived a restart uploading a caption with 0:00.
    test('a fully populated task survives encode -> decode intact', () {
      final task = UploadTask(
        id: 't1',
        mediaItemId: 'm1',
        localFilePath: '/dcim/video.mp4',
        fileName: 'video.mp4',
        fileSize: 4096,
        fileHash: 'hash_t1',
        telegramFileId: 'tf-1',
        telegramMessageId: 'tm-1',
        status: UploadStatus.queued,
        progress: 0.25,
        retryCount: 1,
        nextAttemptAt: DateTime.utc(2026, 3, 1, 12),
        createdAt: DateTime.utc(2026, 2, 28),
        mediaCreatedAt: DateTime.utc(2026, 1, 5, 9, 30),
        mediaModifiedAt: DateTime.utc(2026, 1, 5, 9, 31),
        startedAt: DateTime.utc(2026, 2, 28, 10),
        completedAt: DateTime.utc(2026, 2, 28, 11),
        failedAt: DateTime.utc(2026, 2, 28, 12),
        pausedAt: DateTime.utc(2026, 2, 28, 13),
        lastActivityAt: DateTime.utc(2026, 2, 28, 14),
        priority: 7,
        durationMs: 30000,
        error: TransferError(
          category: TransferErrorCategory.floodWait,
          message: 'Too Many Requests: retry after 30',
          detail: 'FLOOD_WAIT_30',
          retryable: true,
          retryAfterSeconds: 30,
          occurredAt: DateTime.utc(2026, 2, 28, 15),
        ),
      );

      final decoded = persistence.decodeTask(persistence.encodeTask(task));

      expect(decoded.id, task.id);
      expect(decoded.mediaItemId, task.mediaItemId);
      expect(decoded.localFilePath, task.localFilePath);
      expect(decoded.fileName, task.fileName);
      expect(decoded.fileSize, task.fileSize);
      expect(decoded.fileHash, task.fileHash);
      expect(decoded.telegramFileId, task.telegramFileId);
      expect(decoded.telegramMessageId, task.telegramMessageId);
      expect(decoded.status, task.status);
      expect(decoded.progress, task.progress);
      expect(decoded.retryCount, task.retryCount);
      expect(decoded.nextAttemptAt, task.nextAttemptAt);
      expect(decoded.createdAt, task.createdAt);
      expect(decoded.mediaCreatedAt, task.mediaCreatedAt);
      expect(decoded.mediaModifiedAt, task.mediaModifiedAt);
      expect(decoded.startedAt, task.startedAt);
      expect(decoded.completedAt, task.completedAt);
      expect(decoded.failedAt, task.failedAt);
      expect(decoded.pausedAt, task.pausedAt);
      expect(decoded.lastActivityAt, task.lastActivityAt);
      expect(decoded.priority, task.priority);
      expect(
        decoded.durationMs,
        task.durationMs,
        reason:
            'video length feeds the backup caption and must survive a '
            'restart — it was silently dropped on both sides of the codec',
      );
      expect(decoded.error?.category, task.error?.category);
      expect(decoded.error?.message, task.error?.message);
      expect(decoded.error?.detail, task.error?.detail);
      expect(decoded.error?.retryable, task.error?.retryable);
      expect(decoded.error?.retryAfterSeconds, task.error?.retryAfterSeconds);
      expect(decoded.error?.occurredAt, task.error?.occurredAt);
    });

    test('thumbnailPath is documented transient and is not persisted', () {
      final task = UploadTask(
        id: 't2',
        mediaItemId: 'm2',
        localFilePath: '/dcim/a.jpg',
        fileName: 'a.jpg',
        fileSize: 10,
        fileHash: 'h',
        createdAt: DateTime.utc(2026),
        thumbnailPath: '/tmp/poster_t2.jpg',
      );

      final decoded = persistence.decodeTask(persistence.encodeTask(task));

      expect(decoded.thumbnailPath, isNull);
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

      // A pause is a user decision — it must survive a restart.
      expect(merged.length, equals(1));
      expect(merged.first.status, equals(UploadStatus.paused));
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
