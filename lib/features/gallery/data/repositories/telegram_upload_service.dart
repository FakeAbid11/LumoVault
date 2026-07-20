import 'dart:async';
import 'dart:io';

import '../../../../core/tdlib/tdlib_client.dart';
import '../../../../core/tdlib/tdlib_exception.dart';
import '../models/caption_metadata.dart';
import '../models/transfer_error.dart';
import '../models/upload_task.dart';

/// Progress update for an upload operation.
class UploadProgress {
  const UploadProgress({
    required this.taskId,
    required this.progress,
    required this.bytesUploaded,
    required this.totalBytes,
  });
  final String taskId;
  final double progress;
  final int bytesUploaded;
  final int totalBytes;
}

/// Result of a successful upload operation.
class UploadResult {
  const UploadResult({
    required this.taskId,
    required this.messageId,
    required this.fileId,
  });
  final String taskId;
  final int messageId;
  final int fileId;
}

/// Abstract upload service interface for dependency injection.
abstract class UploadService {
  Stream<UploadProgress> get progressStream;
  Future<UploadResult> uploadFile({
    required UploadTask task,
    required int channelId,
  });
  Future<void> cancelUpload(String taskId);
}

/// Telegram-based upload service using TDLib.
///
/// Handles file uploads to the storage channel with progress tracking,
/// cancellation support, and error recovery per PRD Section 5.
class TelegramUploadService implements UploadService {
  TelegramUploadService({required this._client});

  final TdLibClient _client;
  final _progressController = StreamController<UploadProgress>.broadcast();
  final _activeUploads = <String, Completer<void>>{};

  @override
  Stream<UploadProgress> get progressStream => _progressController.stream;

  @override
  Future<UploadResult> uploadFile({
    required UploadTask task,
    required int channelId,
  }) async {
    final cancelCompleter = Completer<void>();
    _activeUploads[task.id] = cancelCompleter;

    try {
      final file = File(task.localFilePath);
      if (!await file.exists()) {
        throw TransferError(
          category: TransferErrorCategory.fileNotFound,
          message: 'File not found: ${task.localFilePath}',
          occurredAt: DateTime.now(),
        );
      }

      // Build caption with metadata.
      final caption = CaptionMetadata(
        mediaItemId: task.mediaItemId,
        fileHash: task.fileHash,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        backedUpAt: DateTime.now(),
        fileSize: task.fileSize,
      );

      // Send file to TDLib.
      final result = await _client.sendRequest(
        method: 'sendMessage',
        params: {
          'chat_id': channelId,
          'input_message_content': {
            '@type': 'inputMessageDocument',
            'document': {'@type': 'inputFileLocal', 'path': task.localFilePath},
            'caption': {
              '@type': 'formattedText',
              'text': caption.toCaptionString(),
            },
            'disable_content_type_detection': false,
          },
        },
      );

      // Monitor upload progress via TDLib updates.
      await _monitorUploadProgress(task.id, task.fileSize, cancelCompleter);

      // Extract message ID and file ID from response.
      final messageId = result['id'] as int? ?? 0;
      final document = result['document'] as Map<String, dynamic>?;
      final fileId = document?['document']?['id'] as int? ?? 0;

      return UploadResult(
        taskId: task.id,
        messageId: messageId,
        fileId: fileId,
      );
    } on TdLibException catch (e) {
      throw TransferError.fromTdLibError(e.code, e.message);
    } finally {
      _activeUploads.remove(task.id);
    }
  }

  @override
  Future<void> cancelUpload(String taskId) async {
    final completer = _activeUploads[taskId];
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _activeUploads.remove(taskId);
  }

  /// Monitor upload progress by listening to TDLib updates.
  Future<void> _monitorUploadProgress(
    String taskId,
    int totalBytes,
    Completer<void> cancelCompleter,
  ) async {
    final subscription = _client.updates.listen((update) {
      final updateType = update['@type'] as String?;
      if (updateType == 'updateFileProgress') {
        final file = update['file'] as Map<String, dynamic>?;
        final fileId = file?['id'] as int?;
        final remote = file?['remote'] as Map<String, dynamic>?;
        final uploadedSize = remote?['uploaded_size'] as int? ?? 0;

        if (fileId != null) {
          final progress = totalBytes > 0 ? uploadedSize / totalBytes : 0.0;
          _progressController.add(
            UploadProgress(
              taskId: taskId,
              progress: progress.clamp(0.0, 1.0),
              bytesUploaded: uploadedSize,
              totalBytes: totalBytes,
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
