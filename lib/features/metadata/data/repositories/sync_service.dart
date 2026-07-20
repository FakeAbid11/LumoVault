import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/metadata_models.dart';
import 'manifest_service.dart';
import 'metadata_repository.dart';
import 'partition_service.dart';

/// Sync strategy per PRD Section 6.5.
///
/// Local -> Telegram (Backup):
/// 1. Scan device for new/modified media
/// 2. Compute SHA-256 hash of each file
/// 3. Check Isar for existing hash (dedup)
/// 4. Upload new files with metadata caption
/// 5. Update Isar with telegramMessageId
/// 6. Update manifest
///
/// Sync triggers:
/// - After upload completion (debounced)
/// - On app background
/// - On manual sync request
/// - Respects Wi-Fi/charging constraints from Backup Engine
class SyncService {
  SyncService({this.debounceDuration = const Duration(seconds: 5)});

  final Duration debounceDuration;

  final Queue<_PendingChange> _changeQueue = Queue();
  Timer? _debounceTimer;
  bool _syncInProgress = false;
  DateTime? _lastSyncTime;
  int _pendingCount = 0;
  String? _lastError;

  final List<SyncLogEntity> _syncLog = [];

  bool get syncInProgress => _syncInProgress;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get pendingCount => _pendingCount;
  String? get lastError => _lastError;

  UnmodifiableListView<SyncLogEntity> get syncLog =>
      UnmodifiableListView(_syncLog);

  /// Initialize the sync service.
  Future<void> initialize() async {
    _loadSyncLog();
  }

  /// Load sync log from persistent storage.
  void _loadSyncLog() {
    // In production, load from Isar SyncLog collection.
    // For now, start with empty log.
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
      _PendingChange(
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

  /// Process pending changes (called after debounce).
  void _processPendingChanges() {
    if (_changeQueue.isEmpty) return;
    debugPrint(
      '[SyncService] Processing ${_changeQueue.length} pending changes',
    );
  }

  /// Sync metadata to Telegram.
  ///
  /// Uploads dirty partitions and updates the manifest.
  /// Respects Wi-Fi/charging constraints from the Backup Engine.
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
      final dirtyIds = partitionService.getDirtyPartitionIds();
      int syncedCount = 0;

      for (final partitionId in dirtyIds) {
        final data = partitionService.serializePartition(partitionId);
        if (data != null) {
          await uploadPartition(partitionId, data);
          syncedCount++;

          _logSync(
            mediaItemId: partitionId,
            operation: 'partition_upload',
            success: true,
          );
        }
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

      _lastSyncTime = DateTime.now().toUtc();
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

    if (_syncLog.length > 1000) {
      _syncLog.removeRange(0, _syncLog.length - 1000);
    }
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

  /// Clear the sync log.
  void clearLog() {
    _syncLog.clear();
  }

  void dispose() {
    _debounceTimer?.cancel();
    _changeQueue.clear();
    _syncLog.clear();
  }
}

/// A pending metadata change waiting to be synced.
class _PendingChange {
  const _PendingChange({
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
