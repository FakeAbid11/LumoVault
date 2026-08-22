import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../gallery/data/models/media_item.dart';
import '../models/metadata_models.dart';
import 'conflict_resolver.dart';
import 'manifest_service.dart';
import 'partition_service.dart';
import 'search_index_service.dart';
import 'sync_service.dart';

/// Metadata change event for notifying listeners.
class MetadataChangeEvent {
  const MetadataChangeEvent({
    required this.mediaItemId,
    required this.operation,
    required this.timestamp,
  });
  final String mediaItemId;
  final String operation;
  final DateTime timestamp;
}

/// Core metadata repository managing all three layers per PRD Section 6:
///
/// Layer 1: Local metadata store (in-memory, hydrated from the drift database)
/// Layer 2: Telegram message captions (portable backup)
/// Layer 3: Manifest + partitioned metadata files (sync layer)
///
/// This repository orchestrates read/write/reconcile across all layers
/// and provides the public API for the metadata system.
class MetadataRepository {
  MetadataRepository({
    required this.manifestService,
    required this.partitionService,
    required this.searchIndexService,
    required this.syncService,
    required this.conflictResolver,
  }) {
    // Installed here rather than in initialize() so the debounced queue always
    // has a drain, even for callers that construct the repository directly.
    syncService.setChangeFlushHandler(_flushChanges);
  }

  final ManifestService manifestService;
  final PartitionService partitionService;
  final SearchIndexService searchIndexService;
  final SyncService syncService;
  final ConflictResolver conflictResolver;

  final Map<String, PartitionItem> _localMetadata = {};
  final _changeController = StreamController<MetadataChangeEvent>.broadcast();

  /// Reflects metadata pulled + reconciled from Telegram back into the gallery
  /// read model. Set by [MetadataIntegration] at bootstrap; null in tests that
  /// only exercise the metadata layer.
  ///
  /// [upserts] are the winning (non-deleted) items whose user-facing fields
  /// changed; [deletions] are localIds tombstoned remotely. Deliberately not a
  /// [changeStream] event: reflecting into the gallery must NOT echo back as a
  /// fresh local change (that would re-enqueue a push and could loop).
  Future<void> Function(List<PartitionItem> upserts, List<String> deletions)?
  onReconcileApplied;

  Stream<MetadataChangeEvent> get changeStream => _changeController.stream;

  int get totalItems => _localMetadata.length;

  /// Initialize the metadata repository.
  ///
  /// Loads existing metadata from storage and reconciles with manifest.
  Future<void> initialize() async {
    await syncService.initialize();
    await _loadLocalMetadata();
  }

  /// Drain handler for the debounced change queue in [SyncService].
  ///
  /// Regenerates the manifest so partition hashes reflect the batched changes
  /// (which is what makes [getDirtyPartitions] meaningful), then announces that
  /// an upload is due so the backup layer can call [syncToTelegram].
  Future<void> _flushChanges(List<SyncChange> changes) async {
    if (changes.isEmpty) return;

    final deviceHash = manifestService.getCurrentManifest()?.deviceHash;
    if (deviceHash != null) {
      await generateManifest(deviceHash: deviceHash);
    }

    // A flush with zero dirty partitions means the batch was already
    // reflected in a sync that ran while the debounce was pending (or the
    // operations cancelled each other out). Announcing sync_pending anyway
    // used to make the backup layer call syncToTelegram, which then
    // re-uploaded the manifest even though nothing had changed.
    if (getDirtyPartitions().isEmpty) {
      debugPrint(
        '[MetadataRepository] Flush produced no dirty partitions — '
        'skipping sync announcement',
      );
      return;
    }

    _emitChange(
      mediaItemId: changes.length == 1 ? changes.first.mediaItemId : '*',
      operation: 'sync_pending',
    );
  }

  /// Load local metadata from persistent storage.
  Future<void> _loadLocalMetadata() async {
    final partitions = partitionService.getAllPartitions();
    for (final partition in partitions) {
      for (final item in partition.items) {
        _localMetadata[item.localId] = item;
      }
    }
  }

  /// Get metadata for a specific media item.
  PartitionItem? getItemMetadata(String localId) {
    return _localMetadata[localId];
  }

  /// Get all metadata items.
  List<PartitionItem> getAllMetadata() {
    return UnmodifiableListView(_localMetadata.values);
  }

  /// Record metadata for a newly scanned media item.
  ///
  /// Called by MediaScanner (Prompt 6) when a new item is discovered.
  /// This is fire-and-forget from the caller's perspective.
  Future<void> recordNewItem(MediaItem item) async {
    final partitionItem = PartitionItem.fromMediaItem(item);

    _localMetadata[item.localId] = partitionItem;

    partitionService.upsertItem(partitionItem);
    searchIndexService.indexItem(partitionItem);
    syncService.enqueueChange(mediaItemId: item.localId, operation: 'create');

    _emitChange(
      mediaItemId: item.localId,
      operation: 'create',
    );
  }

  /// Record metadata update when an item's state changes.
  ///
  /// Called when favorite, hidden, archived, trashed, or album changes.
  Future<void> recordStateChange({
    required String localId,
    String? operation,
    PartitionItem? updatedItem,
  }) async {
    if (updatedItem != null) {
      _localMetadata[localId] = updatedItem;
      partitionService.upsertItem(updatedItem);
      searchIndexService.reindexItem(updatedItem);
    }

    syncService.enqueueChange(
      mediaItemId: localId,
      operation: operation ?? 'update',
    );

    _emitChange(
      mediaItemId: localId,
      operation: operation ?? 'update',
    );
  }

  /// Record upload completion and update Telegram message metadata.
  Future<void> recordUploadComplete({
    required String localId,
    required String telegramMessageId,
    required String telegramFileId,
  }) async {
    final existing = _localMetadata[localId];
    if (existing == null) return;

    final updated = existing.copyWith(
      telegramMessageId: telegramMessageId,
      telegramFileId: telegramFileId,
      backedUpAt: DateTime.now().toUtc(),
    );

    _localMetadata[localId] = updated;
    partitionService.upsertItem(updated);

    syncService.enqueueChange(
      mediaItemId: localId,
      operation: 'upload_complete',
    );
  }

  /// Record item deletion.
  ///
  /// A permanent delete (`operation == 'delete'`) writes a **tombstone**: the
  /// item stays in its partition marked [PartitionItem.isDeleted] with a fresh
  /// [PartitionItem.deletedAt]/[PartitionItem.modifiedAt], so the deletion (a)
  /// re-hashes its partition dirty and re-uploads, (b) survives a restore
  /// instead of being resurrected from the still-present media caption, and
  /// (c) wins the last-write-wins reconcile on other devices, converging them
  /// on the deletion. It is dropped from the in-memory store's live view via
  /// the search index only.
  ///
  /// Any other operation (notably `scan_delete`, where a scan merely noticed
  /// the file left this device) removes the item locally without a tombstone —
  /// a local disappearance must not revoke the channel backup on every device.
  Future<void> recordDeletion({
    required String localId,
    required String operation,
  }) async {
    final existing = _localMetadata[localId];
    if (operation == 'delete' && existing != null) {
      final now = DateTime.now().toUtc();
      final tombstone = existing.copyWith(
        isDeleted: true,
        deletedAt: now,
        modifiedAt: now,
      );
      _localMetadata[localId] = tombstone;
      partitionService.upsertItem(tombstone);
      searchIndexService.removeItem(localId);
    } else {
      _localMetadata.remove(localId);
      partitionService.removeItem(localId);
      searchIndexService.removeItem(localId);
    }

    syncService.enqueueChange(mediaItemId: localId, operation: operation);

    _emitChange(
      mediaItemId: localId,
      operation: operation,
    );
  }

  /// Get dirty partitions that need re-upload.
  ///
  /// Returns partition IDs where the local hash differs from the
  /// last-synced hash in the manifest. This used to call
  /// [PartitionService.getDirtyPartitionIds] with no baseline at all, so it
  /// answered "all of them" unconditionally — the doc comment above described
  /// behaviour the code never performed, and the pending-sync count in the UI
  /// was really just a partition count.
  List<String> getDirtyPartitions() {
    return partitionService.getDirtyPartitionIds(
      manifestHashes: manifestService.partitionHashes,
    );
  }

  /// Get the current manifest.
  Manifest? getCurrentManifest() {
    return manifestService.getCurrentManifest();
  }

  /// Generate a new manifest from current state.
  Future<Manifest> generateManifest({required String deviceHash}) async {
    return manifestService.generateManifest(
      localMetadata: _localMetadata.values.toList(),
      deviceHash: deviceHash,
    );
  }

  /// Resolve conflict between local and remote metadata.
  ///
  /// Per PRD Section 6.5: last-write-wins, no merge needed.
  PartitionItem? resolveConflict({
    required PartitionItem local,
    required PartitionItem remote,
  }) {
    return conflictResolver.resolve(local: local, remote: remote);
  }

  /// Sync metadata to Telegram (upload dirty partitions + manifest).
  ///
  /// Returns the number of partitions synced.
  Future<int> syncToTelegram({
    required Future<void> Function(String partitionId, String data)
    uploadPartition,
    required Future<void> Function(String manifestJson) uploadManifest,
  }) async {
    return syncService.syncToTelegram(
      partitionService: partitionService,
      manifestService: manifestService,
      uploadPartition: uploadPartition,
      uploadManifest: uploadManifest,
    );
  }

  /// Pull the remote metadata layer and reconcile it into local state.
  ///
  /// The mirror of [syncToTelegram]: downloads the remote manifest, and for
  /// every partition whose remote hash differs from what we hold locally,
  /// downloads that partition and runs [ConflictResolver] last-write-wins over
  /// it. Winners are applied to [_localMetadata], the partition set, and the
  /// search index; remote tombstones (isDeleted) become local deletions.
  /// Finally the last-synced baseline advances to the remote manifest, so
  /// partitions where the local (merged) copy still differs stay dirty and are
  /// pushed back on the next sync — this is what converges two devices.
  ///
  /// Idempotent: an item identical on both sides resolves to no-op, so a pull
  /// that finds nothing new (including the echo of our own upload) changes
  /// nothing. Returns the number of items applied (upserts + deletions).
  ///
  /// The two downloads are injected (parallel to [syncToTelegram]'s upload
  /// callbacks) so the metadata layer stays free of any TDLib dependency and
  /// the reconcile is testable with a fake downloader.
  Future<int> reconcileFromTelegram({
    required Future<Manifest?> Function() downloadManifest,
    required Future<MetadataPartition?> Function(String partitionId)
    downloadPartition,
  }) async {
    final remoteManifest = await downloadManifest();
    if (remoteManifest == null) return 0;

    // Only pull partitions whose remote content hash differs from ours — the
    // whole point of the manifest baseline is to avoid re-downloading
    // unchanged partitions.
    final toPull = <String>[];
    for (final chunk in remoteManifest.chunks) {
      final localHash = partitionService.getPartition(chunk.id)?.computeHash();
      if (localHash != chunk.hash) toPull.add(chunk.id);
    }

    final upserts = <PartitionItem>[];
    final deletions = <String>[];

    for (final partitionId in toPull) {
      final remotePartition = await downloadPartition(partitionId);
      if (remotePartition == null) continue;

      final localItems =
          partitionService.getPartition(partitionId)?.items.toList() ??
          const <PartitionItem>[];
      final localIds = {for (final i in localItems) i.localId};

      // Items present on both sides: last-write-wins.
      final resolved = conflictResolver.resolveBatch(
        localItems: localItems,
        remoteItems: remotePartition.items,
      );
      for (final rc in resolved) {
        _applyReconciledItem(rc.resolved, upserts, deletions);
      }

      // Remote-only items: created (or deleted) on another device and not seen
      // here yet — adopt them wholesale.
      for (final remoteItem in remotePartition.items) {
        if (localIds.contains(remoteItem.localId)) continue;
        _applyReconciledItem(remoteItem, upserts, deletions);
      }
    }

    // Advance the last-synced baseline to what the remote manifest describes.
    manifestService.setManifest(remoteManifest);

    final reflect = onReconcileApplied;
    if (reflect != null && (upserts.isNotEmpty || deletions.isNotEmpty)) {
      await reflect(upserts, deletions);
    }

    return upserts.length + deletions.length;
  }

  /// Apply a single reconciled winner to layer 1 (local store, partition set,
  /// search index) and bucket it into [upserts]/[deletions] for gallery
  /// reflection. A tombstoned winner is kept in the partition (so it re-syncs
  /// and survives a restore) but dropped from the search index and marked for
  /// gallery removal.
  void _applyReconciledItem(
    PartitionItem resolved,
    List<PartitionItem> upserts,
    List<String> deletions,
  ) {
    _localMetadata[resolved.localId] = resolved;
    partitionService.upsertItem(resolved);
    if (resolved.isDeleted) {
      searchIndexService.removeItem(resolved.localId);
      deletions.add(resolved.localId);
    } else {
      searchIndexService.reindexItem(resolved);
      upserts.add(resolved);
    }
  }

  /// Get sync status for UI display.
  MetadataSyncStatus getSyncStatus() {
    return syncService.getSyncStatus();
  }

  /// Emit a change event, guarded against a closed controller.
  void _emitChange({
    required String mediaItemId,
    required String operation,
  }) {
    if (_changeController.isClosed) return;
    _changeController.add(
      MetadataChangeEvent(
        mediaItemId: mediaItemId,
        operation: operation,
        timestamp: DateTime.now(),
      ),
    );
  }

  void dispose() {
    _changeController.close();
  }
}

/// Sync status for UI display per PRD wireframes.
class MetadataSyncStatus {
  const MetadataSyncStatus({
    this.lastSyncedAt,
    this.pendingChangesCount = 0,
    this.syncInProgress = false,
    this.syncError,
    this.syncProgress = 0.0,
  });
  final DateTime? lastSyncedAt;
  final int pendingChangesCount;
  final bool syncInProgress;
  final String? syncError;
  final double syncProgress;

  MetadataSyncStatus copyWith({
    DateTime? lastSyncedAt,
    int? pendingChangesCount,
    bool? syncInProgress,
    String? syncError,
    double? syncProgress,
  }) {
    return MetadataSyncStatus(
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      pendingChangesCount: pendingChangesCount ?? this.pendingChangesCount,
      syncInProgress: syncInProgress ?? this.syncInProgress,
      syncError: syncError,
      syncProgress: syncProgress ?? this.syncProgress,
    );
  }

  String get lastSyncDisplay {
    if (lastSyncedAt == null) return 'Never synced';
    final diff = DateTime.now().difference(lastSyncedAt!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  String toString() =>
      'MetadataSyncStatus(last: $lastSyncDisplay, pending: $pendingChangesCount, '
      'inProgress: $syncInProgress)';
}
