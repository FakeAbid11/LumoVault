import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/gallery/data/models/upload_task.dart';
import '../../features/gallery/data/models/transfer_error.dart';

/// Persists the transfer queue to disk so uploads/downloads can resume
/// after app restart.
///
/// Queue state is stored as a JSON file at `<app_support>/transfer_queue.json`.
/// Each entry captures enough information to reconstruct and resume the task.
class TransferQueuePersistence {
  TransferQueuePersistence._();

  static TransferQueuePersistence? _instance;
  static TransferQueuePersistence get instance =>
      _instance ??= TransferQueuePersistence._();

  File? _file;

  /// Initialize the persistence file.
  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/transfer_queue.json');
  }

  /// Save the current queue of tasks.
  Future<void> saveTasks(List<UploadTask> tasks) async {
    if (_file == null) await initialize();

    final jsonList = tasks.map((t) => _taskToJson(t)).toList();
    final data = {
      'version': 1,
      'savedAt': DateTime.now().toIso8601String(),
      'tasks': jsonList,
    };

    await _file!.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );

    debugPrint('[TransferQueuePersistence] Saved ${tasks.length} tasks');
  }

  /// Load persisted tasks.
  Future<List<UploadTask>> loadTasks() async {
    if (_file == null) await initialize();
    if (!await _file!.exists()) return [];

    try {
      final content = await _file!.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final version = data['version'] as int? ?? 0;
      if (version < 1) return [];

      final taskList = data['tasks'] as List<dynamic>? ?? [];
      return taskList
          .map((t) => _taskFromJson(t as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[TransferQueuePersistence] Failed to load: $e');
      return [];
    }
  }

  /// Clear persisted queue.
  Future<void> clear() async {
    if (_file == null) await initialize();
    if (await _file!.exists()) {
      await _file!.delete();
    }
  }

  /// Merge persisted tasks with live queue.
  ///
  /// Returns tasks from [persisted] that don't already exist in [live],
  /// with status reset to queued for any that were in-progress.
  List<UploadTask> mergeQueues({
    required List<UploadTask> live,
    required List<UploadTask> persisted,
  }) {
    final liveIds = live.map((t) => t.id).toSet();
    final merged = List<UploadTask>.from(live);

    for (final task in persisted) {
      if (liveIds.contains(task.id)) continue;

      // Reset in-progress tasks to queued.
      if (task.status == UploadStatus.uploading) {
        merged.add(
          task.copyWith(
            status: UploadStatus.queued,
            progress: 0,
            clearError: () => null,
          ),
        );
      } else if (task.status == UploadStatus.queued ||
          task.status == UploadStatus.failed) {
        merged.add(task);
      }
      // Skip completed and paused tasks.
    }

    return merged;
  }

  Map<String, dynamic> _taskToJson(UploadTask task) {
    return {
      'id': task.id,
      'mediaItemId': task.mediaItemId,
      'localFilePath': task.localFilePath,
      'fileName': task.fileName,
      'fileSize': task.fileSize,
      'fileHash': task.fileHash,
      'telegramFileId': task.telegramFileId,
      'telegramMessageId': task.telegramMessageId,
      'status': task.status.name,
      'progress': task.progress,
      'retryCount': task.retryCount,
      'priority': task.priority,
      'createdAt': task.createdAt.toIso8601String(),
      'startedAt': task.startedAt?.toIso8601String(),
      'completedAt': task.completedAt?.toIso8601String(),
      'failedAt': task.failedAt?.toIso8601String(),
      'pausedAt': task.pausedAt?.toIso8601String(),
      'lastActivityAt': task.lastActivityAt?.toIso8601String(),
      if (task.error != null)
        'error': {
          'category': task.error!.category.name,
          'message': task.error!.message,
          'detail': task.error!.detail,
          'retryable': task.error!.retryable,
          'retryAfterSeconds': task.error!.retryAfterSeconds,
          'occurredAt': task.error!.occurredAt.toIso8601String(),
        },
    };
  }

  UploadTask _taskFromJson(Map<String, dynamic> json) {
    return UploadTask(
      id: json['id'] as String,
      mediaItemId: json['mediaItemId'] as String,
      localFilePath: json['localFilePath'] as String,
      fileName: json['fileName'] as String,
      fileSize: json['fileSize'] as int,
      fileHash: json['fileHash'] as String,
      telegramFileId: json['telegramFileId'] as String?,
      telegramMessageId: json['telegramMessageId'] as String?,
      status: UploadStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => UploadStatus.queued,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      retryCount: json['retryCount'] as int? ?? 0,
      priority: json['priority'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      failedAt: json['failedAt'] != null
          ? DateTime.parse(json['failedAt'] as String)
          : null,
      pausedAt: json['pausedAt'] != null
          ? DateTime.parse(json['pausedAt'] as String)
          : null,
      lastActivityAt: json['lastActivityAt'] != null
          ? DateTime.parse(json['lastActivityAt'] as String)
          : null,
      error: json['error'] != null
          ? TransferError(
              category: TransferErrorCategory.values.firstWhere(
                (c) =>
                    c.name ==
                    (json['error'] as Map<String, dynamic>)['category'],
                orElse: () => TransferErrorCategory.unknown,
              ),
              message:
                  (json['error'] as Map<String, dynamic>)['message'] as String,
              detail:
                  (json['error'] as Map<String, dynamic>)['detail'] as String?,
              retryable:
                  (json['error'] as Map<String, dynamic>)['retryable']
                      as bool? ??
                  false,
              retryAfterSeconds:
                  (json['error'] as Map<String, dynamic>)['retryAfterSeconds']
                      as int?,
              occurredAt: DateTime.parse(
                (json['error'] as Map<String, dynamic>)['occurredAt'] as String,
              ),
            )
          : null,
    );
  }
}
