import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../core/tdlib/tdlib_client.dart';
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
  TelegramDownloadService({
    required TdLibConnectionManager manager,
    @visibleForTesting TdRequestSender? requestSender,
    @visibleForTesting Stream<Map<String, dynamic>>? updates,
  }) : _sendRequest = requestSender ?? manager.sendRequest,
       _updates = updates ?? manager.client.updates;

  // Requests go through the connection manager (not the raw TdLibClient) so
  // a dropped connection mid-download triggers the same backoff/reconnect
  // logic the rest of the app already relies on, instead of just failing
  // the transfer outright.
  //
  // Both collaborators are injectable because neither the manager nor the
  // client can be constructed in a test — TdLibClient is a private-constructor
  // FFI singleton. These two are the entire surface this service uses.
  final TdRequestSender _sendRequest;
  final Stream<Map<String, dynamic>> _updates;
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
      final message = await _sendRequest(
        method: 'getMessage',
        params: {'chat_id': channelId, 'message_id': messageId},
      );

      final content = message['content'] as Map<String, dynamic>?;
      final contentType = content?['@type'] as String?;

      // Extract file info based on content type. TDLib nests the real `file`
      // object (which carries `id`, `local`, `remote`, ...) INSIDE the content
      // wrapper: `document.document`, `video.video`, `photoSize.photo` — there
      // is no top-level `id` on the document/video objects themselves.
      int? fileId;
      String? localPath;

      Map<String, dynamic>? file;
      if (contentType == 'messageDocument') {
        final document = content?['document'] as Map<String, dynamic>?;
        if (mode == DownloadMode.thumbnail) {
          // Prefer the document thumbnail (a small JPEG) when available;
          // fall back to the full document file.
          final thumbFile =
              (document?['thumbnail'] as Map<String, dynamic>?)?['file']
                  as Map<String, dynamic>?;
          file = thumbFile ?? (document?['document'] as Map<String, dynamic>?);
        } else {
          file = document?['document'] as Map<String, dynamic>?;
        }
      } else if (contentType == 'messagePhoto') {
        final photo = content?['photo'] as Map<String, dynamic>?;
        final sizes = photo?['sizes'] as List<dynamic>?;
        if (sizes != null && sizes.isNotEmpty) {
          // TDLib lists photo sizes ascending: thumbnails want the smallest
          // variant, originals the largest.
          final size =
              (mode == DownloadMode.thumbnail ? sizes.first : sizes.last)
                  as Map<String, dynamic>;
          file = size['photo'] as Map<String, dynamic>?;
        }
      } else if (contentType == 'messageVideo') {
        final video = content?['video'] as Map<String, dynamic>?;
        if (mode == DownloadMode.thumbnail) {
          final thumbFile =
              (video?['thumbnail'] as Map<String, dynamic>?)?['file']
                  as Map<String, dynamic>?;
          file = thumbFile ?? (video?['video'] as Map<String, dynamic>?);
        } else {
          file = video?['video'] as Map<String, dynamic>?;
        }
      }

      final local = file?['local'] as Map<String, dynamic>?;
      fileId = file?['id'] as int?;
      localPath = local?['path'] as String?;

      // Check if already downloaded.
      if (localPath != null && localPath.isNotEmpty) {
        final file = File(localPath);
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
            filePath: localPath,
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

      // Subscribe to file updates BEFORE requesting the download.
      // client.updates is a broadcast stream with no buffering — if we
      // subscribe after the request, TDLib can emit the completion event
      // before the listener is active and it is silently lost, causing a
      // 30-minute timeout for every download.
      // ignore: cancel_subscriptions – cancelled in _awaitDownloadCompletion's finally block.
      late final StreamSubscription<Map<String, dynamic>> subscription;
      final completionCompleter = Completer<String>();

      subscription = _updates.listen((update) {
        if (completionCompleter.isCompleted) return;
        final updateType = update['@type'] as String?;
        if (updateType != 'updateFile') return;

        final file = update['file'] as Map<String, dynamic>?;
        if (file == null || file['id'] != fileId) return;

        final local = file['local'] as Map<String, dynamic>?;
        final downloadedSize = local?['downloaded_size'] as int? ?? 0;
        final expectedSize = file['expected_size'] as int? ?? 0;
        final isCompleted =
            local?['is_downloading_completed'] as bool? ?? false;

        final progress = expectedSize > 0 ? downloadedSize / expectedSize : 0.0;
        _progressController.add(
          DownloadProgress(
            taskId: taskId,
            progress: progress.clamp(0.0, 1.0),
            bytesDownloaded: downloadedSize,
            totalBytes: expectedSize,
          ),
        );

        if (isCompleted && !completionCompleter.isCompleted) {
          final path = local?['path'] as String? ?? '';
          completionCompleter.complete(path);
        }
      });

      // Request the download — subscription is already listening.
      await _sendRequest(
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
        cancelCompleter: cancelCompleter,
        subscription: subscription,
        completionCompleter: completionCompleter,
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
  /// The [subscription] and [completionCompleter] are created by the caller
  /// BEFORE the TDLib `downloadFile` request is sent, so the broadcast
  /// stream subscription is active in time to catch fast-completing
  /// downloads (the race condition that caused every download to hang for
  /// 30 minutes).
  Future<String> _awaitDownloadCompletion({
    required String taskId,
    required Completer<void> cancelCompleter,
    required StreamSubscription<Map<String, dynamic>> subscription,
    required Completer<String> completionCompleter,
  }) async {
    // Cancellation from cancelDownload() -> treat as a cancelled transfer.
    unawaited(
      cancelCompleter.future.then((_) {
        if (!completionCompleter.isCompleted) {
          completionCompleter.completeError(
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
      return await completionCompleter.future.timeout(
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
