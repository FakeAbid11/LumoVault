import 'dart:async';
import 'dart:io';

import '../../../../core/tdlib/tdlib_connection_manager.dart';
import '../../../../core/tdlib/tdlib_exception.dart';
import '../models/caption_metadata.dart';
import '../models/transfer_error.dart';

/// Download mode for file retrieval.
enum DownloadMode { thumbnail, original }

/// Progress update for a download operation.
class DownloadProgress {
  const DownloadProgress({
    required this.taskId,
    required this.progress,
    required this.bytesDownloaded,
    required this.totalBytes,
  });
  final String taskId;
  final double progress;
  final int bytesDownloaded;
  final int totalBytes;
}

/// Result of a successful download operation.
class DownloadResult {
  const DownloadResult({
    required this.taskId,
    required this.filePath,
    this.metadata,
  });
  final String taskId;
  final String filePath;
  final CaptionMetadata? metadata;
}

/// Abstract download service interface for dependency injection.
abstract class DownloadService {
  Stream<DownloadProgress> get progressStream;
  Future<DownloadResult> downloadFile({
    required String taskId,
    required int messageId,
    required int channelId,
    DownloadMode mode = DownloadMode.original,
  });
  Future<void> cancelDownload(String taskId);
}

/// Telegram-based download service using TDLib.
///
/// Handles file downloads from the storage channel with progress tracking,
/// cancellation support, and thumbnail/original mode selection.
class TelegramDownloadService implements DownloadService {
  TelegramDownloadService({required this._manager});

  // Requests go through the connection manager (not the raw TdLibClient) so
  // a dropped connection mid-download triggers the same backoff/reconnect
  // logic the rest of the app already relies on, instead of just failing
  // the transfer outright.
  final TdLibConnectionManager _manager;
  final _progressController = StreamController<DownloadProgress>.broadcast();
  final _activeDownloads = <String, Completer<void>>{};

  @override
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  @override
  Future<DownloadResult> downloadFile({
    required String taskId,
    required int messageId,
    required int channelId,
    DownloadMode mode = DownloadMode.original,
  }) async {
    final cancelCompleter = Completer<void>();
    _activeDownloads[taskId] = cancelCompleter;

    try {
      // Get message to extract file info.
      final message = await _manager.sendRequest(
        method: 'getMessage',
        params: {'chat_id': channelId, 'message_id': messageId},
      );

      final content = message['content'] as Map<String, dynamic>?;
      final document = content?['document'] as Map<String, dynamic>?;
      final fileId = document?['id'] as int?;
      final local = document?['local'] as Map<String, dynamic>?;
      final path = local?['path'] as String?;

      // Check if already downloaded.
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          // Parse caption for metadata.
          final captionText =
              (content?['caption'] as Map<String, dynamic>?)?['text']
                  as String?;
          final metadata = captionText != null
              ? CaptionMetadata.fromCaptionString(captionText)
              : null;

          return DownloadResult(
            taskId: taskId,
            filePath: path,
            metadata: metadata,
          );
        }
      }

      // Request file download.
      if (fileId == null) {
        throw TransferError(
          category: TransferErrorCategory.fileNotFound,
          message: 'File ID not found in message',
          occurredAt: DateTime.now(),
        );
      }

      await _manager.sendRequest(
        method: 'downloadFile',
        params: {
          'file_id': fileId,
          'priority': mode == DownloadMode.thumbnail ? 1 : 16,
          'offset': 0,
          'limit': 0,
          'synchronous': false,
        },
      );

      // Wait for TDLib to actually finish the download, emitting real
      // progress along the way, and resolve with the final local path.
      final updatedPath = await _awaitDownloadCompletion(
        taskId: taskId,
        fileId: fileId,
        cancelCompleter: cancelCompleter,
      );
      final captionText =
          (content?['caption'] as Map<String, dynamic>?)?['text'] as String?;
      final metadata = captionText != null
          ? CaptionMetadata.fromCaptionString(captionText)
          : null;

      return DownloadResult(
        taskId: taskId,
        filePath: updatedPath,
        metadata: metadata,
      );
    } on TdLibException catch (e) {
      throw TransferError.fromTdLibError(e.code, e.message);
    } finally {
      _activeDownloads.remove(taskId);
    }
  }

  @override
  Future<void> cancelDownload(String taskId) async {
    final completer = _activeDownloads[taskId];
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _activeDownloads.remove(taskId);
  }

  /// Overall ceiling for a single download. A transfer that reports no
  /// terminal update within this window is treated as stalled and failed,
  /// so the queue can retry it instead of hanging indefinitely.
  static const _downloadTimeout = Duration(minutes: 30);

  /// Listen to TDLib updates until the download for [fileId] finishes,
  /// emitting [DownloadProgress] along the way. Resolves to the final local
  /// file path on success. Honors cancellation via [cancelCompleter] and an
  /// overall [_downloadTimeout].
  ///
  /// Replaces the old `_monitorDownloadProgress`, which listened for a
  /// non-existent `updateFileProgress` type (TDLib actually sends
  /// `updateFile`) and only ever resolved on cancellation — so a real
  /// download never had a signal telling it to stop waiting and just hung
  /// forever.
  Future<String> _awaitDownloadCompletion({
    required String taskId,
    required int fileId,
    required Completer<void> cancelCompleter,
  }) async {
    final completer = Completer<String>();

    late final StreamSubscription<Map<String, dynamic>> subscription;
    subscription = _manager.client.updates.listen((update) {
      if (completer.isCompleted) return;
      final updateType = update['@type'] as String?;
      if (updateType != 'updateFile') return;

      final file = update['file'] as Map<String, dynamic>?;
      if (file == null || file['id'] != fileId) return;

      final local = file['local'] as Map<String, dynamic>?;
      final downloadedSize = local?['downloaded_size'] as int? ?? 0;
      final expectedSize = file['expected_size'] as int? ?? 0;
      final isCompleted = local?['is_downloading_completed'] as bool? ?? false;

      final progress = expectedSize > 0 ? downloadedSize / expectedSize : 0.0;
      _progressController.add(
        DownloadProgress(
          taskId: taskId,
          progress: progress.clamp(0.0, 1.0),
          bytesDownloaded: downloadedSize,
          totalBytes: expectedSize,
        ),
      );

      if (isCompleted && !completer.isCompleted) {
        final path = local?['path'] as String? ?? '';
        completer.complete(path);
      }
    });

    // Cancellation from cancelDownload() -> treat as a cancelled transfer.
    unawaited(
      cancelCompleter.future.then((_) {
        if (!completer.isCompleted) {
          completer.completeError(
            TransferError(
              category: TransferErrorCategory.unknown,
              message: 'Download cancelled',
              occurredAt: DateTime.now(),
            ),
          );
        }
      }),
    );

    try {
      return await completer.future.timeout(
        _downloadTimeout,
        onTimeout: () => throw TransferError(
          category: TransferErrorCategory.network,
          message: 'Download timed out after ${_downloadTimeout.inMinutes} min',
          detail: 'TIMEOUT',
          retryable: true,
          occurredAt: DateTime.now(),
        ),
      );
    } finally {
      await subscription.cancel();
    }
  }
}
