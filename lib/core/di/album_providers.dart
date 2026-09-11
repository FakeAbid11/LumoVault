import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/di/database_providers.dart';
import '../../features/albums/data/models/album.dart';
import '../../features/gallery/data/models/media_item.dart';

/// In-memory list of all albums, refreshed on mutations.
final albumsListProvider = FutureProvider.autoDispose<List<Album>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final rows = await db.albumDao.allAlbums();
  return rows
      .map(
        (r) => Album(
          id: r.id,
          name: r.name,
          coverId: r.coverId,
          position: r.position,
          createdAt: r.createdAt,
          updatedAt: r.updatedAt,
        ),
      )
      .toList();
});

/// Map of albumId → item count.
final albumCountsProvider = FutureProvider.autoDispose<Map<int, int>>((
  ref,
) async {
  final db = ref.watch(appDatabaseProvider);
  return db.albumDao.allAlbumCounts();
});

/// Items inside a specific album.
final albumItemsProvider = FutureProvider.autoDispose
    .family<List<MediaItem>, int>((ref, albumId) async {
      final db = ref.watch(appDatabaseProvider);
      final rows = await db.albumDao.itemsForAlbum(albumId);
      return rows
          .map(
            (r) => MediaItem(
              id: r.id,
              localId: r.localId,
              fileHash: r.fileHash,
              telegramMessageId: r.telegramMessageId,
              telegramFileId: r.telegramFileId,
              filePath: r.filePath,
              fileName: r.fileName,
              mimeType: r.mimeType,
              fileSize: r.fileSize,
              width: r.width,
              height: r.height,
              durationMs: r.durationMs,
              createdAt: r.createdAt,
              modifiedAt: r.modifiedAt,
              scannedAt: r.scannedAt,
              uploadedAt: r.uploadedAt,
              backedUpAt: r.backedUpAt,
              status: MediaStatus.values[r.status],
              errorMessage: r.errorMessage,
              isFavorite: r.isFavorite,
              isHidden: r.isHidden,
              isArchived: r.isArchived,
              isTrashed: r.isTrashed,
              trashedAt: r.trashedAt,
              isExcluded: r.isExcluded,
              albumName: r.albumName,
              deviceFolder: r.deviceFolder,
              description: r.description,
              tags: r.tags,
              aiLabels: r.aiLabels,
              thumbnailPath: r.thumbnailPath,
              latitude: r.latitude,
              longitude: r.longitude,
              isLocationUserSet: r.isLocationUserSet,
            ),
          )
          .toList();
    });

/// Which album IDs a media item belongs to.
final mediaAlbumsProvider = FutureProvider.autoDispose
    .family<List<int>, String>((ref, mediaId) async {
      final db = ref.watch(appDatabaseProvider);
      return db.albumDao.albumsForMedia(mediaId);
    });

class AlbumActions {
  AlbumActions(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  Future<int> createAlbum(String name) async {
    final id = await _db.albumDao.createAlbum(name);
    _ref.invalidate(albumsListProvider);
    _ref.invalidate(albumCountsProvider);
    return id;
  }

  Future<void> renameAlbum(int albumId, String newName) async {
    await _db.albumDao.renameAlbum(albumId, newName);
    _ref.invalidate(albumsListProvider);
  }

  Future<void> deleteAlbum(int albumId) async {
    await _db.albumDao.deleteAlbum(albumId);
    _ref.invalidate(albumsListProvider);
    _ref.invalidate(albumCountsProvider);
  }

  Future<void> addToAlbum(int albumId, String mediaId) async {
    await _db.albumDao.addToAlbum(albumId, mediaId);
    await _db.albumDao.updateAutoCover(albumId);
    _ref.invalidate(albumCountsProvider);
    _ref.invalidate(albumItemsProvider(albumId));
    _ref.invalidate(mediaAlbumsProvider(mediaId));
  }

  Future<void> addToAlbumBatch(int albumId, List<String> mediaIds) async {
    await _db.albumDao.addToAlbumBatch(albumId, mediaIds);
    await _db.albumDao.updateAutoCover(albumId);
    _ref.invalidate(albumCountsProvider);
    _ref.invalidate(albumItemsProvider(albumId));
    for (final id in mediaIds) {
      _ref.invalidate(mediaAlbumsProvider(id));
    }
  }

  Future<void> removeFromAlbum(int albumId, String mediaId) async {
    await _db.albumDao.removeFromAlbum(albumId, mediaId);
    await _db.albumDao.updateAutoCover(albumId);
    _ref.invalidate(albumCountsProvider);
    _ref.invalidate(albumItemsProvider(albumId));
    _ref.invalidate(mediaAlbumsProvider(mediaId));
  }
}

final albumActionsProvider = Provider<AlbumActions>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return AlbumActions(db, ref);
});
