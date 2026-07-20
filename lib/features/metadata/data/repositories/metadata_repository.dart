import 'dart:async';
import 'dart:collection';

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
/// Layer 1: Local metadata store (in-memory, backed by Isar in production)
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
  });

  final ManifestService manifestService;
  final PartitionService partitionService;
  final SearchIndexService searchIndexService;
  final SyncService syncService;
  final ConflictResolver conflictResolver;

  final Map<String, PartitionItem> _localMetadata = {};
  final _changeController = StreamController<MetadataChangeEvent>.broadcast();

  Stream<MetadataChangeEvent> get changeStream => _changeController.stream;

  int get totalItems => _localMetadata.length;

  /// Initialize the metadata repository.
  ///
  /// Loads existing metadata from storage and reconciles with manifest.
  Future<void> initialize() async {
    await syncService.initialize();
    await _loadLocalMetadata();
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

    _changeController.add(
      MetadataChangeEvent(
        mediaItemId: item.localId,
        operation: 'create',
        timestamp: DateTime.now(),
      ),
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

    _changeController.add(
      MetadataChangeEvent(
        mediaItemId: localId,
        operation: operation ?? 'update',
        timestamp: DateTime.now(),
      ),
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

  /// Record item deletion (trashed or permanently removed).
  Future<void> recordDeletion({
    required String localId,
    required String operation,
  }) async {
    _localMetadata.remove(localId);
    partitionService.removeItem(localId);
    searchIndexService.removeItem(localId);

    syncService.enqueueChange(mediaItemId: localId, operation: operation);

    _changeController.add(
      MetadataChangeEvent(
        mediaItemId: localId,
        operation: operation,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Get dirty partitions that need re-upload.
  ///
  /// Returns partition IDs where the local hash differs from the
  /// last-synced hash in the manifest.
  List<String> getDirtyPartitions() {
    return partitionService.getDirtyPartitionIds();
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

  /// Get sync status for UI display.
  MetadataSyncStatus getSyncStatus() {
    return syncService.getSyncStatus();
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
