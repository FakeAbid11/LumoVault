import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/storage/storage_channel_service.dart';
import '../../../core/storage/transfer_queue_persistence.dart';
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

/// What came of a [BackupEngine.backupItemNow] request.
enum SingleBackupOutcome {
  /// The file is now in the channel.
  uploaded,

  /// Nothing to do — this file was already backed up.
  alreadyBackedUp,

  /// A full backup run is already draining the queue, so the item was put at
  /// the front of it rather than uploaded on a second, concurrent path.
  queued,

  /// A rule the user configured excludes this file (size cap, videos off,
  /// excluded folder). [SingleBackupResult.message] says which.
  skipped,

  /// "Wi-Fi only" is on and there's no Wi-Fi. Re-call with
  /// `allowMobileData: true` to upload over the cellular connection.
  needsMobileDataConfirmation,

  /// The upload was attempted and failed. [SingleBackupResult.message] carries
  /// the reason.
  failed,
}

/// Outcome of backing up one item on demand.
class SingleBackupResult {
  const SingleBackupResult(this.outcome, {this.message});
  final SingleBackupOutcome outcome;
  final String? message;
}

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

  /// Total items in the *current* upload queue/batch — not
  /// [totalMediaItems], which is every item ever scanned on the device
  /// across all sessions. [progressDisplay] must match this, or the header
  /// ("Uploading (X of Y)") disagrees with the Pending/Uploading/Completed/
  /// Failed cards directly below it, which are all queue-scoped.
  int get queueTotal =>
      backedUpCount + pendingCount + uploadingCount + failedCount;

  String get progressDisplay {
    if (queueTotal == 0) return 'No items';
    return '$backedUpCount of $queueTotal';
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
    this.onBackupTimestampsChanged,
    this.ensureTdLibConnected,
    this.queuePersistence,
    this.videoPosterGenerator,
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
    _ready = _restorePersistedQueue();
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

  /// Called whenever the engine refreshes [BackupSettings.lastBackupAt] or
  /// [BackupSettings.lastScanAt], so the caller can persist them into
  /// [AppSettings] and have "last backup"/"last scan" survive a restart.
  final void Function(DateTime? lastBackupAt, DateTime? lastScanAt)?
  onBackupTimestampsChanged;

  /// Ensures TDLib is initialized and connected before any upload attempt.
  ///
  /// TDLib only gets initialized via [tdLibInitializedProvider], which was
  /// only ever read from inside the onboarding "Connect Telegram" screens
  /// and [accountInfoProvider] (read by the Account settings screen). A
  /// returning, already-authenticated user who goes straight from launch to
  /// the timeline to the backup dashboard never visits either of those, so
  /// TDLib was never initialized — every upload attempt hit the raw
  /// client's own "not initialized" guard and retried forever, since that
  /// failure never goes away on its own. Calling this before the first
  /// upload attempt guarantees the connection exists regardless of
  /// navigation order.
  final Future<void> Function()? ensureTdLibConnected;

  /// Disk persistence for the upload queue so an app kill mid-backup doesn't
  /// silently drop queued/in-flight work. Optional so tests and lightweight
  /// consumers can construct an engine without touching the filesystem.
  final TransferQueuePersistence? queuePersistence;

  /// Generates a poster frame for a video upload and returns its local file
  /// path (or null on failure / non-video). Injected so the engine stays free
  /// of `photo_manager` and unit tests run without a platform gallery — when
  /// null (the default), video uploads simply go up without a thumbnail.
  final Future<String?> Function(UploadTask task)? videoPosterGenerator;

  /// Completes once the persisted queue has been merged back in.
  ///
  /// The restore is kicked off from the constructor, which can't await. It
  /// used to be fire-and-forget, so [scanAndEnqueue] and [startBackup] could
  /// both run against an empty queue while the restore was still reading from
  /// disk — the scan would re-enqueue items that were already persisted, and
  /// the restore would then overwrite those fresh tasks (or be overwritten by
  /// the next `_persistQueue` snapshot, losing the interrupted work outright).
  /// Both entry points now await this first.
  late final Future<void> _ready;

  /// Completes once any persisted upload queue has been restored.
  ///
  /// The public entry points await this themselves; it's exposed for callers
  /// that need to know the engine is fully warmed up (e.g. tests).
  Future<void> get ready => _ready;

  /// The upload queue, sized from the user's `uploadBatchSize` preference.
  ///
  /// `late` so the initializer can read [settings] — a plain field
  /// initializer can't reference an instance field. Kept in step with
  /// preference changes by [updateSettings]; before that wiring existed the
  /// queue was constructed with no arguments and the batch size was
  /// permanently 10 no matter what the settings screens displayed.
  late final UploadQueue _queue = UploadQueue(
    batchSize: settings.uploadBatchSize,
  );
  BackupEngineState _state = BackupEngineState.idle;
  BackupStats _stats = const BackupStats();
  bool _isPaused = false;
  BackupEnvironment _environment = const BackupEnvironment();

  StreamSubscription<UploadProgress>? _progressSubscription;
  final _stateController = StreamController<BackupEngineState>.broadcast();
  final _statsController = StreamController<BackupStats>.broadcast();

  /// Wakes the queue after a retryable failure's backoff elapses. A failed
  /// task is re-queued with a future [UploadTask.nextAttemptAt] instead of
  /// sleeping inline in the batch loop, so this timer is what brings the
  /// engine back to drain the deferred retry once its backoff is up.
  Timer? _retryTimer;
  DateTime? _retryWakeAt;

  UploadQueue get queue => _queue;
  BackupEngineState get state => _state;
  BackupStats get stats => _stats;
  bool get isPaused => _isPaused;

  Stream<BackupEngineState> get stateStream => _stateController.stream;
  Stream<BackupStats> get statsStream => _statsController.stream;

  /// Update the backup settings.
  void updateSettings(BackupSettings newSettings) {
    settings = newSettings;
    // Propagate the batch size — the queue keeps its own copy, so without
    // this a change to the preference had no effect until app restart (and
    // not even then, since the queue used to ignore the setting entirely).
    _queue.batchSize = newSettings.uploadBatchSize;
  }

  /// Update the environment state (connectivity, battery, etc.).
  void updateEnvironment(BackupEnvironment environment) {
    _environment = environment;
  }

  /// Scan device for new media and enqueue items for backup.
  Future<void> scanAndEnqueue() async {
    // Must not enqueue against a half-restored queue: the dedup checks below
    // consult _queue, so scanning first would re-enqueue persisted work.
    await _ready;
    if (_state == BackupEngineState.scanning) return;

    _setState(BackupEngineState.scanning);

    try {
      // No folders selected — nothing to back up.
      if (settings.includedFolders.isEmpty) {
        _setState(BackupEngineState.idle);
        return;
      }

      // Was scanDevice() — a full re-scan that re-reads and re-hashes every
      // file on the device again, even though the timeline screen already
      // scanned everything moments earlier via scanDeviceIncremental. Using
      // the incremental scan here too avoids doing that expensive work
      // twice, and avoids re-triggering the same freeze-prone full-album
      // fetch path independently of whatever the timeline screen is doing.
      await galleryRepository.scanDeviceIncremental(
        includedFolders: settings.includedFolders,
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
      onBackupTimestampsChanged?.call(
        settings.lastBackupAt,
        settings.lastScanAt,
      );
    } catch (e) {
      _setState(BackupEngineState.error);
      rethrow;
    }
  }

  /// Start the backup process.
  Future<void> startBackup() async {
    await _ready;
    if (_isPaused) return;
    if (_state == BackupEngineState.uploading) return;

    try {
      await ensureTdLibConnected?.call();
    } catch (e) {
      debugPrint('[BackupEngine] TDLib connection failed: $e');
      _setState(BackupEngineState.error);
      return;
    }

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

  /// Retry a single failed upload task.
  ///
  /// No-op if the task isn't failed or has exhausted its retry budget.
  Future<void> retryTask(String taskId) async {
    _queue.retryTask(taskId);
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
    if (item.isExcluded || item.isTrashed || item.isHidden) return;
    if (item.status == MediaStatus.uploaded) return;
    _queue.enqueue(item: item, isUserInitiated: true);
    _updateStats();
  }

  /// Enqueue a single item the user just selected for backup, so it shows up
  /// on the dashboard immediately instead of only after the next full
  /// "Start Backup" scan. Skips items that are excluded, hidden, trashed,
  /// already uploaded, or already queued (enqueue itself dedups the last
  /// case).
  void enqueueSelectedItem(MediaItem item) {
    if (item.isExcluded || item.isTrashed || item.isHidden) return;
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

  /// Back up one item right now, without a full scan or a queue drain.
  ///
  /// This is the "back up this photo" action in the media viewer: the user
  /// pointed at one specific file and asked for it, so it uploads that file and
  /// nothing else. [startBackup] is the wrong tool for that — it drains the
  /// entire queue, which on a first run means the whole library.
  ///
  /// Which gates still apply, and why:
  /// - Per-item content rules ([BackupScheduler.evaluateMediaItem]: size cap,
  ///   photos/videos toggles, folder include/exclude) DO apply. Those describe
  ///   what the user considers backup-worthy, so honouring them is honouring
  ///   the request.
  /// - The automation gates ([BackupScheduler.evaluate]: the auto-backup
  ///   toggle, charging-only, the low-battery floor) do NOT. They exist to keep
  ///   *unattended* backup from ambushing the device; an explicit tap is not
  ///   unattended, and refusing it would leave the button dead with no
  ///   explanation the user could act on.
  /// - "Wi-Fi only" is the exception among those: ignoring it silently spends
  ///   the user's mobile data. So it returns
  ///   [SingleBackupOutcome.needsMobileDataConfirmation] and lets the caller
  ///   confirm, then re-call with [allowMobileData].
  Future<SingleBackupResult> backupItemNow(
    MediaItem item, {
    bool allowMobileData = false,
  }) async {
    await _ready;

    if (item.status == MediaStatus.uploaded) {
      return const SingleBackupResult(SingleBackupOutcome.alreadyBackedUp);
    }

    // Another item with these exact bytes already went up — record the mapping
    // locally instead of uploading a duplicate, same as [_uploadTask] does.
    if (_queue.isAlreadyBackedUp(item.fileHash)) {
      await galleryRepository.markUploaded(localId: item.localId);
      return const SingleBackupResult(SingleBackupOutcome.alreadyBackedUp);
    }

    final include = BackupScheduler.evaluateMediaItem(
      item: item,
      settings: settings,
    );
    if (!include.included) {
      return SingleBackupResult(
        SingleBackupOutcome.skipped,
        message: include.reason,
      );
    }

    if (settings.wifiOnly &&
        !_environment.isWifiConnected &&
        !allowMobileData) {
      return const SingleBackupResult(
        SingleBackupOutcome.needsMobileDataConfirmation,
        message: 'Wi-Fi only is on and this device is not on Wi-Fi.',
      );
    }

    // Reuse the queue entry if one exists so progress, retries and stats all
    // stay on a single task; otherwise create one. isUserInitiated gives it the
    // priority bonus, which matters for the `queued` path below.
    final task =
        _queue.getTaskForMediaItem(item.localId) ??
        _queue.enqueue(item: item, isUserInitiated: true);
    if (task == null) {
      return const SingleBackupResult(
        SingleBackupOutcome.failed,
        message: 'Could not queue this file for backup.',
      );
    }
    _updateStats();

    // A full run is already uploading. Starting a second concurrent upload
    // loop here would race _processQueue for the same task, so hand the item
    // over to the run that's already going — its user-initiated priority puts
    // it at the front of the next batch.
    if (_state == BackupEngineState.uploading || _isPaused) {
      return const SingleBackupResult(SingleBackupOutcome.queued);
    }

    try {
      await ensureTdLibConnected?.call();
    } catch (e) {
      debugPrint('[BackupEngine] TDLib connection failed: $e');
      return const SingleBackupResult(
        SingleBackupOutcome.failed,
        message: 'Could not connect to Telegram.',
      );
    }

    _setState(BackupEngineState.uploading);
    try {
      await _uploadTask(task);
    } finally {
      // Back to idle regardless — this path uploads exactly one file, so the
      // engine must not be left advertising `uploading` afterwards.
      _setState(BackupEngineState.idle);
      _updateStats();
    }

    final finished = _queue.getTaskById(task.id);
    if (finished == null || finished.status == UploadStatus.completed) {
      // Completed tasks are pruned from the persisted queue, so a missing task
      // here means it finished and was cleaned up.
      return const SingleBackupResult(SingleBackupOutcome.uploaded);
    }
    if (finished.status == UploadStatus.queued) {
      // _uploadTask re-queued it for a retry after a retryable failure.
      return SingleBackupResult(
        SingleBackupOutcome.queued,
        message: finished.error?.message,
      );
    }
    return SingleBackupResult(
      SingleBackupOutcome.failed,
      message: finished.error?.message ?? 'Upload failed.',
    );
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
      onBackupTimestampsChanged?.call(
        settings.lastBackupAt,
        settings.lastScanAt,
      );
      _setState(BackupEngineState.idle);
    }

    _updateStats();
  }

  /// Arm [_retryTimer] to wake the queue when a deferred retry's backoff
  /// elapses. If a wake is already scheduled sooner than [wakeAt], the
  /// existing timer is kept so several failures collapse into a single wake.
  void _scheduleRetryWake(DateTime wakeAt) {
    if (_disposed) return;
    if (_retryTimer != null &&
        _retryWakeAt != null &&
        !_retryWakeAt!.isAfter(wakeAt)) {
      return;
    }
    _retryTimer?.cancel();
    _retryWakeAt = wakeAt;
    final delay = wakeAt.difference(DateTime.now());
    _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _retryTimer = null;
      _retryWakeAt = null;
      if (!_isPaused && !_disposed) {
        unawaited(startBackup());
      }
    });
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
      await galleryRepository.markUploaded(localId: task.mediaItemId);
      return;
    }

    _queue.updateTask(
      task.copyWith(status: UploadStatus.uploading, startedAt: DateTime.now()),
    );
    _updateStats();

    try {
      final channelId = await _resolveChannelId();

      // Video documents get no auto-thumbnail from Telegram; generate a poster
      // and attach it so the item shows a real thumbnail in the timeline.
      // Best-effort — a failed poster must never block the upload itself.
      String? posterPath;
      if (videoPosterGenerator != null && _isVideoFileName(task.fileName)) {
        try {
          posterPath = await videoPosterGenerator!(task);
          debugPrint(
            '[BackupEngine] Video ${task.fileName}: poster '
            '${posterPath == null ? 'NOT generated (null)' : 'generated at $posterPath'}',
          );
        } catch (e) {
          debugPrint(
            '[BackupEngine] Poster generation failed for '
            '${task.fileName}: $e',
          );
        }
      }

      final UploadResult result;
      try {
        result = await uploadService.uploadFile(
          task: posterPath != null
              ? task.copyWith(thumbnailPath: posterPath)
              : task,
          channelId: channelId,
        );
      } finally {
        if (posterPath != null) {
          try {
            final f = File(posterPath);
            if (f.existsSync()) f.deleteSync();
          } catch (_) {
            // Temp poster cleanup is best-effort; the OS reclaims temp dirs.
          }
        }
      }

      // Persist the DB state BEFORE completing the queue entry. Completed
      // tasks are dropped from the persisted transfer queue, so completing
      // the task first opens a crash window where the file is already in
      // Telegram but the DB still says `pending` — the next scan would then
      // re-upload it, duplicating it in the channel.
      try {
        await galleryRepository.markUploaded(
          localId: task.mediaItemId,
          telegramMessageId: result.messageId.toString(),
          telegramFileId: result.fileId.toString(),
        );
      } catch (e) {
        // The file made it to Telegram but the local record failed. Keep
        // the task failed (retryable by the user) instead of silently
        // losing the mapping between the media item and its channel copy.
        debugPrint(
          '[BackupEngine] Uploaded ${task.fileName} but failed to save the '
          'result locally: $e',
        );
        _queue.updateTask(
          task.copyWith(
            status: UploadStatus.failed,
            error: TransferError(
              category: TransferErrorCategory.unknown,
              message: 'Uploaded, but failed to save the result locally',
              detail: e.toString(),
              occurredAt: DateTime.now(),
            ),
            failedAt: DateTime.now(),
          ),
        );
        _updateStats();
        return;
      }

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
      // Retry budget: a task gets at most UploadTask.maxAttempts attempts
      // (checked against the pre-increment retryCount). This is independent
      // of uploadBatchSize, which is a throughput knob, not a retry limit.
      final shouldRetry =
          e.retryable && task.retryCount < UploadTask.maxAttempts;

      // Previously only the retry countdown was logged, never the error
      // itself — so a stuck upload showed nothing in logcat beyond
      // "Retrying in Ns" with no way to tell what was actually failing.
      debugPrint(
        '[BackupEngine] Upload failed for ${task.fileName}: '
        'category=${e.category} detail=${e.detail} retryable=${e.retryable} '
        'message=${e.message}',
      );

      _queue.updateTask(
        task.copyWith(
          status: shouldRetry ? UploadStatus.queued : UploadStatus.failed,
          error: e,
          failedAt: DateTime.now(),
          retryCount: task.retryCount + 1,
        ),
      );

      if (shouldRetry) {
        // Defer the retry instead of sleeping here: an inline
        // `await Future.delayed(backoff)` sat in the `for (task in batch)`
        // loop, so one flaky upload stalled every healthy upload queued
        // behind it for the whole backoff. Stamp the task with a future
        // attempt time (getNextBatch skips it until then) and arm a timer to
        // wake the queue when the soonest backoff elapses; the loop moves on
        // to the next task immediately.
        final backoff = BackupScheduler.calculateBackoff(task.retryCount);
        final wakeAt = DateTime.now().add(backoff);
        _queue.updateTask(
          (_queue.getTaskById(task.id) ?? task).copyWith(nextAttemptAt: wakeAt),
        );
        debugPrint(
          '[BackupEngine] Deferring retry of ${task.fileName} for '
          '${backoff.inSeconds}s',
        );
        _scheduleRetryWake(wakeAt);
      }
    } catch (e) {
      // Unexpected error (plugin crash, platform exception, etc.): convert
      // it into a failed task so the queue keeps moving, instead of letting
      // the exception abort _processQueue with the engine stuck in
      // `uploading` and every remaining task frozen.
      debugPrint(
        '[BackupEngine] Unexpected failure uploading ${task.fileName}: $e',
      );
      _queue.updateTask(
        task.copyWith(
          status: UploadStatus.failed,
          error: TransferError(
            category: TransferErrorCategory.unknown,
            message: 'Unexpected upload failure',
            detail: e.toString(),
            occurredAt: DateTime.now(),
          ),
          failedAt: DateTime.now(),
        ),
      );
      _updateStats();
    }
  }

  /// True when [fileName]'s extension marks it as a video, used to decide
  /// whether to generate an upload poster. Extension-based (the queue task
  /// carries no mime type) and matches the container types the app records.
  bool _isVideoFileName(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return const {
      'mp4',
      'mov',
      'mkv',
      'webm',
      'avi',
      'm4v',
      '3gp',
    }.contains(ext);
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
      case StorageChannelNotFound():
        // findOrCreateChannel only returns this if creation was somehow
        // skipped. Uploading without a confirmed channel is not an option,
        // so fail retryably rather than falling through with no channel id.
        throw TransferError(
          category: TransferErrorCategory.unknown,
          message: 'Could not set up Telegram storage: no channel available',
          retryable: true,
          occurredAt: DateTime.now(),
        );
    }
  }

  void _setState(BackupEngineState newState) {
    if (_disposed) return;
    _state = newState;
    _stateController.add(newState);
  }

  /// Re-enqueue whatever was persisted the last time the app was alive.
  ///
  /// In-flight tasks were mid-upload when the process died, so
  /// [TransferQueuePersistence.mergeQueues] resets them to `queued` for a
  /// clean retry; completed items are skipped (drift already knows they
  /// uploaded). Runs at most once per engine instance — the caller holds the
  /// only reference and calls this exactly once from the constructor.
  Future<void> _restorePersistedQueue() async {
    final persistence = queuePersistence;
    if (persistence == null) return;

    try {
      final persisted = await persistence.loadTasks();
      if (persisted.isEmpty) return;
      final merged = persistence.mergeQueues(
        live: _queue.allTasks,
        persisted: persisted,
      );
      for (final task in merged) {
        _queue.updateTask(task);
      }
      _updateStats();
    } catch (e) {
      debugPrint('[BackupEngine] Failed to restore persisted queue: $e');
    }
  }

  /// Write the current queue to disk. Fire-and-forget: persistence is
  /// best-effort and must never block or crash the upload path.
  void _persistQueue() {
    final persistence = queuePersistence;
    if (persistence == null) return;
    unawaited(
      persistence.saveTasks(_queue.allTasks).catchError((Object e) {
        debugPrint('[BackupEngine] Failed to persist queue: $e');
      }),
    );
  }

  void _updateStats() {
    // An upload continuation can resolve after teardown; without this the
    // stats controller throws on add, and _persistQueue below would write
    // the disposed (cleared) queue over the real persisted one.
    if (_disposed) return;
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
    _persistQueue();
  }

  bool _disposed = false;

  /// Whether [dispose] has already run.
  ///
  /// Guards the stats/state controllers: `add` on a closed StreamController
  /// throws, and both [_setState] and [_updateStats] can be reached from an
  /// in-flight upload continuation that resolves after teardown.
  bool get isDisposed => _disposed;

  /// Releases the engine's stream controllers, progress subscription, and
  /// in-memory queue.
  ///
  /// Idempotent — a second call is a no-op rather than a throw on the
  /// already-closed controllers.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    _progressSubscription?.cancel();
    _stateController.close();
    _statsController.close();
    _queue.dispose();
  }
}
