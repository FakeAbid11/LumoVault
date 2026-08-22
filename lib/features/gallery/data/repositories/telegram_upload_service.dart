import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../core/tdlib/tdlib_client.dart';
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
    bool includeCaption = true,
  });
  Future<void> cancelUpload(String taskId);

  /// Release the progress stream and abandon any in-flight uploads.
  ///
  /// Part of the interface rather than just the implementation so whoever owns
  /// the instance can tear it down without knowing the concrete type.
  void dispose();
}

/// Telegram-based upload service using TDLib.
///
/// Handles file uploads to the storage channel with progress tracking,
/// cancellation support, and error recovery per PRD Section 5.
class TelegramUploadService implements UploadService {
  TelegramUploadService({
    required TdLibConnectionManager manager,
    @visibleForTesting TdRequestSender? requestSender,
    @visibleForTesting Stream<Map<String, dynamic>>? updates,
  }) : _sendRequest = requestSender ?? manager.sendRequest,
       _updates = updates ?? manager.client.updates;

  // Requests go through the connection manager (not the raw TdLibClient) so
  // a dropped connection mid-upload triggers the same backoff/reconnect
  // logic the rest of the app already relies on, instead of just failing
  // the transfer outright.
  //
  // Both collaborators are injectable because neither the manager nor the
  // client can be constructed in a test — TdLibClient is a private-constructor
  // FFI singleton. These two are the entire surface this service uses.
  final TdRequestSender _sendRequest;
  final Stream<Map<String, dynamic>> _updates;
  final _progressController = StreamController<UploadProgress>.broadcast();
  final _activeUploads = <String, Completer<void>>{};

  @override
  Stream<UploadProgress> get progressStream => _progressController.stream;

  @override
  Future<UploadResult> uploadFile({
    required UploadTask task,
    required int channelId,
    bool includeCaption = true,
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

      // Build caption with metadata. The capture timestamps come from the
      // source asset via the task — only backedUpAt is "now". Falling back to
      // the task's own createdAt keeps the caption honest for tasks queued
      // before these fields existed, rather than stamping upload time as
      // capture time.
      //
      // includeCaption is false for metadata payloads (manifest and partition
      // files): those must arrive caption-less so the restore flow keeps
      // treating them as non-media messages and skips them when rebuilding
      // the library from captions.
      final now = DateTime.now();
      final caption = includeCaption
          ? CaptionMetadata(
              mediaItemId: task.mediaItemId,
              fileHash: task.fileHash,
              createdAt: task.mediaCreatedAt ?? task.createdAt,
              modifiedAt:
                  task.mediaModifiedAt ?? task.mediaCreatedAt ?? task.createdAt,
              backedUpAt: now,
              fileSize: task.fileSize,
              durationMs: task.durationMs,
            )
          : null;

      // Correlation ids for the async send-succeeded/send-failed and file
      // progress updates. They only become known once `sendMessage` returns,
      // so the listener below buffers updates until [idsKnown] flips true.
      final completer = Completer<int>();
      final pending = <Map<String, dynamic>>[];
      int temporaryMessageId = 0;
      int? sentFileId;
      var idsKnown = false;

      // Subscribe to updates BEFORE dispatching the send. `_updates` is a
      // broadcast stream with no buffering — if we subscribed only after the
      // send result returned, TDLib could emit `updateMessageSendSucceeded`
      // (common for tiny metadata payloads, which complete near-instantly) in
      // the gap and it would be silently lost, hanging the upload until the
      // 30-minute timeout. This is the same subscribe-before-request fix the
      // download service already carries.
      // ignore: cancel_subscriptions – cancelled in the finally block below.
      late final StreamSubscription<Map<String, dynamic>> subscription;
      subscription = _updates.listen((update) {
        if (completer.isCompleted) return;
        // Until the send result gives us the ids to correlate against, hold
        // updates so a fast terminal event isn't dropped.
        if (!idsKnown) {
          pending.add(update);
          return;
        }
        _handleUploadUpdate(
          update: update,
          taskId: task.id,
          temporaryMessageId: temporaryMessageId,
          fileId: sentFileId,
          totalBytes: task.fileSize,
          completer: completer,
        );
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
        // Send file to TDLib. The returned message is a *provisional* one with
        // a temporary id (`sending_state` is still pending); the real upload
        // happens asynchronously and is reported via the updates above.
        final result = await _sendRequest(
          method: 'sendMessage',
          params: {
            'chat_id': channelId,
            'input_message_content': {
              '@type': 'inputMessageDocument',
              'document': {
                '@type': 'inputFileLocal',
                'path': task.localFilePath,
              },
              // A generated poster for video uploads. Video documents get no
              // auto-thumbnail from Telegram, so without this the timeline
              // falls back to a placeholder.
              if (task.thumbnailPath != null)
                'thumbnail': {
                  '@type': 'inputThumbnail',
                  'thumbnail': {
                    '@type': 'inputFileLocal',
                    'path': task.thumbnailPath,
                  },
                },
              if (caption != null)
                'caption': {
                  '@type': 'formattedText',
                  'text': caption.toCaptionString(),
                },
              'disable_content_type_detection': false,
            },
          },
        );

        temporaryMessageId = result['id'] as int? ?? 0;
        final document =
            result['content']?['document'] as Map<String, dynamic>?;
        sentFileId = document?['document']?['id'] as int?;
        idsKnown = true;

        if (task.thumbnailPath != null) {
          debugPrint(
            '[UploadService] ${task.fileName}: sent with inputThumbnail; '
            'resulting content @type='
            '${(result['content'] as Map<String, dynamic>?)?['@type']}, '
            'document.thumbnail '
            '${document?['thumbnail'] == null ? 'ABSENT' : 'present'}',
          );
        }

        // Replay any updates that arrived before we knew the ids, now that we
        // can correlate them. A terminal event in the buffer resolves the
        // completer here rather than waiting on the timeout.
        for (final update in pending) {
          if (completer.isCompleted) break;
          _handleUploadUpdate(
            update: update,
            taskId: task.id,
            temporaryMessageId: temporaryMessageId,
            fileId: sentFileId,
            totalBytes: task.fileSize,
            completer: completer,
          );
        }
        pending.clear();

        // Wait for TDLib to actually finish (or fail) the upload.
        final finalMessageId = await completer.future.timeout(
          _uploadTimeout,
          onTimeout: () => throw TransferError(
            category: TransferErrorCategory.network,
            message: 'Upload timed out after ${_uploadTimeout.inMinutes} min',
            detail: 'TIMEOUT',
            retryable: true,
            occurredAt: DateTime.now(),
          ),
        );

        return UploadResult(
          taskId: task.id,
          messageId: finalMessageId,
          fileId: sentFileId ?? 0,
        );
      } finally {
        await subscription.cancel();
      }
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

  /// Handle a single TDLib update against an in-flight upload, emitting
  /// [UploadProgress] from `updateFile` events and resolving [completer] with
  /// the *permanent* message id (or a [TransferError]) on the terminal
  /// send-succeeded/send-failed events. Correlated to this upload via
  /// [temporaryMessageId] and [fileId].
  void _handleUploadUpdate({
    required Map<String, dynamic> update,
    required String taskId,
    required int temporaryMessageId,
    required int? fileId,
    required int totalBytes,
    required Completer<int> completer,
  }) {
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
        _emitProgress(
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
        _emitProgress(
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
  }

  /// Emit progress only while the stream is open.
  ///
  /// [dispose] can land between an upload starting and a TDLib update
  /// arriving; adding to a closed controller throws, and this runs inside an
  /// updates listener where the throw would go nowhere useful.
  void _emitProgress(UploadProgress progress) {
    if (_progressController.isClosed) return;
    _progressController.add(progress);
  }

  @override
  void dispose() {
    // Unblock anything waiting on _awaitUploadCompletion. Without this, an
    // upload in flight when the owning provider is torn down sits on its
    // completer until the 30-minute timeout, holding the updates subscription
    // and the queue slot with it.
    for (final completer in _activeUploads.values) {
      if (!completer.isCompleted) completer.complete();
    }
    _activeUploads.clear();
    _progressController.close();
  }
}
