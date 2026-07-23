import 'dart:async';
import 'dart:collection';

import 'package:photo_manager/photo_manager.dart';

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
  MetadataChangeCallback? _onMetadataChange;

  /// Set a callback for metadata changes.
  ///
  /// This allows the metadata system to hook into state changes
  /// without creating a circular dependency.
  void setMetadataChangeCallback(MetadataChangeCallback? callback) {
    _onMetadataChange = callback;
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
  Future<void> hydrate() async {
    final dao = _mediaDao;
    if (dao == null) return;

    final rows = await dao.all();
    _mediaItems
      ..clear()
      ..addAll(rows.map((r) => r.toDomain()));
    _mediaItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
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

    _mediaItems.clear();
    _mediaItems.addAll(result.mediaItems);

    _folders.clear();
    _folders.addAll(result.folders);

    _mediaItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Persist the freshly scanned set, replacing any previous contents so the
    // database mirrors the in-memory read model.
    await _mediaDao?.replaceAll(
      _mediaItems.map((item) => item.toCompanion()).toList(),
    );

    for (final item in result.mediaItems) {
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
        _mergeIntoMemory(newBatch, updatedBatch);
        unawaited(_persistBatch(newBatch, updatedBatch));
      },
    );

    // The batches above already covered everything scanForChanges found, so
    // this is a no-op for items already flushed — it only picks up the
    // (rare) remainder smaller than one batch. indexWhere-based merging and
    // dao.upsertAll are both idempotent, so re-applying is harmless.
    _mergeIntoMemory(result.newItems, result.updatedItems);

    if (result.deletedIds.isNotEmpty) {
      final deleted = result.deletedIds.toSet();
      _mediaItems.removeWhere((item) => deleted.contains(item.localId));
    }

    _mediaItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Folder metadata is cheap (counts only, no file reads) so it's still
    // refreshed in full on every scan.
    _folders.clear();
    _folders.addAll(await _scannerService.getDeviceFolders());

    final dao = _mediaDao;
    if (dao != null) {
      await _persistBatch(result.newItems, result.updatedItems);
      if (result.deletedIds.isNotEmpty) {
        await dao.deleteByLocalIds(result.deletedIds);
      }
    }

    for (final item in result.newItems) {
      _notifyMetadataChange(
        localId: item.localId,
        operation: 'scan_discover',
        item: item,
      );
    }
    for (final item in result.updatedItems) {
      _notifyMetadataChange(
        localId: item.localId,
        operation: 'scan_update',
        item: item,
      );
    }
    for (final id in result.deletedIds) {
      _notifyMetadataChange(localId: id, operation: 'scan_delete', item: null);
    }

    return result;
  }

  /// Merge a batch of new/updated items into the in-memory list, replacing
  /// by [MediaItem.localId] when already present. Idempotent — safe to call
  /// more than once with overlapping items.
  void _mergeIntoMemory(
    List<MediaItem> newBatch,
    List<MediaItem> updatedBatch,
  ) {
    for (final item in [...newBatch, ...updatedBatch]) {
      final index = _mediaItems.indexWhere((m) => m.localId == item.localId);
      if (index != -1) {
        _mediaItems[index] = item;
      } else {
        _mediaItems.add(item);
      }
    }
  }

  /// Persist a batch of new/updated items to the database. No-op without a
  /// DAO (e.g. in unit tests) or for an empty batch.
  Future<void> _persistBatch(
    List<MediaItem> newBatch,
    List<MediaItem> updatedBatch,
  ) async {
    final dao = _mediaDao;
    if (dao == null) return;
    if (newBatch.isEmpty && updatedBatch.isEmpty) return;
    await dao.upsertAll(
      [...newBatch, ...updatedBatch].map((item) => item.toCompanion()).toList(),
    );
  }

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
      return true;
    }).toList();
  }

  List<MediaItem> getAlbumItems(String albumName) {
    return _mediaItems.where((item) => item.albumName == albumName).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<MediaItem> getFavoriteItems() {
    return _mediaItems.where((item) => item.isFavorite).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<MediaItem> searchMedia(String query) {
    final lowerQuery = query.toLowerCase();
    return _mediaItems.where((item) {
      return item.fileName.toLowerCase().contains(lowerQuery) ||
          (item.description?.toLowerCase().contains(lowerQuery) ?? false) ||
          (item.albumName?.toLowerCase().contains(lowerQuery) ?? false) ||
          item.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  Map<String, List<MediaItem>> getTimelineByDate() {
    final Map<String, List<MediaItem>> grouped = {};

    for (final item in _mediaItems) {
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
    try {
      return _mediaItems.firstWhere((item) => item.localId == localId);
    } catch (_) {
      return null;
    }
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
    final index = _mediaItems.indexWhere((item) => item.localId == localId);

    late final MediaItem updated;
    if (index != -1) {
      updated = _mediaItems[index].copyWith(isExcluded: excluded);
      _mediaItems[index] = updated;
    } else {
      final built = await _incrementalScanner.buildSingleItem(asset);
      if (built == null) return;
      updated = built.copyWith(isExcluded: excluded);
      _mediaItems.add(updated);
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
    final index = _mediaItems.indexWhere((item) => item.localId == localId);
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
    final index = _mediaItems.indexWhere((item) => item.localId == localId);
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
    final index = _mediaItems.indexWhere((item) => item.localId == localId);
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
    final index = _mediaItems.indexWhere((item) => item.localId == localId);
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

  Future<void> moveToTrash(String localId) async {
    final index = _mediaItems.indexWhere((item) => item.localId == localId);
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
    final index = _mediaItems.indexWhere((item) => item.localId == localId);
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

  List<MediaItem> getTrashedItems() {
    return _mediaItems.where((item) => item.isTrashed).toList()..sort(
      (a, b) =>
          (b.trashedAt ?? b.createdAt).compareTo(a.trashedAt ?? a.createdAt),
    );
  }

  int get totalSize => _mediaItems.fold(0, (sum, item) => sum + item.fileSize);

  /// Write a single mutated item through to the database, keyed by localId so
  /// the persisted row is updated in place. No-op without a database.
  Future<void> _persistItem(MediaItem item) async {
    final dao = _mediaDao;
    if (dao == null) return;
    await dao.updateByLocalId(item.localId, item.toCompanion());
  }

  void _notifyMetadataChange({
    required String localId,
    required String operation,
    MediaItem? item,
  }) {
    _onMetadataChange?.call(localId: localId, operation: operation, item: item);
  }
}
