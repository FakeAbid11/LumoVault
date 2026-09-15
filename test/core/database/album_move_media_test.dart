import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/core/database/media_item_mapper.dart';
import 'package:lumovault/core/di/database_providers.dart';
import 'package:lumovault/core/di/album_providers.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';

MediaItem _media(String localId) => MediaItem(
  localId: localId,
  fileHash: 'h-$localId',
  filePath: '/p/$localId',
  fileName: '$localId.jpg',
  mimeType: 'image/jpeg',
  fileSize: 1,
  width: 1,
  height: 1,
  createdAt: DateTime(2026, 1, 1),
  modifiedAt: DateTime(2026, 1, 1),
  scannedAt: DateTime(2026, 1, 1),
);

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
  });

  group('AlbumActions.moveMedia', () {
    test('moves membership from source to destination', () async {
      final actions = container.read(albumActionsProvider);
      await db.mediaDao.upsert(_media('m1').toCompanion());
      final albumA = await actions.createAlbum('A');
      final albumB = await actions.createAlbum('B');
      await actions.addToAlbum(albumA, 'm1');

      await actions.moveMedia(
        fromAlbumId: albumA,
        toAlbumId: albumB,
        mediaId: 'm1',
      );

      expect(await db.albumDao.albumsForMedia('m1'), [albumB]);
      final counts = await db.albumDao.allAlbumCounts();
      expect(counts[albumA] ?? 0, 0);
      expect(counts[albumB] ?? 0, 1);
    });

    test('repairs covers that pointed at the moved photo', () async {
      final actions = container.read(albumActionsProvider);
      await db.mediaDao.upsert(_media('m1').toCompanion());
      final albumA = await actions.createAlbum('A');
      final albumB = await actions.createAlbum('B');
      await actions.addToAlbum(albumA, 'm1');

      // A's cover points at m1 (simulate: set directly).
      await db.albumDao.setCover(albumA, 'm1');

      await actions.moveMedia(
        fromAlbumId: albumA,
        toAlbumId: albumB,
        mediaId: 'm1',
      );

      final albums = await db.albumDao.allAlbums();
      final a = albums.firstWhere((r) => r.id == albumA);
      final b = albums.firstWhere((r) => r.id == albumB);
      // Source cover repaired (m1 is gone from A): with no remaining items
      // the cover must be null, not a dangling pointer.
      expect(a.coverId, isNull);
      // Destination cover points at the moved photo.
      expect(b.coverId, 'm1');
    });

    test('same-source-and-target move is a no-op', () async {
      final actions = container.read(albumActionsProvider);
      await db.mediaDao.upsert(_media('m1').toCompanion());
      final albumA = await actions.createAlbum('A');
      await actions.addToAlbum(albumA, 'm1');

      await actions.moveMedia(
        fromAlbumId: albumA,
        toAlbumId: albumA,
        mediaId: 'm1',
      );

      expect(await db.albumDao.albumsForMedia('m1'), [albumA]);
    });
  });
}
