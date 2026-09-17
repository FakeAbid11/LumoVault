import 'package:drift/drift.dart';

import '../app_database.dart';

part 'album_dao.g.dart';

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

  /// Removes album memberships for deleted media and repairs covers that
  /// pointed at any of them (each falls back to the album's own newest
  /// remaining item). Without this, permanently deleting media left
  /// dangling album_items rows (inflating counts) and stale cover pointers.
  Future<void> detachMediaFromAlbums(List<String> mediaIds) async {
    if (mediaIds.isEmpty) return;
    await (delete(albumItems)..where((t) => t.mediaId.isIn(mediaIds))).go();

    final albums = await allAlbums();
    for (final album in albums) {
      final cover = album.coverId;
      if (cover != null && mediaIds.contains(cover)) {
        await updateAutoCover(album.id);
      }
    }
  }

  Future<void> addToAlbum(int albumId, String mediaId) async {
    // insertOrReplace, NOT insertOnConflictUpdate: AlbumItems has no primary
    // key (only the composite unique albumId+mediaId), and drift's
    // conflict-update insert throws "Table has no primary key" without an
    // explicit target — which made every "Add to album" fail silently.
    await into(albumItems).insert(
      AlbumItemsCompanion.insert(
        albumId: albumId,
        mediaId: mediaId,
        addedAt: DateTime.now(),
      ),
      mode: InsertMode.insertOrReplace,
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
    // Grouped count. The previous version used selectOnly(...).join(...)
    // WITHOUT addColumns, generating `SELECT FROM album_items ...` — invalid
    // SQL that threw on every call, silently falling back to zero counts on
    // the Albums tab.
    final countExp = albumItems.mediaId.count();
    final query = selectOnly(albumItems)
      ..addColumns([albumItems.albumId, countExp])
      ..groupBy([albumItems.albumId]);
    final rows = await query.get();
    final counts = <int, int>{};
    for (final row in rows) {
      counts[row.read(albumItems.albumId)!] = row.read(countExp) ?? 0;
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

  Future<void> updateAutoCover(int albumId) async {
    // The cover must come from THIS album's own items — the query used to
    // have no album predicate at all, so every album mutation set every
    // album's cover to the globally newest photo in the library.
    final items = await itemsForAlbum(albumId);
    if (items.isEmpty) {
      await setCover(albumId, null);
      return;
    }
    final newest = items.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    await setCover(albumId, newest.localId);
  }
}
