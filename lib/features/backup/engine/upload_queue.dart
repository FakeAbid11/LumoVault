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
/// - Throttle: configurable delay between uploads (default 2000ms)
/// - Concurrency: 1 upload at a time (TDLib limitation)
class UploadQueue {
  UploadQueue({this.batchSize = 10, this.uploadDelayMs = 2000});

  int batchSize;
  int uploadDelayMs;

  final SplayTreeSet<UploadTask> _queue = SplayTreeSet<UploadTask>((a, b) {
    final cmp = a.priority.compareTo(b.priority);
    if (cmp != 0) return cmp;
    return a.id.compareTo(b.id);
  });

  final Map<String, UploadTask> _taskIndex = {};

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
  bool hasTaskForMediaItem(String mediaItemId) {
    return _taskIndex.values.any((t) => t.mediaItemId == mediaItemId);
  }

  /// Check if a file hash already has a completed task (already backed up).
  bool isAlreadyBackedUp(String fileHash) {
    return _queue.any(
      (t) => t.fileHash == fileHash && t.status == UploadStatus.completed,
    );
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
    );

    _queue.add(task);
    _taskIndex[task.id] = task;
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
  List<UploadTask> getNextBatch() {
    final queued = queuedTasks;
    if (queued.isEmpty) return const [];
    final end = queued.length.clamp(0, batchSize);
    return queued.sublist(0, end);
  }

  /// Update a task's status and properties.
  void updateTask(UploadTask updatedTask) {
    _queue.removeWhere((t) => t.id == updatedTask.id);
    _queue.add(updatedTask);
    _taskIndex[updatedTask.id] = updatedTask;
  }

  /// Remove a task from the queue.
  void removeTask(String taskId) {
    final task = _taskIndex.remove(taskId);
    if (task != null) {
      _queue.remove(task);
    }
  }

  /// Remove any task associated with [mediaItemId] from the queue.
  ///
  /// Used when the user de-selects a photo/video from backup — the queued
  /// task for it should disappear too, not linger and get uploaded anyway.
  /// No-op if the item isn't queued (e.g. it already finished uploading).
  void removeByMediaItem(String mediaItemId) {
    final matching = _taskIndex.values
        .where((t) => t.mediaItemId == mediaItemId)
        .toList();
    for (final task in matching) {
      _queue.remove(task);
      _taskIndex.remove(task.id);
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
      _taskIndex.remove(task.id);
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
        );
        updateTask(updated);
      }
    }
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
  }
}
