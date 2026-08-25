import 'dart:collection';

import '../../gallery/data/models/media_item.dart';
import '../../gallery/data/models/upload_task.dart';

/// Priority calculation per PRD Section 9.3.
///
/// Assumption: The PRD specifies the formula but leaves interpretation open.
/// We implement:
///   priorityScore = fileSizeMB + (recencyScore * 10) + (retryPenalty * 50)
/// Lower score = higher priority (min-heap behavior).
/// User-initiated uploads get a -1000 bonus to jump the queue.
/// Newly scanned items (not yet attempted) get priority over retries.
class UploadPriorityCalculator {
  const UploadPriorityCalculator._();

  /// Calculate priority score for a MediaItem being enqueued.
  ///
  /// Lower score = higher priority (processed first).
  static int calculatePriority({
    required MediaItem item,
    required int attemptCount,
    bool isUserInitiated = false,
  }) {
    final fileSizeMB = item.fileSize / (1024 * 1024);

    final daysSinceCreation = DateTime.now().difference(item.createdAt).inDays;
    final recencyScore = 1.0 - (daysSinceCreation / 365).clamp(0.0, 1.0);

    final retryPenalty = attemptCount.toDouble();

    var score = fileSizeMB - (recencyScore * 10) + (retryPenalty * 50);

    if (isUserInitiated) {
      score -= 1000;
    }

    return score.round();
  }

  /// Sort tasks by priority (ascending = highest priority first).
  static List<UploadTask> sortByPriority(List<UploadTask> tasks) {
    return List<UploadTask>.of(tasks)
      ..sort((a, b) => a.priority.compareTo(b.priority));
  }
}

/// Upload queue managing pending upload tasks with priority ordering.
///
/// Per PRD Section 9.3:
/// - PriorityQueue (min-heap by priority score)
/// - Batch size: configurable (default 10)
/// - Concurrency: 1 upload at a time (TDLib limitation)
///
/// Inter-upload throttling is NOT handled here — [BackupEngine] applies
/// `settings.uploadDelayMs` between uploads directly. This class previously
/// carried its own `uploadDelayMs` field that nothing ever read.
class UploadQueue {
  UploadQueue({int batchSize = defaultBatchSize})
    : _batchSize = _sanitizeBatchSize(batchSize);

  /// Batch size used when the caller doesn't specify one.
  static const int defaultBatchSize = 10;

  int _batchSize;

  /// How many queued tasks [getNextBatch] returns at once.
  ///
  /// Kept in step with the user's `uploadBatchSize` preference by
  /// `BackupEngine.updateSettings`. A non-positive value would make
  /// [getNextBatch] return nothing and stall the backup outright, so the
  /// setter floors it at 1.
  int get batchSize => _batchSize;

  set batchSize(int value) => _batchSize = _sanitizeBatchSize(value);

  static int _sanitizeBatchSize(int value) => value < 1 ? 1 : value;

  final SplayTreeSet<UploadTask> _queue = SplayTreeSet<UploadTask>((a, b) {
    final cmp = a.priority.compareTo(b.priority);
    if (cmp != 0) return cmp;
    return a.id.compareTo(b.id);
  });

  final Map<String, UploadTask> _taskIndex = {};

  /// Task IDs grouped by media item, so duplicate checks and removals don't
  /// have to scan the whole queue.
  ///
  /// A set rather than a single ID: [enqueue] refuses duplicates, but tasks
  /// restored from persistence are merged in without going through it.
  final Map<String, Set<String>> _tasksByMediaItem = {};

  /// How many completed tasks exist per file hash, for the dedup check.
  ///
  /// A count rather than a set because the same hash can legitimately
  /// complete more than once (the same photo present in two albums), and
  /// decrementing has to know when the last one is gone.
  final Map<String, int> _completedByHash = {};

  /// Add [task] to the secondary indexes. Call whenever a task enters
  /// [_queue]; [_unindex] is its exact inverse.
  void _index(UploadTask task) {
    _taskIndex[task.id] = task;
    _tasksByMediaItem
        .putIfAbsent(task.mediaItemId, () => <String>{})
        .add(task.id);
    if (task.status == UploadStatus.completed) {
      _completedByHash.update(
        task.fileHash,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
  }

  /// Remove [task] from the secondary indexes.
  void _unindex(UploadTask task) {
    _taskIndex.remove(task.id);

    final siblings = _tasksByMediaItem[task.mediaItemId];
    if (siblings != null) {
      siblings.remove(task.id);
      // Drop the empty set — otherwise the map grows without bound over a
      // long backup run and never shrinks.
      if (siblings.isEmpty) _tasksByMediaItem.remove(task.mediaItemId);
    }

    if (task.status == UploadStatus.completed) {
      final count = _completedByHash[task.fileHash];
      if (count != null) {
        if (count <= 1) {
          _completedByHash.remove(task.fileHash);
        } else {
          _completedByHash[task.fileHash] = count - 1;
        }
      }
    }
  }

  /// All tasks in the queue (queued + in-progress).
  List<UploadTask> get allTasks => List.unmodifiable(_queue);

  /// Tasks waiting to be uploaded.
  List<UploadTask> get queuedTasks =>
      _queue.where((t) => t.status == UploadStatus.queued).toList();

  /// Currently uploading tasks.
  List<UploadTask> get uploadingTasks =>
      _queue.where((t) => t.status == UploadStatus.uploading).toList();

  /// Completed tasks.
  List<UploadTask> get completedTasks =>
      _queue.where((t) => t.status == UploadStatus.completed).toList();

  /// Failed tasks.
  List<UploadTask> get failedTasks =>
      _queue.where((t) => t.status == UploadStatus.failed).toList();

  int get pendingCount => queuedTasks.length;
  int get uploadingCount => uploadingTasks.length;
  int get completedCount => completedTasks.length;
  int get failedCount => failedTasks.length;
  int get totalCount => _queue.length;

  /// Overall progress (0.0 to 1.0).
  double get overallProgress {
    if (_queue.isEmpty) return 0.0;
    final totalProgress = _queue.fold<double>(
      0.0,
      (sum, t) => sum + t.progress,
    );
    return totalProgress / _queue.length;
  }

  /// Get a task by ID.
  UploadTask? getTaskById(String taskId) => _taskIndex[taskId];

  /// Check if a media item already has a task in the queue (duplicate prevention).
  ///
  /// O(1). This was a linear scan of every task, and [enqueue] calls it once
  /// per item — which made [enqueueBatch] quadratic. On a first backup of a
  /// 20k-photo library that is ~200M comparisons before a single byte is
  /// uploaded, all of it on the UI isolate.
  bool hasTaskForMediaItem(String mediaItemId) {
    return _tasksByMediaItem.containsKey(mediaItemId);
  }

  /// The live task for a media item, or null if it has none queued.
  ///
  /// An item can briefly own more than one task id (a retry re-enqueue racing
  /// a stale entry), so prefer the one that is still in flight or waiting over
  /// a finished one — that is the task a caller wanting to watch or drive this
  /// item's upload actually cares about. O(1)-ish: at most a couple of ids.
  UploadTask? getTaskForMediaItem(String mediaItemId) {
    final ids = _tasksByMediaItem[mediaItemId];
    if (ids == null || ids.isEmpty) return null;
    UploadTask? fallback;
    for (final id in ids) {
      final task = _taskIndex[id];
      if (task == null) continue;
      if (task.status == UploadStatus.uploading ||
          task.status == UploadStatus.queued) {
        return task;
      }
      fallback ??= task;
    }
    return fallback;
  }

  /// Check if a file hash already has a completed task (already backed up).
  ///
  /// O(1), for the same reason as [hasTaskForMediaItem].
  bool isAlreadyBackedUp(String fileHash) {
    return _completedByHash.containsKey(fileHash);
  }

  /// Enqueue a new upload task.
  ///
  /// Returns the created task, or null if the media item is already queued.
  UploadTask? enqueue({
    required MediaItem item,
    bool isUserInitiated = false,
    int attemptCount = 0,
  }) {
    if (hasTaskForMediaItem(item.localId)) return null;
    if (isAlreadyBackedUp(item.fileHash)) return null;

    final priority = UploadPriorityCalculator.calculatePriority(
      item: item,
      attemptCount: attemptCount,
      isUserInitiated: isUserInitiated,
    );

    final task = UploadTask(
      id: 'upload_${item.localId}_${DateTime.now().millisecondsSinceEpoch}',
      mediaItemId: item.localId,
      localFilePath: item.filePath,
      fileName: item.fileName,
      fileSize: item.fileSize,
      fileHash: item.fileHash,
      priority: priority,
      createdAt: DateTime.now(),
      // Carry the source asset's real timestamps so the backup caption can
      // record when the media was captured, not when it happened to upload.
      mediaCreatedAt: item.createdAt,
      mediaModifiedAt: item.modifiedAt,
      durationMs: item.durationMs,
    );

    _queue.add(task);
    _index(task);
    return task;
  }

  /// Enqueue multiple items as a batch.
  List<UploadTask> enqueueBatch(
    List<MediaItem> items, {
    bool isUserInitiated = false,
  }) {
    final tasks = <UploadTask>[];
    for (final item in items) {
      final task = enqueue(item: item, isUserInitiated: isUserInitiated);
      if (task != null) tasks.add(task);
    }
    return tasks;
  }

  /// Get the next batch of tasks to process.
  ///
  /// Skips tasks whose retry backoff ([UploadTask.nextAttemptAt]) hasn't
  /// elapsed yet — a failed upload is re-queued with a future attempt time
  /// rather than blocking the batch loop with an inline delay, so healthy
  /// uploads waiting behind it aren't stalled.
  List<UploadTask> getNextBatch() {
    final now = DateTime.now();
    final queued = queuedTasks
        .where((t) => t.nextAttemptAt == null || !t.nextAttemptAt!.isAfter(now))
        .toList();
    if (queued.isEmpty) return const [];
    final end = queued.length.clamp(0, batchSize);
    return queued.sublist(0, end);
  }

  /// Update a task's status and properties.
  ///
  /// Also accepts a task that isn't in the queue yet — that's how tasks
  /// restored from persistence get merged in, bypassing [enqueue]'s duplicate
  /// checks.
  void updateTask(UploadTask updatedTask) {
    // The previous implementation scanned the whole queue with removeWhere,
    // and every progress tick on every upload went through here. Looking the
    // old task up by ID and removing that exact object is O(log n) — and it
    // has to be the old object: _queue is ordered by (priority, id), so
    // removing by the *updated* task would silently miss whenever a
    // priority changed and leave a stale duplicate behind.
    final existing = _taskIndex[updatedTask.id];
    if (existing != null) {
      _queue.remove(existing);
      _unindex(existing);
    }

    _queue.add(updatedTask);
    _index(updatedTask);
  }

  /// Remove a task from the queue.
  void removeTask(String taskId) {
    final task = _taskIndex[taskId];
    if (task != null) {
      _queue.remove(task);
      _unindex(task);
    }
  }

  /// Remove any task associated with [mediaItemId] from the queue.
  ///
  /// Used when the user de-selects a photo/video from backup — the queued
  /// task for it should disappear too, not linger and get uploaded anyway.
  /// No-op if the item isn't queued (e.g. it already finished uploading).
  void removeByMediaItem(String mediaItemId) {
    // Copy the ID set first: _unindex mutates it, and mutating a set while
    // iterating it throws.
    final taskIds = _tasksByMediaItem[mediaItemId]?.toList();
    if (taskIds == null) return;

    for (final taskId in taskIds) {
      final task = _taskIndex[taskId];
      if (task == null) continue;
      _queue.remove(task);
      _unindex(task);
    }
  }

  /// Clear completed and failed tasks.
  void clearFinished() {
    final toRemove = _queue
        .where(
          (t) =>
              t.status == UploadStatus.completed ||
              t.status == UploadStatus.failed,
        )
        .toList();
    for (final task in toRemove) {
      _queue.remove(task);
      _unindex(task);
    }
  }

  /// Retry all failed tasks (reset to queued).
  void retryAllFailed() {
    final failed = failedTasks;
    for (final task in failed) {
      if (task.canRetry) {
        final updated = task.copyWith(
          status: UploadStatus.queued,
          retryCount: task.retryCount + 1,
          error: null,
          progress: 0.0,
          clearNextAttempt: true,
        );
        updateTask(updated);
      }
    }
  }

  /// Retry a single failed task (reset to queued).
  ///
  /// No-op if the task is not failed or has exhausted its retry budget.
  void retryTask(String taskId) {
    final task = _taskIndex[taskId];
    if (task == null || !task.canRetry) return;
    final updated = task.copyWith(
      status: UploadStatus.queued,
      retryCount: task.retryCount + 1,
      error: null,
      progress: 0.0,
      clearNextAttempt: true,
    );
    updateTask(updated);
  }

  /// Pause all queued tasks.
  void pauseAll() {
    for (final task in queuedTasks) {
      updateTask(
        task.copyWith(status: UploadStatus.paused, pausedAt: DateTime.now()),
      );
    }
  }

  /// Resume all paused tasks.
  void resumeAll() {
    final paused = _queue
        .where((t) => t.status == UploadStatus.paused)
        .toList();
    for (final task in paused) {
      updateTask(task.copyWith(status: UploadStatus.queued));
    }
  }

  /// Enforce duplicate prevention: check before upload if the file hash
  /// already has a completed upload somewhere else.
  bool shouldSkipDuplicate(
    UploadTask task,
    List<UploadTask> allCompletedTasks,
  ) {
    return allCompletedTasks.any(
      (t) =>
          t.id != task.id &&
          t.fileHash == task.fileHash &&
          t.status == UploadStatus.completed,
    );
  }

  void dispose() {
    _queue.clear();
    _taskIndex.clear();
    _tasksByMediaItem.clear();
    _completedByHash.clear();
  }
}
