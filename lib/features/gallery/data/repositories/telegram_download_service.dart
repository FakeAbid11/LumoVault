import 'dart:async';
import 'dart:io';

import '../../../../core/tdlib/tdlib_client.dart';
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
  TelegramDownloadService({required this._client});

  final TdLibClient _client;
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
      final message = await _client.sendRequest(
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

      await _client.sendRequest(
        method: 'downloadFile',
        params: {
          'file_id': fileId,
          'priority': mode == DownloadMode.thumbnail ? 1 : 16,
          'offset': 0,
          'limit': 0,
          'synchronous': false,
        },
      );

      // Monitor download progress.
      await _monitorDownloadProgress(taskId, fileId, cancelCompleter);

      // Get updated file info after download.
      final updatedFile = await _client.sendRequest(
        method: 'getFile',
        params: {'file_id': fileId},
      );

      final updatedPath = updatedFile['local']?['path'] as String? ?? '';
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

  /// Monitor download progress by listening to TDLib updates.
  Future<void> _monitorDownloadProgress(
    String taskId,
    int fileId,
    Completer<void> cancelCompleter,
  ) async {
    final subscription = _client.updates.listen((update) {
      final updateType = update['@type'] as String?;
      if (updateType == 'updateFileProgress') {
        final file = update['file'] as Map<String, dynamic>?;
        final updateFileId = file?['id'] as int?;
        if (updateFileId == fileId) {
          final local = file?['local'] as Map<String, dynamic>?;
          final downloadedSize = local?['downloaded_size'] as int? ?? 0;
          final expectedSize = file?['expected_size'] as int? ?? 0;

          final progress = expectedSize > 0
              ? downloadedSize / expectedSize
              : 0.0;
          _progressController.add(
            DownloadProgress(
              taskId: taskId,
              progress: progress.clamp(0.0, 1.0),
              bytesDownloaded: downloadedSize,
              totalBytes: expectedSize,
            ),
          );
        }
      }
    });

    // Wait for cancellation or completion.
    await cancelCompleter.future;
    await subscription.cancel();
  }
}
