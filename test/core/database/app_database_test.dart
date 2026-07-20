import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/core/database/media_item_mapper.dart';
import 'package:lumovault/core/database/upload_task_mapper.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/models/transfer_error.dart';
import 'package:lumovault/features/gallery/data/models/upload_task.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  MediaItem buildMediaItem() => MediaItem(
    localId: 'local-1',
    fileHash: 'hash-abc',
    telegramMessageId: 'msg-1',
    telegramFileId: 'file-1',
    filePath: '/storage/pic.jpg',
    fileName: 'pic.jpg',
    mimeType: 'image/jpeg',
    fileSize: 2048,
    width: 100,
    height: 200,
    durationMs: null,
    createdAt: DateTime(2026, 1, 1),
    modifiedAt: DateTime(2026, 1, 2),
    scannedAt: DateTime(2026, 1, 3),
    status: MediaStatus.uploaded,
    isFavorite: true,
    albumName: 'Camera',
    deviceFolder: '/storage/DCIM/Camera',
    description: 'a photo',
    tags: const ['beach', 'sun'],
  );

  UploadTask buildUploadTask({TransferError? error}) => UploadTask(
    id: 'task-1',
    mediaItemId: 'local-1',
    localFilePath: '/storage/pic.jpg',
    fileName: 'pic.jpg',
    fileSize: 2048,
    fileHash: 'hash-abc',
    status: UploadStatus.failed,
    progress: 0.5,
    retryCount: 2,
    createdAt: DateTime(2026, 1, 1),
    error: error,
  );

  group('AppDatabase schema', () {
    test('creates tables and starts empty', () async {
      expect(await db.select(db.mediaItems).get(), isEmpty);
      expect(await db.select(db.uploadTasks).get(), isEmpty);
    });
  });

  group('MediaItem mapping', () {
    test('round-trips domain -> row -> domain losslessly', () async {
      final original = buildMediaItem();

      await db.into(db.mediaItems).insert(original.toCompanion());
      final row = await db.select(db.mediaItems).getSingle();
      final restored = row.toDomain();

      expect(restored.localId, original.localId);
      expect(restored.fileHash, original.fileHash);
      expect(restored.telegramMessageId, original.telegramMessageId);
      expect(restored.mimeType, original.mimeType);
      expect(restored.fileSize, original.fileSize);
      expect(restored.width, original.width);
      expect(restored.height, original.height);
      expect(restored.createdAt, original.createdAt);
      expect(restored.status, MediaStatus.uploaded);
      expect(restored.isFavorite, isTrue);
      expect(restored.albumName, 'Camera');
      expect(restored.description, 'a photo');
      expect(restored.tags, const ['beach', 'sun']);
    });

    test('assigns an autoincrement id on insert', () async {
      await db.into(db.mediaItems).insert(buildMediaItem().toCompanion());
      final row = await db.select(db.mediaItems).getSingle();
      expect(row.id, greaterThan(0));
    });

    test('localId is unique', () async {
      await db.into(db.mediaItems).insert(buildMediaItem().toCompanion());
      expect(
        () => db.into(db.mediaItems).insert(buildMediaItem().toCompanion()),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('UploadTask mapping', () {
    test('round-trips a task with no error', () async {
      final original = buildUploadTask();

      await db.into(db.uploadTasks).insert(original.toCompanion());
      final row = await db.select(db.uploadTasks).getSingle();
      final restored = row.toDomain();

      expect(restored.id, original.id);
      expect(restored.mediaItemId, original.mediaItemId);
      expect(restored.status, UploadStatus.failed);
      expect(restored.progress, 0.5);
      expect(restored.retryCount, 2);
      expect(restored.error, isNull);
    });

    test('round-trips a task with a TransferError losslessly', () async {
      final error = TransferError(
        category: TransferErrorCategory.floodWait,
        message: 'slow down',
        detail: 'FLOOD_WAIT',
        retryable: true,
        retryAfterSeconds: 30,
        occurredAt: DateTime(2026, 1, 4),
      );
      final original = buildUploadTask(error: error);

      await db.into(db.uploadTasks).insert(original.toCompanion());
      final row = await db.select(db.uploadTasks).getSingle();
      final restored = row.toDomain();

      expect(restored.error, isNotNull);
      expect(restored.error!.category, TransferErrorCategory.floodWait);
      expect(restored.error!.message, 'slow down');
      expect(restored.error!.detail, 'FLOOD_WAIT');
      expect(restored.error!.retryable, isTrue);
      expect(restored.error!.retryAfterSeconds, 30);
      expect(restored.error!.occurredAt, DateTime(2026, 1, 4));
    });
  });
}
