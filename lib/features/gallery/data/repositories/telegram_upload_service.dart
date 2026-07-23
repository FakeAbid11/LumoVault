import 'dart:async';
import 'dart:io';

import '../../../../core/tdlib/tdlib_connection_manager.dart';
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
  TelegramUploadService({required this._manager});

  // Requests go through the connection manager (not the raw TdLibClient) so
  // a dropped connection mid-upload triggers the same backoff/reconnect
  // logic the rest of the app already relies on, instead of just failing
  // the transfer outright.
  final TdLibConnectionManager _manager;
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

      // Send file to TDLib. The returned message is a *provisional* one with
      // a temporary id (`sending_state` is still pending); the real upload
      // happens asynchronously and is reported via updates. So we start
      // listening BEFORE we act on the send result.
      final result = await _manager.sendRequest(
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

      // The temporary message id we need to correlate the async
      // send-succeeded/send-failed updates back to this upload.
      final temporaryMessageId = result['id'] as int? ?? 0;
      final document = result['content']?['document'] as Map<String, dynamic>?;
      final sentFileId = document?['document']?['id'] as int?;

      // Wait for TDLib to actually finish (or fail) the upload, emitting
      // real progress along the way. This replaces the old code, which
      // awaited a completer nothing ever completed on success (so it hung
      // forever) and listened for a non-existent 'updateFileProgress' type
      // (so progress never moved off 0%).
      final finalMessageId = await _awaitUploadCompletion(
        taskId: task.id,
        temporaryMessageId: temporaryMessageId,
        fileId: sentFileId,
        totalBytes: task.fileSize,
        cancelCompleter: cancelCompleter,
      );

      return UploadResult(
        taskId: task.id,
        messageId: finalMessageId,
        fileId: sentFileId ?? 0,
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

  /// Overall ceiling for a single upload. A transfer that reports no
  /// terminal update within this window is treated as stalled and failed,
  /// so the queue can retry it instead of hanging indefinitely.
  static const _uploadTimeout = Duration(minutes: 30);

  /// Listen to TDLib updates until the send for [temporaryMessageId]
  /// succeeds or fails, emitting [UploadProgress] from `updateFile` events
  /// for [fileId] along the way. Resolves to the *permanent* message id on
  /// success. Honors cancellation via [cancelCompleter] and an overall
  /// [_uploadTimeout].
  Future<int> _awaitUploadCompletion({
    required String taskId,
    required int temporaryMessageId,
    required int? fileId,
    required int totalBytes,
    required Completer<void> cancelCompleter,
  }) async {
    final completer = Completer<int>();

    late final StreamSubscription<Map<String, dynamic>> subscription;
    subscription = _manager.client.updates.listen((update) {
      if (completer.isCompleted) return;
      final type = update['@type'] as String?;

      switch (type) {
        // Progress for the file being uploaded.
        case 'updateFile':
          final file = update['file'] as Map<String, dynamic>?;
          if (file == null) return;
          if (fileId != null && file['id'] != fileId) return;
          final remote = file['remote'] as Map<String, dynamic>?;
          final uploadedSize = remote?['uploaded_size'] as int? ?? 0;
          final progress = totalBytes > 0 ? uploadedSize / totalBytes : 0.0;
          _progressController.add(
            UploadProgress(
              taskId: taskId,
              progress: progress.clamp(0.0, 1.0),
              bytesUploaded: uploadedSize,
              totalBytes: totalBytes,
            ),
          );

        // The upload finished and the message was persisted server-side.
        case 'updateMessageSendSucceeded':
          final oldId = update['old_message_id'] as int?;
          if (oldId != temporaryMessageId) return;
          final message = update['message'] as Map<String, dynamic>?;
          final newId = message?['id'] as int? ?? temporaryMessageId;
          // Emit a final 100% so the UI settles on complete.
          _progressController.add(
            UploadProgress(
              taskId: taskId,
              progress: 1.0,
              bytesUploaded: totalBytes,
              totalBytes: totalBytes,
            ),
          );
          if (!completer.isCompleted) completer.complete(newId);

        // The send failed; surface it as a retryable transfer error.
        case 'updateMessageSendFailed':
          final oldId = update['old_message_id'] as int?;
          if (oldId != temporaryMessageId) return;
          final error = update['error'] as Map<String, dynamic>?;
          final code = error?['code']?.toString() ?? 'UNKNOWN';
          final messageText = error?['message'] as String? ?? 'Upload failed';
          if (!completer.isCompleted) {
            completer.completeError(
              TransferError.fromTdLibError(code, messageText),
            );
          }
      }
    });

    // Cancellation from cancelUpload() -> treat as a cancelled transfer.
    unawaited(
      cancelCompleter.future.then((_) {
        if (!completer.isCompleted) {
          completer.completeError(
            TransferError(
              category: TransferErrorCategory.unknown,
              message: 'Upload cancelled',
              occurredAt: DateTime.now(),
            ),
          );
        }
      }),
    );

    try {
      return await completer.future.timeout(
        _uploadTimeout,
        onTimeout: () => throw TransferError(
          category: TransferErrorCategory.network,
          message: 'Upload timed out after ${_uploadTimeout.inMinutes} min',
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
