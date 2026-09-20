import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/metadata_models.dart';
import 'manifest_service.dart';
import 'metadata_repository.dart';
import 'partition_service.dart';
import 'sync_log_persistence.dart';

/// Handler invoked with a coalesced batch of changes once the debounce elapses.
///
/// Throwing from the handler re-queues the batch and re-arms a self-retry
/// timer (bounded exponential backoff), so the batch retries on its own.
typedef ChangeFlushHandler = Future<void> Function(List<SyncChange> changes);

/// Maximum number of log entries retained in memory and on disk.
const int _maxLogEntries = 1000;

/// Sync strategy per PRD Section 6.5.
///
/// Local -> Telegram (Backup):
/// 1. Scan device for new/modified media
/// 2. Compute SHA-256 hash of each file
/// 3. Check the local drift store for an existing hash (dedup)
/// 4. Upload new files with metadata caption
/// 5. Update the local drift store with telegramMessageId
/// 6. Update manifest
///
/// Sync triggers:
/// - After upload completion (debounced)
/// - On app background
/// - On manual sync request
/// - Respects Wi-Fi/charging constraints from Backup Engine
class SyncService {
  SyncService({
    this.debounceDuration = const Duration(seconds: 5),
    this.logStore,
  });

  final Duration debounceDuration;

  /// Optional persistence for [syncLog]. When null the log is memory-only,
  /// which keeps plain `flutter test` runs (no plugin registrant) working.
  final SyncLogStore? logStore;

  final Queue<SyncChange> _changeQueue = Queue();
  Timer? _debounceTimer;
  bool _syncInProgress = false;
  DateTime? _lastSyncTime;
  int _pendingCount = 0;
  String? _lastError;
  ChangeFlushHandler? _flushHandler;

  /// Number of consecutive flush failures, used to grow the retry backoff.
  /// Reset to zero on the first successful flush.
  int _consecutiveFlushFailures = 0;

  /// Upper bound on the self-retry backoff so a persistently failing handler
  /// keeps retrying at a slow, steady cadence rather than either spinning or
  /// backing off to effectively never.
  static const Duration _maxRetryBackoff = Duration(minutes: 5);

  final List<SyncLogEntity> _syncLog = [];

  bool get syncInProgress => _syncInProgress;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get pendingCount => _pendingCount;
  String? get lastError => _lastError;

  UnmodifiableListView<SyncLogEntity> get syncLog =>
      UnmodifiableListView(_syncLog);

  /// Initialize the sync service.
  Future<void> initialize() async {
    await _loadSyncLog();
  }

  /// Install the handler that drains coalesced changes after the debounce.
  ///
  /// Without a handler the queue is still drained and logged, so
  /// [pendingCount] stays honest instead of growing without bound.
  void setChangeFlushHandler(ChangeFlushHandler? handler) {
    _flushHandler = handler;
  }

  /// Load sync log from persistent storage (JSON file, see [FileSyncLogStore]).
  Future<void> _loadSyncLog() async {
    final store = logStore;
    if (store == null) return;

    final persisted = await store.load();
    if (persisted.isEmpty) return;

    _syncLog
      ..clear()
      ..addAll(persisted);
    _trimLog();
  }

  /// Enqueue a metadata change for sync.
  ///
  /// Changes are debounced to avoid excessive sync operations.
  /// This is fire-and-forget from the caller's perspective.
  void enqueueChange({
    required String mediaItemId,
    required String operation,
    Map<String, dynamic>? details,
  }) {
    _changeQueue.add(
      SyncChange(
        mediaItemId: mediaItemId,
        operation: operation,
        timestamp: DateTime.now().toUtc(),
        details: details,
      ),
    );
    _pendingCount = _changeQueue.length;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, _processPendingChanges);
  }

  /// Compute the self-retry delay after [_consecutiveFlushFailures] failures:
  /// the debounce doubled per failure, capped at [_maxRetryBackoff].
  Duration _retryBackoff() {
    final failures = _consecutiveFlushFailures.clamp(0, 20);
    final scaled = debounceDuration * (1 << (failures - 1).clamp(0, 20));
    return scaled > _maxRetryBackoff ? _maxRetryBackoff : scaled;
  }

  /// Process pending changes (called after debounce).
  ///
  /// Drains the whole queue, coalescing by media item so only the newest
  /// change per item is flushed, then hands the batch to the flush handler.
  /// On failure the batch is re-queued and a self-retry timer is re-armed
  /// with a bounded exponential backoff (see [_retryBackoff]), so recovery no
  /// longer waits on an unrelated [enqueueChange] to happen by. A successful
  /// flush resets the backoff.
  Future<void> _processPendingChanges() async {
    if (_changeQueue.isEmpty) return;

    final batch = _changeQueue.toList(growable: false);
    _changeQueue.clear();
    _pendingCount = 0;

    final coalesced = <String, SyncChange>{};
    for (final change in batch) {
      coalesced[change.mediaItemId] = change;
    }
    final changes = coalesced.values.toList(growable: false);

    debugPrint(
      '[SyncService] Flushing ${changes.length} coalesced '
      'change(s) from ${batch.length} pending',
    );

    try {
      await _flushHandler?.call(changes);

      _consecutiveFlushFailures = 0;
      for (final change in changes) {
        _logSync(
          mediaItemId: change.mediaItemId,
          operation: change.operation,
          success: true,
        );
      }
      await _persistLog();
    } catch (e) {
      _lastError = e.toString();
      _consecutiveFlushFailures++;
      _changeQueue.addAll(batch);
      _pendingCount = _changeQueue.length;
      final backoff = _retryBackoff();
      _logSync(
        mediaItemId: 'sync',
        operation: 'flush_failed',
        success: false,
        error: e.toString(),
        details:
            '${batch.length} change(s) re-queued; retry in ${backoff.inSeconds}s',
      );
      await _persistLog();

      // Re-arm the debounce so the batch retries on its own instead of
      // stalling until some later, unrelated change happens to be enqueued.
      _debounceTimer?.cancel();
      _debounceTimer = Timer(backoff, _processPendingChanges);
    }
  }

  /// Sync metadata to Telegram.
  ///
  /// Uploads dirty partitions and updates the manifest.
  /// Respects Wi-Fi/charging constraints from the Backup Engine.
  ///
  /// "Dirty" is decided by comparing each local partition's content hash
  /// against the hash recorded for it in the current manifest. Partitions
  /// whose contents haven't changed since the last successful sync are
  /// skipped entirely — that is the whole point of partitioning metadata by
  /// month. Passing no baseline (as this used to) makes every partition look
  /// dirty and re-uploads the user's entire metadata history on every sync.
  Future<int> syncToTelegram({
    required PartitionService partitionService,
    required ManifestService manifestService,
    required Future<void> Function(String partitionId, String data)
    uploadPartition,
    required Future<void> Function(String manifestJson) uploadManifest,
  }) async {
    if (_syncInProgress) return 0;

    _syncInProgress = true;
    _lastError = null;

    try {
      final dirtyIds = partitionService.getDirtyPartitionIds(
        manifestHashes: manifestService.partitionHashes,
      );
      int syncedCount = 0;

      final synced = <MetadataPartition>[];
      for (final partitionId in dirtyIds) {
        final partition = partitionService.getPartition(partitionId);
        final data = partitionService.serializePartition(partitionId);
        if (partition != null && data != null) {
          await uploadPartition(partitionId, data);
          syncedCount++;
          synced.add(partition);

          _logSync(
            mediaItemId: partitionId,
            operation: 'partition_upload',
            success: true,
          );
        }
      }

      final syncTime = DateTime.now().toUtc();

      // Record what was just uploaded *before* serializing the manifest, so
      // the manifest sent to Telegram matches the partitions that went with
      // it — and so the next run's dirty check has a baseline to compare
      // against. An upload that throws skips this and leaves the partition
      // dirty, which is the behaviour we want on failure.
      if (synced.isNotEmpty) {
        manifestService.recordSyncedPartitions(
          partitions: synced,
          syncTime: syncTime,
        );
      }

      // Refresh the manifest content from the live partition set so what gets
      // uploaded describes current state. The debounced flush normally does
      // this, but a manual sync that runs before the debounce fires would
      // otherwise serialize a stale manifest. This regenerates *content* only
      // — it no longer advances the baseline (generateManifest keeps
      // partitionHashes untouched; only recordSyncedPartitions above does).
      final current = manifestService.getCurrentManifest();
      final deviceHash = current?.deviceHash;
      if (deviceHash != null) {
        final items = partitionService
            .getAllPartitions()
            .expand((partition) => partition.items)
            .toList();
        await manifestService.generateManifest(
          localMetadata: items,
          deviceHash: deviceHash,
        );
      }

      final manifest = manifestService.toJsonString();
      if (manifest != null) {
        await uploadManifest(manifest);
        _logSync(
          mediaItemId: 'manifest',
          operation: 'manifest_upload',
          success: true,
        );
      }

      _lastSyncTime = syncTime;
      _pendingCount = 0;

      return syncedCount;
    } catch (e) {
      _lastError = e.toString();
      _logSync(
        mediaItemId: 'sync',
        operation: 'sync_failed',
        success: false,
        error: e.toString(),
      );
      return 0;
    } finally {
      _syncInProgress = false;
      await _persistLog();
    }
  }

  /// Log a sync operation.
  void _logSync({
    required String mediaItemId,
    required String operation,
    required bool success,
    String? error,
    String? details,
  }) {
    final log = SyncLogEntity(
      mediaItemId: mediaItemId,
      operation: operation,
      timestamp: DateTime.now().toUtc(),
      success: success,
      error: error,
      details: details,
    );
    _syncLog.add(log);
    _trimLog();
  }

  void _trimLog() {
    if (_syncLog.length > _maxLogEntries) {
      _syncLog.removeRange(0, _syncLog.length - _maxLogEntries);
    }
  }

  Future<void> _persistLog() async {
    final store = logStore;
    if (store == null) return;
    await store.save(_syncLog);
  }

  /// Get sync status for UI display.
  MetadataSyncStatus getSyncStatus() {
    return MetadataSyncStatus(
      lastSyncedAt: _lastSyncTime,
      pendingChangesCount: _pendingCount,
      syncInProgress: _syncInProgress,
      syncError: _lastError,
      syncProgress: _syncInProgress ? 0.5 : 0.0,
    );
  }

  /// Get recent sync log entries.
  List<SyncLogEntity> getRecentLog({int limit = 50}) {
    return _syncLog.length <= limit
        ? List.from(_syncLog.reversed)
        : _syncLog.sublist(_syncLog.length - limit).reversed.toList();
  }

  /// Clear the sync log, in memory and on disk.
  Future<void> clearLog() async {
    _syncLog.clear();
    await logStore?.clear();
  }

  void dispose() {
    _debounceTimer?.cancel();
    _changeQueue.clear();
    _syncLog.clear();
  }
}

/// A pending metadata change waiting to be synced.
class SyncChange {
  const SyncChange({
    required this.mediaItemId,
    required this.operation,
    required this.timestamp,
    this.details,
  });
  final String mediaItemId;
  final String operation;
  final DateTime timestamp;
  final Map<String, dynamic>? details;
}
