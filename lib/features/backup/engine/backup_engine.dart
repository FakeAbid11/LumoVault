import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/storage/storage_channel_service.dart';
import '../data/models/backup_settings.dart';
import '../../gallery/data/models/media_item.dart';
import '../../gallery/data/models/transfer_error.dart';
import '../../gallery/data/models/upload_task.dart';
import '../../gallery/data/repositories/gallery_repository.dart';
import '../../gallery/data/repositories/telegram_upload_service.dart';
import 'backup_scheduler.dart';
import 'upload_queue.dart';

/// Backup engine state.
enum BackupEngineState { idle, scanning, uploading, paused, error }

/// Aggregate backup statistics.
class BackupStats {
  const BackupStats({
    this.totalMediaItems = 0,
    this.backedUpCount = 0,
    this.pendingCount = 0,
    this.failedCount = 0,
    this.uploadingCount = 0,
    this.progress = 0.0,
    this.lastBackupAt,
    this.totalBytes = 0,
    this.backedUpBytes = 0,
  });
  final int totalMediaItems;
  final int backedUpCount;
  final int pendingCount;
  final int failedCount;
  final int uploadingCount;
  final double progress;
  final DateTime? lastBackupAt;
  final int totalBytes;
  final int backedUpBytes;

  BackupStats copyWith({
    int? totalMediaItems,
    int? backedUpCount,
    int? pendingCount,
    int? failedCount,
    int? uploadingCount,
    double? progress,
    DateTime? lastBackupAt,
    int? totalBytes,
    int? backedUpBytes,
  }) {
    return BackupStats(
      totalMediaItems: totalMediaItems ?? this.totalMediaItems,
      backedUpCount: backedUpCount ?? this.backedUpCount,
      pendingCount: pendingCount ?? this.pendingCount,
      failedCount: failedCount ?? this.failedCount,
      uploadingCount: uploadingCount ?? this.uploadingCount,
      progress: progress ?? this.progress,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      totalBytes: totalBytes ?? this.totalBytes,
      backedUpBytes: backedUpBytes ?? this.backedUpBytes,
    );
  }

  double get progressPercent => (progress * 100).clamp(0.0, 100.0);

  String get progressDisplay {
    if (totalMediaItems == 0) return 'No items';
    return '$backedUpCount of $totalMediaItems';
  }
}

/// Core backup engine orchestrating scan, queue, upload, and state.
///
/// Per PRD Section 9.1, the engine coordinates:
/// 1. Media Scanner -> detect new/modified media
/// 2. Upload Scheduler -> prioritize, batch, throttle
/// 3. Upload Worker -> TDLib client, chunked upload, progress, errors
/// 4. State Manager -> updates, notifications, stats
class BackupEngine {
  BackupEngine({
    required this.galleryRepository,
    required this.uploadService,
    required this.settings,
    required this.storageChannelService,
    int? persistedChannelId,
    this.onChannelResolved,
  }) {
    if (persistedChannelId != null) {
      storageChannelService.setCachedChannelId(persistedChannelId);
    }
    // Previously declared but never assigned, so per-file progress from
    // TDLib never reached the queue: the dashboard showed 0% / 0 B for the
    // entire duration of an upload no matter how much had actually
    // transferred, only jumping to 100% once the task fully completed.
    _progressSubscription = uploadService.progressStream.listen(
      _onUploadProgress,
    );
  }

  final GalleryRepository galleryRepository;
  final UploadService uploadService;
  BackupSettings settings;

  /// Finds (or creates, on first-ever backup) the private Telegram channel
  /// that files upload into. Previously this was never called at all — every
  /// upload used a hardcoded placeholder `channelId = 0`, so no channel was
  /// ever created and no real upload could have succeeded.
  final StorageChannelService storageChannelService;

  /// Called once a channel id is resolved (found or newly created), so the
  /// caller can persist it — without this, a fresh app process would create
  /// a brand new channel every time instead of reusing the existing one.
  final void Function(int channelId)? onChannelResolved;

  final UploadQueue _queue = UploadQueue();
  BackupEngineState _state = BackupEngineState.idle;
  BackupStats _stats = const BackupStats();
  bool _isPaused = false;
  BackupEnvironment _environment = const BackupEnvironment();

  Timer? _uploadTimer;
  StreamSubscription<UploadProgress>? _progressSubscription;
  final _stateController = StreamController<BackupEngineState>.broadcast();
  final _statsController = StreamController<BackupStats>.broadcast();

  UploadQueue get queue => _queue;
  BackupEngineState get state => _state;
  BackupStats get stats => _stats;
  bool get isPaused => _isPaused;

  Stream<BackupEngineState> get stateStream => _stateController.stream;
  Stream<BackupStats> get statsStream => _statsController.stream;

  /// Update the backup settings.
  void updateSettings(BackupSettings newSettings) {
    settings = newSettings;
  }

  /// Update the environment state (connectivity, battery, etc.).
  void updateEnvironment(BackupEnvironment environment) {
    _environment = environment;
  }

  /// Scan device for new media and enqueue items for backup.
  Future<void> scanAndEnqueue() async {
    if (_state == BackupEngineState.scanning) return;

    _setState(BackupEngineState.scanning);

    try {
      // Was scanDevice() — a full re-scan that re-reads and re-hashes every
      // file on the device again, even though the timeline screen already
      // scanned everything moments earlier via scanDeviceIncremental. Using
      // the incremental scan here too avoids doing that expensive work
      // twice, and avoids re-triggering the same freeze-prone full-album
      // fetch path independently of whatever the timeline screen is doing.
      await galleryRepository.scanDeviceIncremental(
        includedFolders: settings.allFoldersIncluded
            ? null
            : settings.includedFolders,
      );

      final items = galleryRepository.getTimelineItems();
      final filteredItems = BackupScheduler.filterItemsForBackup(
        items: items,
        settings: settings,
      );

      // Enqueue items that aren't already backed up or queued.
      final newItems = filteredItems.where((item) {
        if (item.status == MediaStatus.uploaded) return false;
        if (item.status == MediaStatus.excluded) return false;
        if (_queue.hasTaskForMediaItem(item.localId)) return false;
        if (_queue.isAlreadyBackedUp(item.fileHash)) return false;
        return true;
      }).toList();

      _queue.enqueueBatch(newItems);

      _updateStats();
      _setState(BackupEngineState.idle);

      settings = settings.copyWith(lastScanAt: DateTime.now());
    } catch (e) {
      _setState(BackupEngineState.error);
      rethrow;
    }
  }

  /// Start the backup process.
  Future<void> startBackup() async {
    if (_isPaused) return;
    if (_state == BackupEngineState.uploading) return;

    final schedulerResult = BackupScheduler.evaluate(
      settings: settings,
      environment: _environment,
    );

    if (!schedulerResult.canProceed) {
      debugPrint('[BackupEngine] Cannot start: ${schedulerResult.reason}');
      return;
    }

    _setState(BackupEngineState.uploading);
    await _processQueue();
  }

  /// Pause the backup.
  void pauseBackup() {
    _isPaused = true;
    _uploadTimer?.cancel();
    _queue.pauseAll();
    _setState(BackupEngineState.paused);
  }

  /// Resume the backup.
  Future<void> resumeBackup() async {
    _isPaused = false;
    _queue.resumeAll();
    _setState(BackupEngineState.idle);
    await startBackup();
  }

  /// Retry all failed uploads.
  Future<void> retryFailed() async {
    _queue.retryAllFailed();
    _updateStats();
    if (!_isPaused) {
      await startBackup();
    }
  }

  /// Cancel a specific upload task.
  void cancelTask(String taskId) {
    _queue.removeTask(taskId);
    _updateStats();
  }

  /// Add a single item to the queue (user-initiated).
  void addToQueue(MediaItem item) {
    _queue.enqueue(item: item, isUserInitiated: true);
    _updateStats();
  }

  /// Enqueue a single item the user just selected for backup, so it shows up
  /// on the dashboard immediately instead of only after the next full
  /// "Start Backup" scan. Skips items that are excluded, trashed, already
  /// uploaded, or already queued (enqueue itself dedups the last case).
  void enqueueSelectedItem(MediaItem item) {
    if (item.isExcluded || item.isTrashed) return;
    if (item.status == MediaStatus.uploaded) return;
    _queue.enqueue(item: item, isUserInitiated: true);
    _updateStats();
  }

  /// Drop the queued task for an item the user just de-selected, so it stops
  /// showing as pending on the dashboard. Harmless if it isn't queued.
  void dequeueSelectedItem(String mediaItemId) {
    _queue.removeByMediaItem(mediaItemId);
    _updateStats();
  }

  /// Clear finished tasks from the queue.
  void clearFinished() {
    _queue.clearFinished();
    _updateStats();
  }

  /// Process the upload queue.
  Future<void> _processQueue() async {
    if (_isPaused) return;

    final batch = _queue.getNextBatch();
    if (batch.isEmpty) {
      _setState(BackupEngineState.idle);
      _updateStats();
      return;
    }

    for (final task in batch) {
      if (_isPaused) break;

      // Re-evaluate constraints before each upload.
      final schedulerResult = BackupScheduler.evaluate(
        settings: settings,
        environment: _environment,
      );

      if (!schedulerResult.canProceed) {
        debugPrint(
          '[BackupEngine] Paused mid-batch: ${schedulerResult.reason}',
        );
        _setState(BackupEngineState.paused);
        return;
      }

      await _uploadTask(task);

      // Throttle between uploads.
      if (!_isPaused && settings.uploadDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: settings.uploadDelayMs));
      }
    }

    // Process next batch if available.
    if (!_isPaused && _queue.pendingCount > 0) {
      await _processQueue();
    } else if (!_isPaused) {
      settings = settings.copyWith(lastBackupAt: DateTime.now());
      _setState(BackupEngineState.idle);
    }

    _updateStats();
  }

  /// Forward a progress event from [uploadService] into the matching queue
  /// task, so the dashboard's progress bar and byte counter actually move
  /// during an upload instead of sitting at 0% until it finishes.
  void _onUploadProgress(UploadProgress progress) {
    final task = _queue.getTaskById(progress.taskId);
    if (task == null || task.status != UploadStatus.uploading) return;
    _queue.updateTask(task.copyWith(progress: progress.progress));
    _updateStats();
  }

  /// Upload a single task.
  Future<void> _uploadTask(UploadTask task) async {
    // Duplicate check before upload.
    if (_queue.isAlreadyBackedUp(task.fileHash)) {
      _queue.updateTask(
        task.copyWith(
          status: UploadStatus.completed,
          progress: 1.0,
          completedAt: DateTime.now(),
        ),
      );
      return;
    }

    _queue.updateTask(
      task.copyWith(status: UploadStatus.uploading, startedAt: DateTime.now()),
    );
    _updateStats();

    try {
      final channelId = await _resolveChannelId();

      final result = await uploadService.uploadFile(
        task: task,
        channelId: channelId,
      );

      _queue.updateTask(
        task.copyWith(
          status: UploadStatus.completed,
          progress: 1.0,
          telegramMessageId: result.messageId.toString(),
          telegramFileId: result.fileId.toString(),
          completedAt: DateTime.now(),
        ),
      );
    } on TransferError catch (e) {
      final shouldRetry =
          e.retryable && task.retryCount < settings.uploadBatchSize;

      _queue.updateTask(
        task.copyWith(
          status: shouldRetry ? UploadStatus.queued : UploadStatus.failed,
          error: e,
          failedAt: DateTime.now(),
          retryCount: task.retryCount + 1,
        ),
      );

      if (shouldRetry) {
        final backoff = BackupScheduler.calculateBackoff(task.retryCount);
        debugPrint(
          '[BackupEngine] Retrying ${task.fileName} in ${backoff.inSeconds}s',
        );
        await Future.delayed(backoff);
      }
    }
  }

  /// Resolve the Telegram channel to upload into, creating it on first use.
  ///
  /// Cached both in-memory (via [StorageChannelService.cachedChannelId]) and,
  /// through [onChannelResolved], in persisted settings — so this only
  /// actually calls TDLib to find-or-create the channel once per install,
  /// not once per file.
  Future<int> _resolveChannelId() async {
    final cached = storageChannelService.cachedChannelId;
    if (cached != null) return cached;

    final result = await storageChannelService.findOrCreateChannel();

    switch (result) {
      case StorageChannelFound(:final channelId):
      case StorageChannelCreated(:final channelId):
        onChannelResolved?.call(channelId);
        return channelId;
      case StorageChannelError(:final message, :final code):
        throw TransferError(
          category: TransferErrorCategory.unknown,
          message: 'Could not set up Telegram storage: $message',
          detail: code,
          retryable: true,
          occurredAt: DateTime.now(),
        );
    }
  }

  void _setState(BackupEngineState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void _updateStats() {
    _stats = BackupStats(
      totalMediaItems: galleryRepository.totalCount,
      backedUpCount: _queue.completedCount,
      pendingCount: _queue.pendingCount,
      failedCount: _queue.failedCount,
      uploadingCount: _queue.uploadingCount,
      progress: _queue.overallProgress,
      lastBackupAt: settings.lastBackupAt,
      totalBytes: _queue.allTasks.fold(0, (sum, t) => sum + t.fileSize),
      backedUpBytes: _queue.allTasks.fold(0, (sum, t) {
        if (t.status == UploadStatus.completed) return sum + t.fileSize;
        if (t.status == UploadStatus.uploading) {
          return sum + (t.fileSize * t.progress).round();
        }
        return sum;
      }),
    );
    _statsController.add(_stats);
  }

  void dispose() {
    _uploadTimer?.cancel();
    _progressSubscription?.cancel();
    _stateController.close();
    _statsController.close();
    _queue.dispose();
  }
}
