import 'package:drift/drift.dart';

import '../app_database.dart';

part 'album_dao.g.dart';

class DeviceFolderAlbum {
  const DeviceFolderAlbum({
    required this.name,
    this.folder,
    required this.count,
    this.coverId,
  });

  final String name;
  final String? folder;
  final int count;
  final String? coverId;
}

@DriftAccessor(tables: [Albums, AlbumItems, MediaItems])
class AlbumDao extends DatabaseAccessor<AppDatabase> with _$AlbumDaoMixin {
  AlbumDao(super.db);

  Future<int> createAlbum(String name) async {
    final now = DateTime.now();
    return into(albums).insert(
      AlbumsCompanion.insert(name: name, createdAt: now, updatedAt: now),
    );
  }

  Future<void> renameAlbum(int albumId, String newName) async {
    await (update(albums)..where((t) => t.id.equals(albumId))).write(
      AlbumsCompanion(name: Value(newName), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> deleteAlbum(int albumId) async {
    await (delete(albumItems)..where((t) => t.albumId.equals(albumId))).go();
    await (delete(albums)..where((t) => t.id.equals(albumId))).go();
  }

  Future<void> reorderAlbum(int albumId, int newPosition) async {
    await (update(albums)..where((t) => t.id.equals(albumId))).write(
      AlbumsCompanion(
        position: Value(newPosition),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setCover(int albumId, String? mediaId) async {
    await (update(albums)..where((t) => t.id.equals(albumId))).write(
      AlbumsCompanion(
        coverId: Value(mediaId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> addToAlbum(int albumId, String mediaId) async {
    await into(albumItems).insertOnConflictUpdate(
      AlbumItemsCompanion.insert(
        albumId: albumId,
        mediaId: mediaId,
        addedAt: DateTime.now(),
      ),
    );
  }

  Future<void> addToAlbumBatch(int albumId, List<String> mediaIds) async {
    final now = DateTime.now();
    await batch((b) {
      b.insertAll(
        albumItems,
        mediaIds
            .map(
              (id) => AlbumItemsCompanion.insert(
                albumId: albumId,
                mediaId: id,
                addedAt: now,
              ),
            )
            .toList(),
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> removeFromAlbum(int albumId, String mediaId) async {
    await (delete(albumItems)
          ..where((t) => t.albumId.equals(albumId) & t.mediaId.equals(mediaId)))
        .go();
  }

  Future<List<AlbumRow>> allAlbums() {
    return (select(
      albums,
    )..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
  }

  Future<AlbumRow?> albumById(int albumId) {
    return (select(
      albums,
    )..where((t) => t.id.equals(albumId))).getSingleOrNull();
  }

  Future<int> albumItemCount(int albumId) async {
    final query = selectOnly(albumItems)
      ..addColumns([albumItems.mediaId.count()])
      ..where(albumItems.albumId.equals(albumId));
    final result = await query.getSingle();
    return result.read(albumItems.mediaId.count()) ?? 0;
  }

  Future<Map<int, int>> allAlbumCounts() async {
    final query = selectOnly(
      albumItems,
    ).join([innerJoin(albums, albums.id.equalsExp(albumItems.albumId))]);
    final rows = await query.get();
    final counts = <int, int>{};
    for (final row in rows) {
      final aId = row.readTable(albumItems).albumId;
      counts[aId] = (counts[aId] ?? 0) + 1;
    }
    return counts;
  }

  Future<List<String>> albumMediaIds(int albumId) async {
    final rows = await (select(
      albumItems,
    )..where((t) => t.albumId.equals(albumId))).get();
    return rows.map((r) => r.mediaId).toList();
  }

  Future<bool> isInAlbum(int albumId, String mediaId) async {
    final row =
        await (select(albumItems)
              ..where(
                (t) => t.albumId.equals(albumId) & t.mediaId.equals(mediaId),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<List<int>> albumsForMedia(String mediaId) async {
    final rows = await (select(
      albumItems,
    )..where((t) => t.mediaId.equals(mediaId))).get();
    return rows.map((r) => r.albumId).toList();
  }

  Future<List<DeviceFolderAlbum>> deviceFolderAlbums() async {
    final query = selectOnly(mediaItems)
      ..addColumns([
        mediaItems.albumName,
        mediaItems.deviceFolder,
        mediaItems.localId.count(),
        mediaItems.localId.min(),
      ])
      ..where(
        mediaItems.albumName.isNotNull() &
            mediaItems.isTrashed.equals(false) &
            mediaItems.isHidden.equals(false),
      )
      ..groupBy([mediaItems.albumName])
      ..orderBy([OrderingTerm.desc(mediaItems.localId.count())]);

    final rows = await query.get();
    return rows.map((row) {
      return DeviceFolderAlbum(
        name: row.read(mediaItems.albumName)!,
        folder: row.read(mediaItems.deviceFolder),
        count: row.read(mediaItems.localId.count())!,
        coverId: row.read(mediaItems.localId.min()),
      );
    }).toList();
  }

  Future<List<MediaItemRow>> itemsForDeviceFolder(String albumName) async {
    return (select(mediaItems)
          ..where(
            (t) =>
                t.albumName.equals(albumName) &
                t.isTrashed.equals(false) &
                t.isHidden.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<void> updateAutoCover(int albumId) async {
    final newest =
        await (select(mediaItems)
              ..where(
                (t) => t.isTrashed.equals(false) & t.isHidden.equals(false),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(1))
            .get();

    if (newest.isNotEmpty) {
      await setCover(albumId, newest.first.localId);
    } else {
      await setCover(albumId, null);
    }
  }

  Future<List<MediaItemRow>> itemsForAlbum(int albumId) async {
    final query =
        select(mediaItems).join([
            innerJoin(
              albumItems,
              albumItems.mediaId.equalsExp(mediaItems.localId),
            ),
          ])
          ..where(albumItems.albumId.equals(albumId))
          ..orderBy([OrderingTerm.desc(albumItems.addedAt)]);

    final rows = await query.get();
    return rows.map((r) => r.readTable(mediaItems)).toList();
  }
}
