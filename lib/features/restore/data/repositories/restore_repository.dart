import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../../core/storage/storage_channel_service.dart';
import '../../../../core/tdlib/tdlib_client.dart';
import '../../../gallery/data/models/caption_metadata.dart';
import '../../../gallery/data/models/media_item.dart';
import '../../../gallery/data/repositories/telegram_download_service.dart';
import '../../../metadata/data/models/manifest.dart';

/// Manages downloading manifest, partitions, thumbnails, and originals
/// from the Telegram storage channel during restore.
class RestoreRepository {
  RestoreRepository({
    required this._client,
    required this._storageChannelService,
    required this._downloadService,
    required this._storageBasePath,
  });

  final TdLibClient _client;
  final StorageChannelService _storageChannelService;
  final DownloadService _downloadService;
  final String _storageBasePath;

  /// Detect if an existing storage channel has backup data.
  ///
  /// Returns the channel ID if found, an empty result only when the lookup
  /// definitively found no channel, and an errored result when the lookup
  /// couldn't be completed — the caller must not treat that last case as
  /// "no backup exists".
  Future<ChannelDetectionResult> detectExistingBackup() async {
    try {
      final result = await _storageChannelService.findExistingChannel();

      return switch (result) {
        StorageChannelFound(:final channelId) => ChannelDetectionResult(
          channelId: channelId,
        ),
        StorageChannelCreated(:final channelId) => ChannelDetectionResult(
          channelId: channelId,
        ),
        StorageChannelNotFound() => const ChannelDetectionResult(),
        StorageChannelError(:final message) => ChannelDetectionResult(
          error: message,
        ),
      };
    } catch (e) {
      return ChannelDetectionResult(error: e.toString());
    }
  }

  /// Fetch the manifest from the pinned message in the storage channel.
  ///
  /// Per PRD Section 10.2 Step 3: get pinned message, parse manifest JSON.
  ///
  /// Returns null only when the channel legitimately has no pinned manifest.
  /// Transport/parse failures propagate to the caller — silently returning
  /// null here used to surface to the user as "backup corrupted" (a
  /// non-retryable error) on a transient network blip.
  Future<Manifest?> fetchManifest(int channelId) async {
    final result = await _client.sendRequest(
      method: 'getChatPinnedMessages',
      params: {'chat_id': channelId},
    );

    final messageIds = (result['message_ids'] as List<dynamic>?) ?? [];
    if (messageIds.isEmpty) return null;

    final messageId = messageIds.first as int;
    final message = await _client.sendRequest(
      method: 'getMessage',
      params: {'chat_id': channelId, 'message_id': messageId},
    );

    final content = message['content'] as Map<String, dynamic>?;
    final text = content?['text'] as Map<String, dynamic>?;
    final manifestText = text?['text'] as String?;

    if (manifestText == null || manifestText.isEmpty) return null;

    return Manifest.fromJsonString(manifestText);
  }

  /// Get all file messages from the storage channel.
  ///
  /// Returns messages with their IDs, captions, and file info.
  ///
  /// Each history page gets a bounded retry before the failure propagates:
  /// returning a silently truncated list here used to make the engine think
  /// the backup was complete (or "corrupted" if the first page failed) and
  /// permanently drop the unreached files from the restore.
  Future<List<ChannelMessage>> fetchChannelMessages(int channelId) async {
    final messages = <ChannelMessage>[];
    int? fromMessageId;
    int? previousFromMessageId;

    while (true) {
      final result = await _fetchHistoryPage(channelId, fromMessageId);

      final messagesList = (result['messages'] as List<dynamic>?) ?? [];
      if (messagesList.isEmpty) break;

      for (final msg in messagesList) {
        final msgMap = msg as Map<String, dynamic>;
        final msgId = msgMap['id'] as int?;
        final dateUnix = msgMap['date'] as int?;
        final sentAt = dateUnix != null && dateUnix > 0
            ? DateTime.fromMillisecondsSinceEpoch(dateUnix * 1000)
            : null;
        final content = msgMap['content'] as Map<String, dynamic>?;
        final contentType = content?['@type'] as String?;

        if (contentType == 'messageDocument') {
          final document = content?['document'] as Map<String, dynamic>?;
          final caption = content?['caption'] as Map<String, dynamic>?;
          final captionText = caption?['text'] as String?;
          final fileId =
              (document?['document'] as Map<String, dynamic>?)?['id'] as int?;
          final fileName = document?['file_name'] as String? ?? 'unknown';

          messages.add(
            ChannelMessage(
              messageId: msgId ?? 0,
              fileId: fileId ?? 0,
              fileName: fileName,
              caption: captionText,
              sentAt: sentAt,
            ),
          );
        }

        fromMessageId = msgId;
      }

      // Page until TDLib returns an EMPTY result.
      //
      // This used to be `if (messagesList.length < 100) break;`. getChatHistory
      // is explicitly allowed to return fewer messages than `limit` even when
      // more history remains (it returns whatever is in one locally-available
      // chunk), so a single short page silently ended the restore and dropped
      // the unreached files with no error surfaced anywhere.
      //
      // The only reliable terminator is an empty page, handled above.
      if (fromMessageId == null || fromMessageId == previousFromMessageId) {
        // The cursor didn't advance, so the next request would return the same
        // page forever. Nothing sane produces this, but an unbounded network
        // loop is a worse failure than a truncated restore.
        debugPrint(
          '[RestoreRepository] Pagination cursor stalled at $fromMessageId '
          'after ${messages.length} message(s); stopping',
        );
        break;
      }
      previousFromMessageId = fromMessageId;
    }

    return messages;
  }

  /// Fetch a single page of chat history with a bounded retry.
  ///
  /// Only transient request errors are retried (each page is idempotent via
  /// [fromMessageId], so a retry can never duplicate entries).
  Future<Map<String, dynamic>> _fetchHistoryPage(
    int channelId,
    int? fromMessageId,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxPageAttempts; attempt++) {
      try {
        return await _client.sendRequest(
          method: 'getChatHistory',
          params: {
            'chat_id': channelId,
            'limit': 100,
            'from_message_id': fromMessageId ?? 0,
            'offset': 0,
            'sender_server_date_min': 0,
            'sender_server_date_max': 0,
            'offset_date': 0,
            'offset_chat_id': 0,
            'offset_message_id': 0,
            'only_local': false,
          },
        );
      } catch (e) {
        lastError = e;
        debugPrint(
          '[RestoreRepository] History page failed '
          '(attempt $attempt/$_maxPageAttempts): $e',
        );
      }
    }
    throw lastError!;
  }

  static const int _maxPageAttempts = 2;

  /// Download a single file from the channel.
  ///
  /// Returns the local file path and parsed caption metadata.
  ///
  /// Failures propagate to the caller. Returning null here used to make the
  /// engine count a failed file as successfully skipped, so a storage-full
  /// or auth-expired condition was silently swallowed and the restore still
  /// reported "complete".
  Future<DownloadedFile> downloadFile({
    required int messageId,
    required int channelId,
    required String fileName,
    DownloadMode mode = DownloadMode.original,
    void Function(double progress)? onProgress,
  }) async {
    final taskId =
        'restore_${messageId}_${DateTime.now().millisecondsSinceEpoch}';

    final subscription = _downloadService.progressStream.listen((progress) {
      if (progress.taskId == taskId) {
        onProgress?.call(progress.progress);
      }
    });

    try {
      final result = await _downloadService.downloadFile(
        taskId: taskId,
        messageId: messageId,
        channelId: channelId,
        mode: mode,
      );

      return DownloadedFile(
        filePath: result.filePath,
        metadata: result.metadata,
        fileName: fileName,
      );
    } finally {
      await subscription.cancel();
    }
  }

  /// Save a downloaded file to the restore directory.
  ///
  /// Returns the saved file path.
  Future<String> saveRestoredFile({
    required String sourcePath,
    required String fileName,
    required String subDir,
  }) async {
    final dir = Directory(p.join(_storageBasePath, 'restored', subDir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final destPath = p.join(dir.path, fileName);
    final sourceFile = File(sourcePath);

    if (await sourceFile.exists()) {
      await sourceFile.copy(destPath);
      return destPath;
    }

    return sourcePath;
  }

  /// Generate a MediaItem from a ChannelMessage's metadata.
  MediaItem? buildMediaItemFromMessage({
    required ChannelMessage message,
    required String localFilePath,
    required String fileName,
  }) {
    final metadata = message.captionMetadata;
    if (metadata == null) return null;

    return MediaItem(
      localId: metadata.mediaItemId.isEmpty
          ? 'msg_${message.messageId}'
          : metadata.mediaItemId,
      fileHash: metadata.fileHash,
      telegramMessageId: message.messageId.toString(),
      telegramFileId: message.fileId.toString(),
      filePath: localFilePath,
      fileName: fileName,
      mimeType: metadata.mimeType ?? _guessMimeType(fileName),
      fileSize: metadata.fileSize,
      width: metadata.width,
      height: metadata.height,
      durationMs: metadata.durationMs,
      createdAt: metadata.createdAt,
      modifiedAt: metadata.modifiedAt,
      scannedAt: DateTime.now(),
      backedUpAt: DateTime.now(),
      status: MediaStatus.uploaded,
      isFavorite: metadata.isFavorite,
      isHidden: metadata.isHidden,
      isArchived: metadata.isArchived,
      albumName: metadata.albumName,
      deviceFolder: metadata.deviceFolder,
      description: metadata.description,
      tags: metadata.tags,
    );
  }

  String _guessMimeType(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.avi':
        return 'video/x-msvideo';
      default:
        return 'application/octet-stream';
    }
  }

  /// Cancel an in-progress download.
  Future<void> cancelDownload(String taskId) async {
    await _downloadService.cancelDownload(taskId);
  }

  void dispose() {}
}

/// Result of channel detection.
class ChannelDetectionResult {
  const ChannelDetectionResult({
    this.channelId,
    this.isNewChannel = false,
    this.error,
  });
  final int? channelId;
  final bool isNewChannel;
  final String? error;

  bool get hasBackup => channelId != null && !isNewChannel;
  bool get hasError => error != null;
  bool get isNew => isNewChannel;
}

/// A message from the Telegram storage channel.
class ChannelMessage {
  const ChannelMessage({
    required this.messageId,
    required this.fileId,
    required this.fileName,
    this.caption,
    this.sentAt,
  });
  final int messageId;
  final int fileId;
  final String fileName;
  final String? caption;

  /// When the message was sent (Unix timestamp from TDLib).
  /// Falls back to [DateTime.now] if absent.
  final DateTime? sentAt;

  CaptionMetadata? get captionMetadata {
    if (caption == null || caption!.isEmpty) return null;
    return CaptionMetadata.fromCaptionString(caption!);
  }
}

/// A downloaded file with its metadata.
class DownloadedFile {
  const DownloadedFile({
    required this.filePath,
    this.metadata,
    required this.fileName,
  });
  final String filePath;
  final CaptionMetadata? metadata;
  final String fileName;
}
