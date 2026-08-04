import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/storage/storage_channel_service.dart';
import '../../../../core/storage/thumbnail_cache.dart';
import '../../../../core/tdlib/tdlib_client.dart';
import '../../../gallery/data/models/caption_metadata.dart';
import '../../../gallery/data/models/media_item.dart';
import '../../../gallery/data/repositories/gallery_repository.dart';
import '../../../gallery/data/repositories/telegram_download_service.dart';
import 'restore_repository.dart';

/// Lightweight service that scans an existing Telegram backup channel
/// and populates the gallery with backed-up media items + thumbnails.
///
/// Unlike [RestoreEngine], this does NOT download original files — only
/// metadata and thumbnails for fast timeline display. Originals are
/// downloaded on-demand when the user opens an item.
class ChannelScanService {
  ChannelScanService({
    required TdLibClient client,
    required this._storageChannelService,
    required this._downloadService,
    required this._galleryRepository,
    @visibleForTesting TdRequestSender? requestSender,
  }) : _sendRequest = requestSender ?? client.sendRequest;

  final TdRequestSender _sendRequest;
  final StorageChannelService _storageChannelService;
  final DownloadService _downloadService;
  final GalleryRepository _galleryRepository;

  bool _hasScanned = false;
  bool get hasScanned => _hasScanned;

  /// The result of the last *successful* scan, replayed by repeat calls.
  ChannelScanResult? _lastResult;

  /// Mark the scan as done and remember its result so a second call can
  /// replay it. Only successful outcomes go through here — a failed scan
  /// must stay retryable.
  ChannelScanResult _complete(ChannelScanResult result) {
    _hasScanned = true;
    _lastResult = result;
    return result;
  }

  /// Scan the existing backup channel for backed-up media.
  ///
  /// Creates [MediaItem] objects from channel messages, downloads thumbnails,
  /// and merges them into [GalleryRepository].
  ///
  /// Returns a [ChannelScanResult] with scan statistics.
  Future<ChannelScanResult> scanChannel({
    void Function(int current, int total, String fileName)? onProgress,
  }) async {
    if (_hasScanned) {
      // Replay the previous outcome. Returning a zeroed hasBackup:false
      // result here was indistinguishable from "this account has no
      // backup", so a second call could convince the UI that a backup it
      // had already found didn't exist.
      final previous = _lastResult;
      if (previous != null) return previous.copyWith(alreadyScanned: true);
      return const ChannelScanResult(
        totalItems: 0,
        newItems: 0,
        skippedItems: 0,
        failedThumbnails: 0,
        hasBackup: false,
        alreadyScanned: true,
      );
    }

    try {
      // Ensure the thumbnail cache directory exists before downloading.
      await ThumbnailCache.instance.initialize();

      // Step 1: Find existing backup channel.
      final lookup = await _storageChannelService.findExistingChannel();

      final int channelId;
      switch (lookup) {
        case StorageChannelFound(channelId: final id):
          channelId = id;
        case StorageChannelCreated(channelId: final id):
          channelId = id;
        case StorageChannelNotFound():
          // A definitive answer: this account really has no backup channel.
          return _complete(
            const ChannelScanResult(
              totalItems: 0,
              newItems: 0,
              skippedItems: 0,
              failedThumbnails: 0,
              hasBackup: false,
            ),
          );
        case StorageChannelError(:final message):
          // We couldn't determine whether a backup exists. Report it as an
          // error and stay retryable — do NOT record this as "scanned".
          debugPrint('[ChannelScanService] Channel lookup failed: $message');
          return ChannelScanResult(
            totalItems: 0,
            newItems: 0,
            skippedItems: 0,
            failedThumbnails: 0,
            hasBackup: false,
            error: message,
          );
      }

      // Step 2: Fetch all channel messages.
      final messages = await _fetchMessages(channelId);
      if (messages.isEmpty) {
        return _complete(
          const ChannelScanResult(
            totalItems: 0,
            newItems: 0,
            skippedItems: 0,
            failedThumbnails: 0,
            hasBackup: true,
          ),
        );
      }

      // Step 3: Build MediaItems from messages, skipping duplicates.
      final existingHashes = _galleryRepository.mediaItems
          .map((item) => item.fileHash)
          .toSet();

      final newItems = <MediaItem>[];
      int skippedCount = 0;
      int failedThumbnailCount = 0;

      for (int i = 0; i < messages.length; i++) {
        final message = messages[i];

        // Report progress.
        onProgress?.call(i + 1, messages.length, message.fileName);

        // Parse caption metadata.
        final metadata = message.captionMetadata;

        // Build MediaItem — use parsed metadata if available, otherwise
        // generate a minimal item so manually-sent images still appear.
        MediaItem? mediaItem;
        if (metadata != null && metadata.fileHash.isNotEmpty) {
          mediaItem = _buildMediaItem(message: message, metadata: metadata);
        } else {
          debugPrint(
            '[ChannelScanService] Msg ${message.messageId} '
            '${message.fileName}: no caption metadata, '
            'building fallback item',
          );
          mediaItem = _buildFallbackMediaItem(message: message);
        }

        if (mediaItem == null) {
          debugPrint(
            '[ChannelScanService] Skipping msg ${message.messageId} '
            '${message.fileName}: could not build MediaItem',
          );
          skippedCount++;
          continue;
        }

        // Skip duplicates by file hash. The thumbnail is still fetched when
        // missing: the gallery can hold an item whose thumbnail never made
        // it into the cache (a download that failed during an earlier scan,
        // or an item added by a restore run). The bytes land under the same
        // [MediaItem.localId] the existing item uses, so the timeline tile
        // heals in place.
        if (existingHashes.contains(mediaItem.fileHash)) {
          if (!await ThumbnailCache.instance.contains(mediaItem.localId)) {
            try {
              await _downloadThumbnail(
                messageId: message.messageId,
                channelId: channelId,
                mediaItem: mediaItem,
              );
            } catch (e) {
              debugPrint(
                '[ChannelScanService] Thumbnail download failed for '
                '${message.fileName}: $e',
              );
              failedThumbnailCount++;
            }
          }
          debugPrint(
            '[ChannelScanService] Skipping msg ${message.messageId} '
            '${message.fileName}: duplicate hash',
          );
          skippedCount++;
          continue;
        }

        // Download thumbnail (non-blocking — item appears with placeholder
        // if thumbnail fails). Skipped when already cached, so a force
        // rescan refetches only what's missing instead of re-downloading
        // the whole channel.
        if (!await ThumbnailCache.instance.contains(mediaItem.localId)) {
          try {
            await _downloadThumbnail(
              messageId: message.messageId,
              channelId: channelId,
              mediaItem: mediaItem,
            );
          } catch (e) {
            debugPrint(
              '[ChannelScanService] Thumbnail download failed for '
              '${message.fileName}: $e',
            );
            failedThumbnailCount++;
          }
        }

        newItems.add(mediaItem);
        existingHashes.add(mediaItem.fileHash);
      }

      // Step 4: Merge into gallery repository.
      if (newItems.isNotEmpty) {
        await _galleryRepository.mergeTelegramItems(newItems);
      }

      debugPrint(
        '[ChannelScanService] Scan complete: '
        'total=${messages.length} new=${newItems.length} '
        'skipped=$skippedCount failedThumbnails=$failedThumbnailCount',
      );

      return _complete(
        ChannelScanResult(
          totalItems: messages.length,
          newItems: newItems.length,
          skippedItems: skippedCount,
          failedThumbnails: failedThumbnailCount,
          hasBackup: true,
        ),
      );
    } catch (e) {
      debugPrint('[ChannelScanService] Scan failed: $e');
      // Deliberately NOT setting _hasScanned: a scan that blew up hasn't
      // told us anything about the channel, and marking it done would wedge
      // the session into permanently reporting "no backup" until restart.
      return ChannelScanResult(
        totalItems: 0,
        newItems: 0,
        skippedItems: 0,
        failedThumbnails: 0,
        hasBackup: false,
        error: e.toString(),
      );
    }
  }

  /// Page size requested from `getChatHistory`.
  ///
  /// A request ceiling, NOT an end-of-history signal — see [_fetchMessages].
  static const int _pageLimit = 100;

  /// Fetch all file messages from the storage channel.
  Future<List<ChannelMessage>> _fetchMessages(int channelId) async {
    final messages = <ChannelMessage>[];
    int? fromMessageId;
    int? previousFromMessageId;

    while (true) {
      // Only the four parameters getChatHistory actually accepts. The previous
      // version also sent sender_server_date_min/max, offset_date,
      // offset_chat_id and only_local — those belong to searchChatMessages /
      // getChats. TDLib ignores unknown fields, so they were silent noise
      // rather than an error, but they implied a filtering behaviour that was
      // never happening.
      final params = <String, dynamic>{
        'chat_id': channelId,
        'limit': _pageLimit,
        'from_message_id': fromMessageId ?? 0,
        'offset': 0,
      };

      final result = await _sendRequest(
        method: 'getChatHistory',
        params: params,
      );

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
          // The file id lives on the nested `document` field of the wrapper
          // (TDLib has no top-level `id` on the document object).
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
        } else if (contentType == 'messagePhoto') {
          final photo = content?['photo'] as Map<String, dynamic>?;
          final sizes = photo?['sizes'] as List<dynamic>?;
          final lastSize = sizes != null && sizes.isNotEmpty
              ? sizes.last as Map<String, dynamic>
              : null;
          final photoFile = lastSize?['photo'] as Map<String, dynamic>?;
          final fileId = photoFile?['id'] as int?;
          final caption = content?['caption'] as Map<String, dynamic>?;
          final captionText = caption?['text'] as String?;

          messages.add(
            ChannelMessage(
              messageId: msgId ?? 0,
              fileId: fileId ?? 0,
              fileName: 'photo_${msgId ?? 0}.jpg',
              caption: captionText,
              sentAt: sentAt,
            ),
          );
        } else if (contentType == 'messageVideo') {
          final video = content?['video'] as Map<String, dynamic>?;
          final fileId =
              (video?['video'] as Map<String, dynamic>?)?['id'] as int?;
          final caption = content?['caption'] as Map<String, dynamic>?;
          final captionText = caption?['text'] as String?;
          final fileName =
              video?['file_name'] as String? ?? 'video_${msgId ?? 0}.mp4';

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
      // chunk), so a single short page silently ended the scan and the restore
      // under-reported the library with no error surfaced anywhere.
      //
      // The only reliable terminator is an empty page, handled above.
      if (fromMessageId == null || fromMessageId == previousFromMessageId) {
        // The cursor didn't advance, so the next request would return the same
        // page forever. Nothing sane produces this, but an unbounded network
        // loop is a worse failure than a truncated scan.
        debugPrint(
          '[ChannelScanService] Pagination cursor stalled at $fromMessageId '
          'after ${messages.length} message(s); stopping',
        );
        break;
      }
      previousFromMessageId = fromMessageId;
    }

    return messages;
  }

  /// Build a [MediaItem] from a [ChannelMessage] and its [CaptionMetadata].
  MediaItem? _buildMediaItem({
    required ChannelMessage message,
    required CaptionMetadata metadata,
  }) {
    if (metadata.fileHash.isEmpty) return null;

    final localId = metadata.mediaItemId.isEmpty
        ? 'msg_${message.messageId}'
        : metadata.mediaItemId;

    return MediaItem(
      localId: localId,
      fileHash: metadata.fileHash,
      telegramMessageId: message.messageId.toString(),
      telegramFileId: message.fileId.toString(),
      filePath: 'telegram://${message.messageId}',
      fileName: message.fileName,
      mimeType: metadata.mimeType ?? _guessMimeType(message.fileName),
      fileSize: metadata.fileSize,
      width: metadata.width,
      height: metadata.height,
      durationMs: metadata.durationMs,
      createdAt: metadata.createdAt,
      modifiedAt: metadata.modifiedAt,
      scannedAt: DateTime.now(),
      backedUpAt: metadata.backedUpAt,
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

  /// Build a fallback [MediaItem] for messages without valid caption metadata.
  ///
  /// Generates a deterministic fileHash from the message ID so manually-sent
  /// images still appear in the timeline instead of being silently dropped.
  MediaItem? _buildFallbackMediaItem({required ChannelMessage message}) {
    if (message.messageId == 0) return null;

    // Deterministic hash from message ID — ensures the same message always
    // produces the same hash (for dedup) while remaining unique across messages.
    final hashSource = 'msg_${message.messageId}_${message.fileId}';
    final fileHash = sha256.convert(utf8.encode(hashSource)).toString();

    final localId = 'msg_${message.messageId}';
    final mimeType = _guessMimeType(message.fileName);

    final now = DateTime.now();
    final messageDate = message.sentAt ?? now;

    return MediaItem(
      localId: localId,
      fileHash: fileHash,
      telegramMessageId: message.messageId.toString(),
      telegramFileId: message.fileId.toString(),
      filePath: 'telegram://${message.messageId}',
      fileName: message.fileName,
      mimeType: mimeType,
      fileSize: 0,
      width: 0,
      height: 0,
      createdAt: messageDate,
      modifiedAt: messageDate,
      scannedAt: now,
      backedUpAt: now,
      status: MediaStatus.uploaded,
    );
  }

  /// Download a thumbnail for a media item and store it in [ThumbnailCache].
  Future<void> _downloadThumbnail({
    required int messageId,
    required int channelId,
    required MediaItem mediaItem,
  }) async {
    final taskId =
        'scan_thumb_${messageId}_${DateTime.now().millisecondsSinceEpoch}';

    final result = await _downloadService.downloadFile(
      taskId: taskId,
      messageId: messageId,
      channelId: channelId,
      mode: DownloadMode.thumbnail,
    );

    final file = File(result.filePath);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      await ThumbnailCache.instance.put(mediaItem.localId, bytes);
      debugPrint(
        '[ChannelScanService] Thumbnail cached for '
        '${mediaItem.fileName} (${bytes.length} bytes)',
      );

      // Clean up the temporary download file — the bytes are now in cache.
      try {
        await file.delete();
      } catch (_) {
        // Non-critical: temp file cleanup failure.
      }
    } else {
      debugPrint(
        '[ChannelScanService] Thumbnail file not found after download: '
        '${result.filePath}',
      );
    }
  }

  String _guessMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      default:
        return 'application/octet-stream';
    }
  }

  /// Reset scan state so the next call to [scanChannel] actually runs.
  void resetScanState() {
    _hasScanned = false;
    _lastResult = null;
  }
}

/// Result of a channel scan operation.
class ChannelScanResult {
  const ChannelScanResult({
    required this.totalItems,
    required this.newItems,
    required this.skippedItems,
    required this.failedThumbnails,
    required this.hasBackup,
    this.error,
    this.alreadyScanned = false,
  });

  final int totalItems;
  final int newItems;
  final int skippedItems;
  final int failedThumbnails;
  final bool hasBackup;
  final String? error;

  /// True when this is a replay of an earlier scan rather than a fresh one.
  ///
  /// Lets callers tell "we already did this, here's what we found" apart
  /// from a genuine scan that turned up nothing.
  final bool alreadyScanned;

  bool get hasError => error != null;

  ChannelScanResult copyWith({bool? alreadyScanned}) {
    return ChannelScanResult(
      totalItems: totalItems,
      newItems: newItems,
      skippedItems: skippedItems,
      failedThumbnails: failedThumbnails,
      hasBackup: hasBackup,
      error: error,
      alreadyScanned: alreadyScanned ?? this.alreadyScanned,
    );
  }
}
