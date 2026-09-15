import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

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

  Future<Set<String>> mediaItemIndexNames(AppDatabase database) async {
    final rows = await database
        .customSelect(
          'SELECT name FROM sqlite_master '
          "WHERE type = 'index' AND tbl_name = 'media_items'",
        )
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

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
      final names = await mediaItemIndexNames(db);

      expect(
        names,
        containsAll([
          'idx_media_items_file_hash',
          'idx_media_items_status',
          'idx_media_items_album_name',
          'idx_media_items_created_at',
          'idx_media_items_is_favorite',
          'idx_media_items_trashed_trashed_at',
        ]),
      );
    });

    test('v3 -> v4 migration creates favorites and trash indexes', () async {
      final raw = sqlite3.openInMemory();
      raw.userVersion = 3;
      raw.execute(
        'CREATE TABLE media_items ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'local_id TEXT NOT NULL UNIQUE, file_hash TEXT NOT NULL, '
        'telegram_message_id TEXT, telegram_file_id TEXT, '
        'file_path TEXT NOT NULL, file_name TEXT NOT NULL, '
        'mime_type TEXT NOT NULL, file_size INTEGER NOT NULL, '
        'width INTEGER NOT NULL, height INTEGER NOT NULL, '
        'duration_ms INTEGER, created_at INTEGER NOT NULL, '
        'modified_at INTEGER NOT NULL, scanned_at INTEGER NOT NULL, '
        'uploaded_at INTEGER, backed_up_at INTEGER, '
        'status INTEGER NOT NULL DEFAULT 0, error_message TEXT, '
        'is_favorite INTEGER NOT NULL DEFAULT 0, '
        'is_hidden INTEGER NOT NULL DEFAULT 0, '
        'is_archived INTEGER NOT NULL DEFAULT 0, '
        'is_trashed INTEGER NOT NULL DEFAULT 0, trashed_at INTEGER, '
        'is_excluded INTEGER NOT NULL DEFAULT 0, album_name TEXT, '
        'device_folder TEXT, description TEXT, tags TEXT NOT NULL DEFAULT \'[]\', '
        'thumbnail_path TEXT)',
      );
      raw.execute(
        'CREATE INDEX idx_media_items_file_hash ON media_items (file_hash)',
      );
      raw.execute(
        'CREATE INDEX idx_media_items_status ON media_items (status)',
      );
      raw.execute(
        'CREATE INDEX idx_media_items_album_name ON media_items (album_name)',
      );
      raw.execute(
        'CREATE INDEX idx_media_items_created_at ON media_items (created_at)',
      );

      final migrated = AppDatabase.forTesting(NativeDatabase.opened(raw));
      addTearDown(migrated.close);

      final names = await mediaItemIndexNames(migrated);
      expect(names, contains('idx_media_items_is_favorite'));
      expect(names, contains('idx_media_items_trashed_trashed_at'));
      expect(names, contains('idx_media_items_file_hash'));
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
