import 'package:drift/drift.dart';

import '../app_database.dart';

part 'media_dao.g.dart';

/// Data-access object for the `MediaItems` table.
///
/// This is the query surface the drift-backed `GalleryRepository` rewrite will
/// consume. It is intentionally additive: nothing in the app calls it yet, so
/// adding it does not change existing behaviour. Methods here return raw
/// [MediaItemRow]s; translation to the `MediaItem` domain model happens via the
/// mappers in `media_item_mapper.dart`.
@DriftAccessor(tables: [MediaItems])
class MediaDao extends DatabaseAccessor<AppDatabase> with _$MediaDaoMixin {
  MediaDao(super.db);

  /// Timeline: all non-trashed, non-hidden items, newest first.
  Future<List<MediaItemRow>> timeline() {
    return (select(mediaItems)
          ..where((t) => t.isTrashed.equals(false) & t.isHidden.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// A single page of the timeline.
  Future<List<MediaItemRow>> timelinePage({
    required int limit,
    required int offset,
  }) {
    return (select(mediaItems)
          ..where((t) => t.isTrashed.equals(false) & t.isHidden.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Items belonging to a device folder / album, newest first.
  Future<List<MediaItemRow>> byAlbum(String albumName) {
    return (select(mediaItems)
          ..where(
            (t) => t.albumName.equals(albumName) & t.isTrashed.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Favorited items, newest first.
  Future<List<MediaItemRow>> favorites() {
    return (select(mediaItems)
          ..where((t) => t.isFavorite.equals(true) & t.isTrashed.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Trashed items, most recently trashed first.
  Future<List<MediaItemRow>> trashed() {
    return (select(mediaItems)
          ..where((t) => t.isTrashed.equals(true))
          ..orderBy([(t) => OrderingTerm.desc(t.trashedAt)]))
        .get();
  }

  /// Case-insensitive search over file name and description.
  Future<List<MediaItemRow>> search(String query) {
    final like = '%${query.toLowerCase()}%';
    return (select(mediaItems)
          ..where(
            (t) =>
                (t.isTrashed.equals(false)) &
                (t.fileName.lower().like(like) |
                    t.description.lower().like(like)),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Look up by stable platform media id.
  Future<MediaItemRow?> byLocalId(String localId) {
    return (select(
      mediaItems,
    )..where((t) => t.localId.equals(localId))).getSingleOrNull();
  }

  /// Look up by content hash (dedup check).
  Future<MediaItemRow?> byHash(String fileHash) {
    return (select(
      mediaItems,
    )..where((t) => t.fileHash.equals(fileHash))).getSingleOrNull();
  }

  /// Distinct album / device-folder names present in the library.
  Future<List<String>> albumNames() async {
    final query = selectOnly(mediaItems, distinct: true)
      ..addColumns([mediaItems.albumName])
      ..where(
        mediaItems.albumName.isNotNull() & mediaItems.isTrashed.equals(false),
      );
    final rows = await query.get();
    return rows
        .map((r) => r.read(mediaItems.albumName))
        .whereType<String>()
        .toList();
  }

  /// All rows, newest first. Used to hydrate the in-memory read model on
  /// startup.
  Future<List<MediaItemRow>> all() {
    return (select(
      mediaItems,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
  }

  /// Insert or replace by primary key. Returns the row id.
  Future<int> upsert(MediaItemsCompanion companion) {
    return into(mediaItems).insertOnConflictUpdate(companion);
  }

  /// Batch upsert used by the scanner (single transaction).
  Future<void> upsertAll(List<MediaItemsCompanion> companions) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(mediaItems, companions);
    });
  }

  /// Replace the entire table contents in a single transaction.
  ///
  /// Mirrors the in-memory `clear() + addAll()` semantics of a full device
  /// rescan: the freshly scanned items become the complete persisted set.
  /// Companions are expected to have an absent primary key so autoincrement
  /// assigns fresh ids.
  Future<void> replaceAll(List<MediaItemsCompanion> companions) async {
    await transaction(() async {
      await delete(mediaItems).go();
      await batch((b) => b.insertAll(mediaItems, companions));
    });
  }

  /// Apply a partial update to the row identified by [localId].
  ///
  /// Used by metadata mutations (favorite/hidden/archive/trash toggles) to
  /// persist a single changed field without rewriting the whole row. Returns
  /// the number of rows affected.
  Future<int> updateByLocalId(String localId, MediaItemsCompanion changes) {
    return (update(
      mediaItems,
    )..where((t) => t.localId.equals(localId))).write(changes);
  }

  /// Delete rows for items no longer present on the device, as detected by
  /// an incremental scan. No-op for an empty list.
  Future<void> deleteByLocalIds(List<String> localIds) async {
    if (localIds.isEmpty) return;
    await (delete(mediaItems)..where((t) => t.localId.isIn(localIds))).go();
  }
}
