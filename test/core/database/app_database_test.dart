import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/core/database/media_item_mapper.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';

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

  group('AppDatabase schema', () {
    test('creates tables and starts empty', () async {
      expect(await db.select(db.mediaItems).get(), isEmpty);
    });

    test('creates indexes for query hot paths', () async {
      final rows = await db
          .customSelect(
            'SELECT name FROM sqlite_master '
            "WHERE type = 'index' AND tbl_name = 'media_items'",
          )
          .get();
      final names = rows.map((r) => r.read<String>('name')).toSet();

      expect(
        names,
        containsAll([
          'idx_media_items_file_hash',
          'idx_media_items_status',
          'idx_media_items_album_name',
          'idx_media_items_created_at',
        ]),
      );
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
}
