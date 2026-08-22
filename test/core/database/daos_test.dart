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

  MediaItem media({
    required String localId,
    int? id,
    String hash = 'h',
    DateTime? createdAt,
    bool favorite = false,
    bool trashed = false,
    bool hidden = false,
    DateTime? trashedAt,
    String? album,
    String fileName = 'pic.jpg',
    String? description,
  }) => MediaItem(
    id: id,
    localId: localId,
    fileHash: '$hash-$localId',
    filePath: '/p/$localId',
    fileName: fileName,
    mimeType: 'image/jpeg',
    fileSize: 1,
    width: 1,
    height: 1,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    modifiedAt: DateTime(2026, 1, 1),
    scannedAt: DateTime(2026, 1, 1),
    isFavorite: favorite,
    isTrashed: trashed,
    isHidden: hidden,
    trashedAt: trashedAt,
    albumName: album,
    description: description,
  );

  group('MediaDao', () {
    test('timeline excludes trashed and hidden, newest first', () async {
      await db.mediaDao.upsertAll([
        media(localId: 'a', createdAt: DateTime(2026, 1, 1)).toCompanion(),
        media(localId: 'b', createdAt: DateTime(2026, 1, 3)).toCompanion(),
        media(localId: 'c', trashed: true).toCompanion(),
        media(localId: 'd', hidden: true).toCompanion(),
      ]);

      final rows = await db.mediaDao.timeline();
      expect(rows.map((r) => r.localId), ['b', 'a']);
    });

    test('favorites returns only favorited, non-trashed', () async {
      await db.mediaDao.upsertAll([
        media(localId: 'a', favorite: true).toCompanion(),
        media(localId: 'b').toCompanion(),
        media(localId: 'c', favorite: true, trashed: true).toCompanion(),
        media(localId: 'd', favorite: true, hidden: true).toCompanion(),
      ]);

      final rows = await db.mediaDao.favorites();
      expect(rows.map((r) => r.localId), ['a']);
    });

    test('byAlbum excludes trashed and hidden items', () async {
      await db.mediaDao.upsertAll([
        media(localId: 'a', album: 'Camera').toCompanion(),
        media(localId: 'b', album: 'Camera', trashed: true).toCompanion(),
        media(localId: 'c', album: 'Camera', hidden: true).toCompanion(),
        media(localId: 'd', album: 'Screenshots').toCompanion(),
      ]);

      final rows = await db.mediaDao.byAlbum('Camera');
      expect(rows.map((r) => r.localId), ['a']);
    });

    test(
      'search matches file name and description, case-insensitive',
      () async {
        await db.mediaDao.upsertAll([
          media(localId: 'a', fileName: 'Sunset.jpg').toCompanion(),
          media(localId: 'b', description: 'a lovely SUNSET').toCompanion(),
          media(localId: 'c', fileName: 'cat.png').toCompanion(),
          media(
            localId: 'd',
            fileName: 'sunset.jpg',
            hidden: true,
          ).toCompanion(),
          media(
            localId: 'e',
            fileName: 'sunset.jpg',
            trashed: true,
          ).toCompanion(),
        ]);

        final rows = await db.mediaDao.search('sunset');
        expect(rows.map((r) => r.localId).toSet(), {'a', 'b'});
      },
    );

    test('byLocalId and byHash look up single rows', () async {
      await db.mediaDao.upsert(media(localId: 'a').toCompanion());
      expect((await db.mediaDao.byLocalId('a'))?.localId, 'a');
      expect((await db.mediaDao.byHash('h-a'))?.localId, 'a');
      expect(await db.mediaDao.byLocalId('missing'), isNull);
    });

    test('byLocalIds returns existing rows keyed by localId', () async {
      await db.mediaDao.upsertAll([
        media(localId: 'a').toCompanion(),
        media(localId: 'b', album: 'Camera').toCompanion(),
      ]);

      final rows = await db.mediaDao.byLocalIds(['a', 'b', 'missing']);
      expect(rows.keys.toSet(), {'a', 'b'});
      expect(rows['a']?.localId, 'a');
      expect(rows['b']?.albumName, 'Camera');
    });

    test('albumNames returns distinct non-null albums', () async {
      await db.mediaDao.upsertAll([
        media(localId: 'a', album: 'Camera').toCompanion(),
        media(localId: 'b', album: 'Camera').toCompanion(),
        media(localId: 'c', album: 'Screenshots').toCompanion(),
        media(localId: 'd').toCompanion(),
      ]);

      final names = await db.mediaDao.albumNames();
      expect(names.toSet(), {'Camera', 'Screenshots'});
    });

    test('upsert replaces existing row by primary key', () async {
      await db.mediaDao.upsert(
        media(localId: 'a', album: 'Camera').toCompanion(),
      );
      final first = await db.mediaDao.byLocalId('a');

      // Re-upsert with the same primary key id but a changed album; the
      // mapper includes the id when non-null, so this updates in place.
      await db.mediaDao.upsert(
        media(id: first!.id, localId: 'a', album: 'Edited').toCompanion(),
      );

      final updated = await db.mediaDao.byLocalId('a');
      expect(updated?.albumName, 'Edited');
      expect(await db.select(db.mediaItems).get(), hasLength(1));
    });
  });
}
