import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tdlib/tdlib_client.dart';
import '../../features/gallery/data/models/media_item.dart';
import '../../features/gallery/data/models/transfer_error.dart';
import '../../features/gallery/data/models/upload_task.dart';
import '../../features/gallery/data/repositories/gallery_repository.dart';
import '../../features/gallery/data/repositories/telegram_download_service.dart';
import '../../features/gallery/data/repositories/telegram_upload_service.dart';
import 'gallery_providers.dart';
import 'tdlib_providers.dart';

/// Transfer queue state.
class TransferQueueState {
  const TransferQueueState({
    this.tasks = const [],
    this.isActive = false,
    this.activeUploadCount = 0,
    this.activeDownloadCount = 0,
  });
  final List<UploadTask> tasks;
  final bool isActive;
  final int activeUploadCount;
  final int activeDownloadCount;

  TransferQueueState copyWith({
    List<UploadTask>? tasks,
    bool? isActive,
    int? activeUploadCount,
    int? activeDownloadCount,
  }) {
    return TransferQueueState(
      tasks: tasks ?? this.tasks,
      isActive: isActive ?? this.isActive,
      activeUploadCount: activeUploadCount ?? this.activeUploadCount,
      activeDownloadCount: activeDownloadCount ?? this.activeDownloadCount,
    );
  }

  int get pendingCount =>
      tasks.where((t) => t.status == UploadStatus.queued).length;
  int get uploadingCount =>
      tasks.where((t) => t.status == UploadStatus.uploading).length;
  int get completedCount =>
      tasks.where((t) => t.status == UploadStatus.completed).length;
  int get failedCount =>
      tasks.where((t) => t.status == UploadStatus.failed).length;
  double get overallProgress {
    if (tasks.isEmpty) return 0.0;
    final totalProgress = tasks.fold<double>(0.0, (sum, t) => sum + t.progress);
    return totalProgress / tasks.length;
  }
}

/// Transfer queue notifier for managing upload/download tasks.
class TransferQueueNotifier extends StateNotifier<TransferQueueState> {
  TransferQueueNotifier({
    required this.uploadService,
    required this.downloadService,
    required this.galleryRepository,
    required this.client,
  }) : super(const TransferQueueState()) {
    _listenToProgress();
  }

  final UploadService uploadService;
  final DownloadService downloadService;
  final GalleryRepository galleryRepository;
  final TdLibClient client;

  StreamSubscription<UploadProgress>? _uploadSubscription;
  StreamSubscription<DownloadProgress>? _downloadSubscription;

  void _listenToProgress() {
    _uploadSubscription = uploadService.progressStream.listen((progress) {
      _updateTaskProgress(progress.taskId, progress.progress);
    });

    _downloadSubscription = downloadService.progressStream.listen((progress) {
      _updateTaskProgress(progress.taskId, progress.progress);
    });
  }

  void _updateTaskProgress(String taskId, double progress) {
    state = state.copyWith(
      tasks: state.tasks.map((task) {
        if (task.id == taskId) {
          return task.copyWith(progress: progress);
        }
        return task;
      }).toList(),
    );
  }

  /// Add a media item to the upload queue.
  void addToQueue(MediaItem item) {
    final task = UploadTask(
      id: 'upload_${item.localId}_${DateTime.now().millisecondsSinceEpoch}',
      mediaItemId: item.localId,
      localFilePath: item.filePath,
      fileName: item.fileName,
      fileSize: item.fileSize,
      fileHash: item.fileHash,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(tasks: [...state.tasks, task]);
  }

  /// Add multiple media items to the upload queue.
  void addBatchToQueue(List<MediaItem> items) {
    final newTasks = items
        .map(
          (item) => UploadTask(
            id: 'upload_${item.localId}_${DateTime.now().millisecondsSinceEpoch}',
            mediaItemId: item.localId,
            localFilePath: item.filePath,
            fileName: item.fileName,
            fileSize: item.fileSize,
            fileHash: item.fileHash,
            createdAt: DateTime.now(),
          ),
        )
        .toList();

    state = state.copyWith(tasks: [...state.tasks, ...newTasks]);
  }

  /// Start processing the upload queue.
  Future<void> startQueue() async {
    if (state.isActive) return;

    state = state.copyWith(isActive: true);

    // Process queued tasks.
    for (final task in state.tasks) {
      if (task.status == UploadStatus.queued) {
        await _processUploadTask(task);
      }
    }

    state = state.copyWith(isActive: false);
  }

  /// Pause the upload queue.
  void pauseQueue() {
    state = state.copyWith(isActive: false);
    // Note: Active uploads continue until cancelled.
  }

  /// Resume the upload queue.
  Future<void> resumeQueue() async {
    await startQueue();
  }

  /// Cancel a specific upload task.
  Future<void> cancelTask(String taskId) async {
    await uploadService.cancelUpload(taskId);
    state = state.copyWith(
      tasks: state.tasks.map((task) {
        if (task.id == taskId) {
          return task.copyWith(status: UploadStatus.failed);
        }
        return task;
      }).toList(),
    );
  }

  /// Retry a failed upload task.
  Future<void> retryTask(String taskId) async {
    state = state.copyWith(
      tasks: state.tasks.map((task) {
        if (task.id == taskId && task.canRetry) {
          return task.copyWith(
            status: UploadStatus.queued,
            retryCount: task.retryCount + 1,
            error: null,
            progress: 0.0,
          );
        }
        return task;
      }).toList(),
    );
  }

  /// Clear completed and failed tasks from the queue.
  void clearFinished() {
    state = state.copyWith(
      tasks: state.tasks.where((t) => !t.isTerminal).toList(),
    );
  }

  /// Process a single upload task.
  Future<void> _processUploadTask(UploadTask task) async {
    try {
      // Update task status to uploading.
      state = state.copyWith(
        tasks: state.tasks.map((t) {
          if (t.id == task.id) {
            return t.copyWith(
              status: UploadStatus.uploading,
              startedAt: DateTime.now(),
              lastActivityAt: DateTime.now(),
            );
          }
          return t;
        }).toList(),
      );

      // Get channel ID from storage.
      // TODO: Get actual channel ID from StorageChannelService
      const channelId = 0; // Placeholder

      // Upload the file.
      final result = await uploadService.uploadFile(
        task: task,
        channelId: channelId,
      );

      // Update task status to completed.
      state = state.copyWith(
        tasks: state.tasks.map((t) {
          if (t.id == task.id) {
            return t.copyWith(
              status: UploadStatus.completed,
              progress: 1.0,
              telegramMessageId: result.messageId.toString(),
              telegramFileId: result.fileId.toString(),
              completedAt: DateTime.now(),
            );
          }
          return t;
        }).toList(),
      );
    } on TransferError catch (e) {
      // Update task status to failed.
      state = state.copyWith(
        tasks: state.tasks.map((t) {
          if (t.id == task.id) {
            return t.copyWith(
              status: UploadStatus.failed,
              error: e,
              failedAt: DateTime.now(),
            );
          }
          return t;
        }).toList(),
      );

      // Auto-retry if retryable.
      if (e.retryable && task.retryCount < 3) {
        final delay = Duration(seconds: (task.retryCount + 1) * 5);
        await Future.delayed(delay);
        await retryTask(task.id);
      }
    }
  }

  @override
  void dispose() {
    _uploadSubscription?.cancel();
    _downloadSubscription?.cancel();
    super.dispose();
  }
}

/// Provider for upload service.
final uploadServiceProvider = Provider<UploadService>((ref) {
  final manager = ref.watch(tdLibConnectionManagerProvider);
  return TelegramUploadService(manager: manager);
});

/// Provider for download service.
final downloadServiceProvider = Provider<DownloadService>((ref) {
  final manager = ref.watch(tdLibConnectionManagerProvider);
  return TelegramDownloadService(manager: manager);
});

/// Provider for the transfer queue notifier.
final transferQueueProvider =
    StateNotifierProvider<TransferQueueNotifier, TransferQueueState>((ref) {
      final uploadService = ref.watch(uploadServiceProvider);
      final downloadService = ref.watch(downloadServiceProvider);
      final galleryRepository = ref.watch(galleryRepositoryProvider);
      final client = ref.watch(tdLibClientProvider);

      return TransferQueueNotifier(
        uploadService: uploadService,
        downloadService: downloadService,
        galleryRepository: galleryRepository,
        client: client,
      );
    });

/// Provider for pending upload count.
final pendingUploadCountProvider = Provider<int>((ref) {
  final queue = ref.watch(transferQueueProvider);
  return queue.pendingCount;
});

/// Provider for overall transfer progress.
final transferProgressProvider = Provider<double>((ref) {
  final queue = ref.watch(transferQueueProvider);
  return queue.overallProgress;
});
