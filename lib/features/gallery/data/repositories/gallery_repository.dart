import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/database/daos/media_dao.dart';
import '../../../../core/database/media_item_mapper.dart';
import '../models/media_item.dart';
import '../models/device_folder.dart';
import 'incremental_scanner.dart';
import 'media_scanner_service.dart';

/// Callback type for metadata change notifications.
typedef MetadataChangeCallback =
    void Function({
      required String localId,
      required String operation,
      MediaItem? item,
    });

/// Callback that propagates a permanent deletion to the storage channel.
///
/// Given the Telegram message ids of the items being permanently deleted, it
/// revokes those channel messages for all members. Optional and injected at
/// bootstrap; null in tests and in the in-memory-only configuration, where no
/// channel exists to delete from. Kept as a callback (rather than a direct
/// [DeletionService] dependency) so [GalleryRepository] stays free of any
/// TDLib types, exactly like [MetadataChangeCallback].
typedef RemoteDeleteCallback =
    Future<void> Function(List<int> telegramMessageIds);

/// In-memory read model for the gallery, backed by optional drift persistence.
///
/// The `List<MediaItem>` remains the authoritative source for the synchronous
/// read API that the UI, backup, restore, and diagnostics layers depend on.
/// When a [MediaDao] is supplied, every mutation is additionally written
/// through to the database so state survives restarts; on startup [hydrate]
/// repopulates the in-memory list from the database. When no DAO is supplied
/// (e.g. in unit tests) the repository behaves exactly as the previous
/// in-memory-only implementation.
class GalleryRepository {
  GalleryRepository({
    required this._scannerService,
    this._mediaDao,
    IncrementalScanner? incrementalScanner,
  }) : _incrementalScanner = incrementalScanner ?? IncrementalScanner();

  final MediaScannerService _scannerService;
  final MediaDao? _mediaDao;
  final IncrementalScanner _incrementalScanner;

  final List<MediaItem> _mediaItems = [];
  final List<DeviceFolder> _folders = [];

  /// localId → position in [_mediaItems], so per-item lookups are O(1) instead
  /// of an O(n) `indexWhere` on every toggle/mark. Kept in step with the list:
  /// [_rebuildIndex] after any structural change (sort/clear/removeWhere), and
  /// updated in place for appends. In-place `_mediaItems[i] = …` replacements
  /// keep the same localId at the same position, so they need no upkeep. A
  /// full restore that calls [markUploaded] per item was previously O(n²).
  final Map<String, int> _indexByLocalId = {};

  /// In-memory cache of resolved GPS coordinates: asset ID → (lat, lng).
  /// Populated lazily on first map visit; survives across tab switches
  /// within the same app session.
  final Map<String, (double, double)> _locationCache = {};

  /// Get the location cache for read-only access (e.g. by map providers).
  Map<String, (double, double)> get locationCache => _locationCache;

  /// Check if a location is already cached for the given asset ID.
  bool isLocationCached(String assetId) => _locationCache.containsKey(assetId);

  /// Cache a resolved location for an asset.
  void cacheLocation(String assetId, double lat, double lng) {
    _locationCache[assetId] = (lat, lng);
  }

  /// Get a cached location, or null if not cached.
  (double, double)? getCachedLocation(String assetId) =>
      _locationCache[assetId];

  MetadataChangeCallback? _onMetadataChange;

  /// Propagates permanent deletions to the storage channel. Null until wired
  /// at bootstrap (and in tests); see [RemoteDeleteCallback].
  RemoteDeleteCallback? _onRemoteDelete;

  /// O(1) position of [localId] in [_mediaItems], or -1 if absent.
  int _indexOfLocalId(String localId) => _indexByLocalId[localId] ?? -1;

  /// Rebuild [_indexByLocalId] from scratch. Call after any change that moves
  /// existing items (sort) or removes them (clear/removeWhere).
  void _rebuildIndex() {
    _indexByLocalId.clear();
    for (var i = 0; i < _mediaItems.length; i++) {
      _indexByLocalId[_mediaItems[i].localId] = i;
    }
  }

  /// Set a callback for metadata changes.
  ///
  /// This allows the metadata system to hook into state changes
  /// without creating a circular dependency.
  void setMetadataChangeCallback(MetadataChangeCallback? callback) {
    _onMetadataChange = callback;
  }

  /// Wire the storage-channel deletion propagation. Called once at bootstrap;
  /// see [RemoteDeleteCallback].
  void setRemoteDeleteCallback(RemoteDeleteCallback? callback) {
    _onRemoteDelete = callback;
  }

  UnmodifiableListView<MediaItem> get mediaItems =>
      UnmodifiableListView(_mediaItems);

  UnmodifiableListView<DeviceFolder> get folders =>
      UnmodifiableListView(_folders);

  int get totalCount => _mediaItems.length;

  /// Load the persisted media set into the in-memory read model.
  ///
  /// No-op when the repository was constructed without a database (tests).
  /// Called once during app bootstrap before the first timeline read.
  /// Trash items past their retention window are purged on the way through
  /// (the "permanently deleted after N days" promise from the trash screen).
  Future<void> hydrate() async {
    final dao = _mediaDao;
    if (dao == null) return;

    final rows = await dao.all();
    _mediaItems
      ..clear()
      ..addAll(rows.map((r) => r.toDomain()));
    _mediaItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _rebuildIndex();

    await purgeExpiredTrashedItems();
  }

  Future<bool> requestPermission() async {
    return _scannerService.requestPermission();
  }

  Future<bool> checkPermission() async {
    return _scannerService.checkPermission();
  }

  Future<ScanResult> scanDevice({
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
  }) async {
    final result = await _scannerService.scanDevice(
      includedFolders: includedFolders,
      onProgress: onProgress,
    );

    // A full rescan sees every file as freshly-built (default metadata), so
    // merge each item against its previous record before replacing — a
    // rescan must not silently wipe the user's hidden/favorite/trash/backup
    // selections.
    final previous = {for (final item in _mediaItems) item.localId: item};
    _mediaItems.clear();
    for (final item in result.mediaItems) {
      final existing = previous[item.localId];
      _mediaItems.add(
        existing == null ? item : _carryForwardMetadata(existing, item),
      );
    }

    _folders.clear();
    _folders.addAll(result.folders);

    _mediaItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _rebuildIndex();

    // Persist the freshly scanned set, replacing any previous contents so the
    // database mirrors the in-memory read model.
    await _mediaDao?.replaceAll(
      _mediaItems.map((item) => item.toCompanion()).toList(),
    );

    // Notify with the MERGED records, not result.mediaItems.
    //
    // result.mediaItems are freshly-built scan objects carrying default flags
    // (isFavorite/isHidden/isArchived false, no album/description/tags). The
    // merge above is what restores the user's real state, so notifying from
    // the raw scan output reported every user flag as its default and let the
    // synced metadata manifest overwrite genuine user state with blanks.
    for (final item in _mediaItems) {
      _notifyMetadataChange(
        localId: item.localId,
        operation: 'scan_discover',
        item: item,
      );
    }

    return result;
  }

  /// Scan for changes since the last known set instead of re-reading and
  /// re-hashing every file on the device.
  ///
  /// [scanDevice] always re-scans and re-hashes the full device library —
  /// fine for the very first scan, but calling it on every app launch (as
  /// the timeline screen used to) means reading and MD5-hashing the full
  /// bytes of every photo and video again each time, which is both slow and
  /// makes progress restart from zero every launch instead of resuming.
  /// This compares against the already-hydrated in-memory set and only
  /// processes items that are new or whose modified timestamp changed.
  Future<IncrementalScanResult> scanDeviceIncremental({
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
  }) async {
    final lastKnownItems = {for (final item in _mediaItems) item.localId: item};

    final result = await _incrementalScanner.scanForChanges(
      lastKnownItems: lastKnownItems,
      includedFolders: includedFolders,
      onProgress: onProgress,
      // Flush every batch to the database as the scan runs. Previously
      // everything was only persisted once the whole scan finished, so a
      // slow first scan that got interrupted — or that the user closed the
      // app during — saved nothing at all and restarted from item 1 next
      // launch, no matter how far it had actually gotten.
      onBatch: (newBatch, updatedBatch) {
        final merged = _mergeIntoMemory(newBatch, updatedBatch);
        // Chain batches instead of firing them off independently. Each batch
        // does a read (dao.byLocalIds) before its write, so overlapping
        // batches could interleave read/write and upsert a stale row id.
        // Errors are logged rather than rethrown: a failed flush costs this
        // batch's persistence, but aborting the scan would lose the rest too.
        _pendingBatchWrites = _pendingBatchWrites
            .then((_) => _persistBatch(merged))
            .catchError((Object error, StackTrace stackTrace) {
              debugPrint(
                '[GalleryRepository] Batch persist failed for '
                '${merged.length} item(s): $error',
              );
              debugPrint('$stackTrace');
            });
      },
    );

    // The final _persistBatch below must not race the in-flight batch writes
    // queued above.
    await _pendingBatchWrites;

    // The batches above already covered everything scanForChanges found, so
    // this is a no-op for items already flushed — it only picks up the
    // (rare) remainder smaller than one batch. indexWhere-based merging and
    // dao.upsertAll are both idempotent, so re-applying is harmless.
    final mergedItems = _mergeIntoMemory(result.newItems, result.updatedItems);

    if (result.deletedIds.isNotEmpty) {
      final deleted = result.deletedIds.toSet();
      _mediaItems.removeWhere((item) => deleted.contains(item.localId));
    }

    _mediaItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _rebuildIndex();

    // Folder metadata is cheap (counts only, no file reads) so it's still
    // refreshed in full on every scan.
    _folders.clear();
    _folders.addAll(await _scannerService.getDeviceFolders());

    final dao = _mediaDao;
    if (dao != null) {
      await _persistBatch(mergedItems);
      if (result.deletedIds.isNotEmpty) {
        await dao.deleteByLocalIds(result.deletedIds);
      }
    }

    // Notify with the merged in-memory records rather than the raw scan
    // output, for the same reason as [scanDevice]: result.newItems and
    // result.updatedItems carry default user flags, and _mergeIntoMemory (via
    // _carryForwardMetadata) is what reconciles them with the user's real
    // state. Notifying from the raw lists reported favorites, hidden, archive,
    // album, description and tags as defaults.
    //
    // Looked up by localId because the batches above already merged most of
    // these — the authoritative record is the one now in _mediaItems.
    final mergedById = {for (final item in _mediaItems) item.localId: item};

    for (final item in result.newItems) {
      _notifyMetadataChange(
        localId: item.localId,
        operation: 'scan_discover',
        item: mergedById[item.localId] ?? item,
      );
    }
    for (final item in result.updatedItems) {
      _notifyMetadataChange(
        localId: item.localId,
        operation: 'scan_update',
        item: mergedById[item.localId] ?? item,
      );
    }
    for (final id in result.deletedIds) {
      _notifyMetadataChange(localId: id, operation: 'scan_delete', item: null);
    }

    return result;
  }

  /// Merge a batch of new/updated items into the in-memory list, replacing
  /// by [MediaItem.localId] when already present — carrying the previous
  /// record's user metadata forward so a rescan never wipes it. Returns the
  /// merged records so the caller persists exactly what ended up in memory.
  /// Idempotent — safe to call more than once with overlapping items.
  List<MediaItem> _mergeIntoMemory(
    List<MediaItem> newBatch,
    List<MediaItem> updatedBatch,
  ) {
    final merged = <MediaItem>[];
    for (final item in [...newBatch, ...updatedBatch]) {
      final index = _indexOfLocalId(item.localId);
      if (index != -1) {
        final carried = _carryForwardMetadata(_mediaItems[index], item);
        _mediaItems[index] = carried;
        merged.add(carried);
      } else {
        _mediaItems.add(item);
        _indexByLocalId[item.localId] = _mediaItems.length - 1;
        merged.add(item);
      }
    }
    return merged;
  }

  /// Merge a freshly scanned item with the metadata of the item it replaces.
  ///
  /// Device-derived fields (hash, path, size, dates, album) come from the
  /// fresh scan. User state — favorite, hidden, archive, trash, backup
  /// selection, description, tags — is carried over from the previous
  /// record. Upload state (status, Telegram ids, timestamps, error) survives
  /// only while the content hash is unchanged: an edited file is new content
  /// that must be re-uploaded, so its stale "uploaded" badge must not stick
  /// around.
  MediaItem _carryForwardMetadata(MediaItem existing, MediaItem fresh) {
    final hashChanged = existing.fileHash != fresh.fileHash;
    return fresh.copyWith(
      id: existing.id,
      isFavorite: existing.isFavorite,
      isHidden: existing.isHidden,
      isArchived: existing.isArchived,
      isTrashed: existing.isTrashed,
      trashedAt: existing.trashedAt,
      isExcluded: existing.isExcluded,
      description: existing.description,
      tags: existing.tags,
      aiLabels: existing.aiLabels,
      status: hashChanged ? null : existing.status,
      telegramMessageId: hashChanged ? null : existing.telegramMessageId,
      telegramFileId: hashChanged ? null : existing.telegramFileId,
      uploadedAt: hashChanged ? null : existing.uploadedAt,
      backedUpAt: hashChanged ? null : existing.backedUpAt,
      errorMessage: hashChanged ? null : existing.errorMessage,
      // Preserve user-set coordinates through rescans. EXIF-derived
      // coordinates are always overwritten by the fresh scan (the default
      // when isLocationUserSet is false).
      latitude: existing.isLocationUserSet ? existing.latitude : fresh.latitude,
      longitude: existing.isLocationUserSet
          ? existing.longitude
          : fresh.longitude,
      isLocationUserSet: existing.isLocationUserSet,
    );
  }

  /// Serializes the incremental scan's per-batch database writes.
  ///
  /// [scanDeviceIncremental] flushes each batch as the scan runs so an
  /// interrupted scan keeps its progress. Those flushes used to be
  /// fire-and-forget, which let two batches interleave their read-then-write
  /// against the same rows and discarded any error entirely.
  Future<void> _pendingBatchWrites = Future<void>.value();

  /// Persist a batch of items to the database. No-op without a DAO (e.g. in
  /// unit tests) or for an empty batch.
  ///
  /// Callers pass the records that were actually merged into memory (see
  /// [_mergeIntoMemory]), so user metadata carried forward by a rescan is
  /// what lands in the database, not the scanner's default flags.
  ///
  /// Scanned items never carry their database-assigned `id` back into
  /// memory, so a companion built straight from one would upsert with an
  /// absent primary key. `insertOnConflictUpdate` only treats the `id`
  /// column as its conflict target, so when a row with the same `localId`
  /// already exists the insert collides with the `localId` unique
  /// constraint and the whole batch throws. Existing row ids are looked up
  /// and carried forward here, making the upsert update the correct row.
  Future<void> _persistBatch(List<MediaItem> items) async {
    final dao = _mediaDao;
    if (dao == null) return;
    if (items.isEmpty) return;

    final missingIds = items
        .where((item) => item.id == null)
        .map((item) => item.localId)
        .toList();
    final existingById = await dao.byLocalIds(missingIds);
    final toPersist = items.map((item) {
      if (item.id != null) return item;
      final existing = existingById[item.localId];
      return existing == null ? item : item.copyWith(id: existing.id);
    }).toList();

    await dao.upsertAll(toPersist.map((item) => item.toCompanion()).toList());
  }

  /// Timeline items, newest first.
  ///
  /// Hidden and trashed items are excluded by default — they only surface
  /// through [getHiddenItems]/[getTrashedItems] (or an explicit filter
  /// parameter below). This mirrors [MediaDao.timeline].
  List<MediaItem> getTimelineItems({
    DateTime? startDate,
    DateTime? endDate,
    bool? isFavorite,
    bool? isHidden,
    bool? isArchived,
    bool? isTrashed,
  }) {
    return _mediaItems.where((item) {
      if (startDate != null && item.createdAt.isBefore(startDate)) return false;
      if (endDate != null && item.createdAt.isAfter(endDate)) return false;
      if (isFavorite != null && item.isFavorite != isFavorite) return false;
      if (isHidden != null && item.isHidden != isHidden) return false;
      if (isArchived != null && item.isArchived != isArchived) return false;
      if (isTrashed != null && item.isTrashed != isTrashed) return false;
      if (isHidden == null && item.isHidden) return false;
      if (isTrashed == null && item.isTrashed) return false;
      return true;
    }).toList();
  }

  List<MediaItem> getAlbumItems(String albumName) {
    return _mediaItems
        .where(
          (item) =>
              item.albumName == albumName && !item.isHidden && !item.isTrashed,
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<MediaItem> getFavoriteItems() {
    return _mediaItems
        .where((item) => item.isFavorite && !item.isHidden && !item.isTrashed)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<MediaItem> searchMedia(String query) {
    final lowerQuery = query.toLowerCase();
    return _mediaItems.where((item) {
      if (item.isHidden || item.isTrashed) return false;
      return item.fileName.toLowerCase().contains(lowerQuery) ||
          (item.description?.toLowerCase().contains(lowerQuery) ?? false) ||
          (item.albumName?.toLowerCase().contains(lowerQuery) ?? false) ||
          item.tags.any((tag) => tag.toLowerCase().contains(lowerQuery)) ||
          item.aiLabels.any(
            (label) => label.toLowerCase().contains(lowerQuery),
          );
    }).toList();
  }

  Map<String, List<MediaItem>> getTimelineByDate() {
    final Map<String, List<MediaItem>> grouped = {};

    for (final item in _mediaItems) {
      if (item.isHidden || item.isTrashed) continue;
      final dateKey = _getDateKey(item.createdAt);
      grouped.putIfAbsent(dateKey, () => []).add(item);
    }

    return grouped;
  }

  String _getDateKey(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(date.year, date.month, date.day);

    if (itemDate == today) return 'Today';
    if (itemDate == today.subtract(const Duration(days: 1))) return 'Yesterday';

    return '${date.month}/${date.day}/${date.year}';
  }

  MediaItem? getItemById(String localId) {
    final index = _indexOfLocalId(localId);
    return index == -1 ? null : _mediaItems[index];
  }

  /// Include/exclude a specific photo or video from backup.
  ///
  /// Unlike [toggleFavorite]/[toggleHidden]/[toggleArchived], this works
  /// even for an asset that's never been scanned before — the timeline no
  /// longer scans everything up front, so most assets won't have a
  /// [MediaItem] record yet when the user acts on one from the viewer.
  /// In that case, [asset] is used to build one on demand (computing its
  /// real hash now, via the same path a full scan would use — the
  /// alternative, a placeholder record with no hash, would either never
  /// get properly filled in by a later scan or have this exclusion choice
  /// silently overwritten when it finally is).
  Future<void> setBackupExcluded({
    required String localId,
    required bool excluded,
    required AssetEntity asset,
  }) async {
    final index = _indexOfLocalId(localId);

    late final MediaItem updated;
    if (index != -1) {
      updated = _mediaItems[index].copyWith(isExcluded: excluded);
      _mediaItems[index] = updated;
    } else {
      final built = await _incrementalScanner.buildSingleItem(asset);
      if (built == null) return;
      updated = built.copyWith(isExcluded: excluded);
      _mediaItems.add(updated);
      _indexByLocalId[updated.localId] = _mediaItems.length - 1;
    }

    await _persistItem(updated);
    _notifyMetadataChange(
      localId: localId,
      operation: 'backup_exclusion_toggle',
      item: updated,
    );
  }

  /// Record that [localId] has finished uploading, so the timeline can
  /// show its "backed up" badge. Called by [BackupEngine] once a transfer
  /// completes — nothing previously wrote this back, so the badge that
  /// already existed in [AssetTile] had no way to ever turn green.
  Future<void> markUploaded({
    required String localId,
    String? telegramMessageId,
    String? telegramFileId,
  }) async {
    final index = _indexOfLocalId(localId);
    if (index == -1) return;

    final updated = _mediaItems[index].copyWith(
      status: MediaStatus.uploaded,
      uploadedAt: DateTime.now(),
      backedUpAt: DateTime.now(),
      telegramMessageId: telegramMessageId,
      telegramFileId: telegramFileId,
    );
    _mediaItems[index] = updated;
    await _persistItem(updated);
    _notifyMetadataChange(
      localId: localId,
      operation: 'uploaded',
      item: updated,
    );
  }

  Future<void> toggleFavorite(String localId) async {
    final index = _indexOfLocalId(localId);
    if (index != -1) {
      final updated = _mediaItems[index].copyWith(
        isFavorite: !_mediaItems[index].isFavorite,
      );
      _mediaItems[index] = updated;
      await _persistItem(updated);
      _notifyMetadataChange(
        localId: localId,
        operation: 'favorite_toggle',
        item: updated,
      );
    }
  }

  Future<void> toggleHidden(String localId) async {
    final index = _indexOfLocalId(localId);
    if (index != -1) {
      final updated = _mediaItems[index].copyWith(
        isHidden: !_mediaItems[index].isHidden,
      );
      _mediaItems[index] = updated;
      await _persistItem(updated);
      _notifyMetadataChange(
        localId: localId,
        operation: 'hidden_toggle',
        item: updated,
      );
    }
  }

  Future<void> toggleArchived(String localId) async {
    final index = _indexOfLocalId(localId);
    if (index != -1) {
      final updated = _mediaItems[index].copyWith(
        isArchived: !_mediaItems[index].isArchived,
      );
      _mediaItems[index] = updated;
      await _persistItem(updated);
      _notifyMetadataChange(
        localId: localId,
        operation: 'archive_toggle',
        item: updated,
      );
    }
  }

  /// Set (or remove) the GPS coordinates for a media item.
  ///
  /// When [latitude] and [longitude] are non-null the location is marked as
  /// user-set ([isLocationUserSet] = true) so it survives future rescans.
  /// Pass null for both to clear a previously user-set location.
  Future<void> setLocation(
    String localId, {
    double? latitude,
    double? longitude,
  }) async {
    final index = _indexOfLocalId(localId);
    if (index != -1) {
      final hasLocation = latitude != null && longitude != null;
      final updated = _mediaItems[index].copyWith(
        latitude: latitude,
        longitude: longitude,
        isLocationUserSet: hasLocation,
      );
      _mediaItems[index] = updated;
      await _persistItem(updated);
      _notifyMetadataChange(
        localId: localId,
        operation: 'location_set',
        item: updated,
      );
    }
  }

  /// Persists AI-generated labels for a media item.
  ///
  /// Labels should be prefixed with `ai_` (e.g. `ai_beach`, `ai_sunset`).
  /// Only overwrites the `aiLabels` field; user tags are preserved.
  Future<void> labelMediaItem(String localId, List<String> labels) async {
    final index = _indexOfLocalId(localId);
    if (index != -1) {
      final updated = _mediaItems[index].copyWith(aiLabels: labels);
      _mediaItems[index] = updated;
      await _persistItem(updated);
    }
  }

  Future<void> moveToTrash(String localId) async {
    final index = _indexOfLocalId(localId);
    if (index != -1) {
      final updated = _mediaItems[index].copyWith(
        isTrashed: true,
        trashedAt: DateTime.now(),
      );
      _mediaItems[index] = updated;
      await _persistItem(updated);
      _notifyMetadataChange(
        localId: localId,
        operation: 'trash',
        item: updated,
      );
    }
  }

  Future<void> restoreFromTrash(String localId) async {
    final index = _indexOfLocalId(localId);
    if (index != -1) {
      final updated = _mediaItems[index].copyWith(
        isTrashed: false,
        clearTrashedAt: true,
      );

      _mediaItems[index] = updated;
      await _persistItem(updated);
      _notifyMetadataChange(
        localId: localId,
        operation: 'restore',
        item: updated,
      );
    }
  }

  /// Permanently delete an item: drop it from the in-memory read model and
  /// the database. This only removes LumoVault's records — it does not touch
  /// the file on the device (that's the OS's, and the backup copy lives in
  /// the Telegram channel). "Permanent" here means it can't be restored from
  /// trash within the app, since the trash row itself is gone.
  Future<void> deletePermanently(String localId) =>
      deletePermanentlyBatch([localId]);

  /// Bulk permanent delete — see [deletePermanently].
  ///
  /// Beyond dropping the local records, this revokes each item's copy in the
  /// storage channel (via the injected [RemoteDeleteCallback]) and lets the
  /// metadata layer write a deletion tombstone, so other devices on the same
  /// channel converge on the deletion instead of resurrecting the item. The
  /// remote revoke is best-effort: a failure is logged but never blocks the
  /// local delete, since the tombstone alone still converges peers on the next
  /// pull.
  Future<void> deletePermanentlyBatch(
    List<String> localIds, {
    bool revokeRemote = true,
  }) async {
    if (localIds.isEmpty) return;
    final ids = localIds.toSet();

    // Capture Telegram message ids BEFORE removing the records — the ids live
    // on the items, and permanent delete revokes the channel copies too.
    final messageIds = <int>[];
    for (final item in _mediaItems) {
      if (!ids.contains(item.localId)) continue;
      final mid = int.tryParse(item.telegramMessageId ?? '');
      if (mid != null && mid != 0) messageIds.add(mid);
    }

    _mediaItems.removeWhere((item) => ids.contains(item.localId));
    _rebuildIndex();
    await _mediaDao?.deleteByLocalIds(localIds);

    final remoteDelete = _onRemoteDelete;
    if (revokeRemote && remoteDelete != null && messageIds.isNotEmpty) {
      try {
        await remoteDelete(messageIds);
      } catch (e) {
        debugPrint('[GalleryRepository] Remote channel delete failed: $e');
      }
    }

    for (final id in localIds) {
      _notifyMetadataChange(localId: id, operation: 'delete', item: null);
    }
  }

  /// Permanently remove items that have been in trash for longer than
  /// [retentionDays] — the trash screen's "permanently deleted after N days"
  /// promise, which was previously never enforced. Returns the number of
  /// items purged. Runs automatically on [hydrate]; safe to call manually
  /// (e.g. from a maintenance task) at any time.
  ///
  /// Unlike an explicit "delete forever", the automatic purge does **not**
  /// revoke the Telegram channel copy ([revokeRemote] defaults to false): a
  /// timer silently destroying the user's only cloud backup of a photo they
  /// trashed and forgot is exactly the data loss this app exists to prevent.
  /// The local record is removed and peers converge via the deletion
  /// tombstone, but the backed-up bytes remain recoverable in the channel.
  Future<int> purgeExpiredTrashedItems({
    int retentionDays = AppConstants.trashRetentionDays,
    bool revokeRemote = false,
  }) async {
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
    final expired = _mediaItems
        .where(
          (item) =>
              item.isTrashed &&
              (item.trashedAt ?? item.createdAt).isBefore(cutoff),
        )
        .map((item) => item.localId)
        .toList();
    if (expired.isEmpty) return 0;

    await deletePermanentlyBatch(expired, revokeRemote: revokeRemote);
    return expired.length;
  }

  List<MediaItem> getTrashedItems() {
    return _mediaItems.where((item) => item.isTrashed).toList()..sort(
      (a, b) =>
          (b.trashedAt ?? b.createdAt).compareTo(a.trashedAt ?? a.createdAt),
    );
  }

  /// Hidden items, newest first. Backs the hidden album screen.
  List<MediaItem> getHiddenItems() {
    return _mediaItems.where((item) => item.isHidden).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Archived items, newest first. Backs the archive screen.
  List<MediaItem> getArchivedItems() {
    return _mediaItems.where((item) => item.isArchived).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Groups of items sharing the same file content (SHA-256 hash).
  ///
  /// Returns only groups with 2+ items, sorted by group size descending.
  /// Empty hashes and trashed items are excluded.
  Map<String, List<MediaItem>> getDuplicateGroups() {
    final groups = <String, List<MediaItem>>{};
    for (final item in _mediaItems) {
      if (item.fileHash.isEmpty || item.isTrashed) continue;
      groups.putIfAbsent(item.fileHash, () => []).add(item);
    }
    groups.removeWhere((_, items) => items.length < 2);
    final sorted = SplayTreeMap<String, List<MediaItem>>(
      (a, b) => groups[b]!.length.compareTo(groups[a]!.length),
    );
    sorted.addAll(groups);
    return sorted;
  }

  /// Merge Telegram-backed-up items into the in-memory read model.
  ///
  /// Called by [ChannelScanService] after scanning an existing backup channel.
  /// Items are deduplicated by [MediaItem.localId] (existing items are
  /// replaced) and sorted into the timeline. The merged set is persisted
  /// through [MediaDao].
  Future<void> mergeTelegramItems(List<MediaItem> telegramItems) async {
    final changed = <MediaItem>[];

    for (final item in telegramItems) {
      final index = _indexOfLocalId(item.localId);
      if (index != -1) {
        // Keep the existing entry if it has richer local data (e.g. a
        // filePath pointing to an actual file on disk).
        final existing = _mediaItems[index];
        if (existing.filePath.isNotEmpty &&
            !existing.filePath.startsWith('telegram://')) {
          // Preserve the local item — just sync the Telegram metadata.
          final updated = existing.copyWith(
            telegramMessageId: item.telegramMessageId,
            telegramFileId: item.telegramFileId,
            status: item.status,
            backedUpAt: item.backedUpAt,
          );
          _mediaItems[index] = updated;
          changed.add(updated);
          continue;
        }
        _mediaItems[index] = item;
        changed.add(item);
      } else {
        _mediaItems.add(item);
        _indexByLocalId[item.localId] = _mediaItems.length - 1;
        changed.add(item);
      }
    }

    _mediaItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _rebuildIndex();

    // Persist only items that were actually added or updated, and look up
    // existing DB row IDs to avoid creating duplicate rows on rescans.
    // Batched (single lookup + upsertAll) rather than one upsert per item —
    // a full restore can merge tens of thousands of items.
    await _persistBatch(changed);
  }

  int get totalSize => _mediaItems.fold(0, (sum, item) => sum + item.fileSize);

  /// Apply metadata reconciled from a remote device (the pull side of two-way
  /// sync) to the in-memory read model and database, WITHOUT echoing the
  /// change back through [setMetadataChangeCallback].
  ///
  /// Reconcile already owns the metadata layer for these items; notifying
  /// would re-enqueue a push and could loop. [upserts] are pre-merged
  /// [MediaItem]s for items already known locally (unknown items are ignored
  /// here — they arrive through the caption scan/restore path that also has
  /// the file pointers). [deletions] are localIds tombstoned remotely, removed
  /// from the read model and the database.
  Future<void> applyReconciledMetadata({
    required List<MediaItem> upserts,
    required List<String> deletions,
  }) async {
    for (final item in upserts) {
      final index = _indexOfLocalId(item.localId);
      if (index == -1) continue;
      _mediaItems[index] = item;
      await _persistItem(item);
    }

    if (deletions.isNotEmpty) {
      final ids = deletions.toSet();
      final before = _mediaItems.length;
      _mediaItems.removeWhere((item) => ids.contains(item.localId));
      if (_mediaItems.length != before) _rebuildIndex();
      await _mediaDao?.deleteByLocalIds(deletions);
    }
  }

  /// Write a single mutated item through to the database, keyed by localId.
  /// No-op without a database.
  ///
  /// Uses upsert, not a plain UPDATE: an item reached via [setBackupExcluded]
  /// or [markUploaded] for an asset that was never through a full
  /// [scanDevice]/[scanDeviceIncremental] pass has no existing row yet. An
  /// UPDATE against a localId that isn't in the table affects zero rows and
  /// silently does nothing — the item then lived in memory only, and
  /// vanished (along with its backup status) the next time [hydrate] ran on
  /// a cold start.
  ///
  /// Items scanned via [scanDevice]/[scanDeviceIncremental] never get their
  /// database-assigned `id` merged back into memory, so a later mutation
  /// (favorite/trash/upload status/etc.) usually has `item.id == null` even
  /// though a row already exists. Upsert's ON CONFLICT target is the `id`
  /// column, not the `localId` unique constraint — with `id` absent, that
  /// silently collided with the real unique constraint instead of updating
  /// it. Looking the row up by localId first and carrying its id forward
  /// makes the upsert target the correct primary key either way.
  Future<void> _persistItem(MediaItem item) async {
    final dao = _mediaDao;
    if (dao == null) return;

    var toPersist = item;
    if (toPersist.id == null) {
      final existing = await dao.byLocalId(toPersist.localId);
      if (existing != null) {
        toPersist = toPersist.copyWith(id: existing.id);
      }
    }
    await dao.upsert(toPersist.toCompanion());
  }

  void _notifyMetadataChange({
    required String localId,
    required String operation,
    MediaItem? item,
  }) {
    _onMetadataChange?.call(localId: localId, operation: operation, item: item);
  }
}
