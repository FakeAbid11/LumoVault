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
  /// Returns the channel ID if found with data, null if no backup exists.
  Future<ChannelDetectionResult> detectExistingBackup() async {
    try {
      final result = await _storageChannelService.findOrCreateChannel();

      return switch (result) {
        StorageChannelFound(:final channelId) => ChannelDetectionResult(
          channelId: channelId,
          isNewChannel: false,
        ),
        StorageChannelCreated(:final channelId) => ChannelDetectionResult(
          channelId: channelId,
          isNewChannel: true,
        ),
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
  Future<Manifest?> fetchManifest(int channelId) async {
    try {
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
    } catch (e) {
      debugPrint('[RestoreRepository] Failed to fetch manifest: $e');
      return null;
    }
  }

  /// Get all file messages from the storage channel.
  ///
  /// Returns messages with their IDs, captions, and file info.
  Future<List<ChannelMessage>> fetchChannelMessages(int channelId) async {
    final messages = <ChannelMessage>[];
    int? fromMessageId;

    try {
      while (true) {
        final params = <String, dynamic>{
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
        };

        final result = await _client.sendRequest(
          method: 'getChatHistory',
          params: params,
        );

        final messagesList = (result['messages'] as List<dynamic>?) ?? [];
        if (messagesList.isEmpty) break;

        for (final msg in messagesList) {
          final msgMap = msg as Map<String, dynamic>;
          final msgId = msgMap['id'] as int?;
          final content = msgMap['content'] as Map<String, dynamic>?;
          final contentType = content?['@type'] as String?;

          if (contentType == 'messageDocument') {
            final document = content?['document'] as Map<String, dynamic>?;
            final caption = content?['caption'] as Map<String, dynamic>?;
            final captionText = caption?['text'] as String?;
            final fileId = document?['id'] as int?;
            final fileName = document?['file_name'] as String? ?? 'unknown';

            messages.add(
              ChannelMessage(
                messageId: msgId ?? 0,
                fileId: fileId ?? 0,
                fileName: fileName,
                caption: captionText,
              ),
            );
          }

          fromMessageId = msgId;
        }

        if (messagesList.length < 100) break;
      }
    } catch (e) {
      debugPrint('[RestoreRepository] Error fetching messages: $e');
    }

    return messages;
  }

  /// Download a single file from the channel.
  ///
  /// Returns the local file path and parsed caption metadata.
  Future<DownloadedFile?> downloadFile({
    required int messageId,
    required int channelId,
    required String fileName,
    DownloadMode mode = DownloadMode.original,
    void Function(double progress)? onProgress,
  }) async {
    final taskId =
        'restore_${messageId}_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final subscription = _downloadService.progressStream.listen((progress) {
        if (progress.taskId == taskId) {
          onProgress?.call(progress.progress);
        }
      });

      final result = await _downloadService.downloadFile(
        taskId: taskId,
        messageId: messageId,
        channelId: channelId,
        mode: mode,
      );

      await subscription.cancel();

      return DownloadedFile(
        filePath: result.filePath,
        metadata: result.metadata,
        fileName: fileName,
      );
    } catch (e) {
      debugPrint('[RestoreRepository] Download failed for $fileName: $e');
      return null;
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
  });
  final int messageId;
  final int fileId;
  final String fileName;
  final String? caption;

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
