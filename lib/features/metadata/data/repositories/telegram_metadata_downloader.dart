import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../core/storage/storage_channel_service.dart';
import '../../../../core/tdlib/tdlib_client.dart';
import '../../../gallery/data/repositories/telegram_download_service.dart';
import '../models/manifest.dart';
import '../models/metadata_partition.dart';
import 'telegram_metadata_uploader.dart';

/// Downloads and parses the metadata layer's JSON payloads (the manifest and
/// partition documents) that [TelegramMetadataUploader] wrote to the storage
/// channel — the pull half of two-way sync.
///
/// Metadata documents are caption-less, so they cannot be found by the
/// caption-driven scan/restore paths. Instead this pages `getChatHistory`
/// (the same idiom as [ChannelScanService]) and matches each message's
/// `document.file_name` against the deterministic names the uploader produces
/// ([TelegramMetadataUploader.channelFileName]). The newest message wins for a
/// given file name, so a re-uploaded partition supersedes its predecessor.
class TelegramMetadataDownloader {
  TelegramMetadataDownloader({
    required TdLibClient client,
    required this.downloadService,
    this.storageChannelService,
    this.channelIdProvider,
    @visibleForTesting TdRequestSender? requestSender,
  }) : _sendRequest = requestSender ?? client.sendRequest;

  final TdRequestSender _sendRequest;

  /// Retrieves the actual document bytes once located by message id.
  final DownloadService downloadService;

  /// Used to find the storage channel. Optional when [channelIdProvider] is
  /// supplied instead (tests).
  final StorageChannelService? storageChannelService;

  /// Resolves the channel to pull from. Defaults to
  /// [StorageChannelService.findExistingChannel]. Returns null when no backup
  /// channel exists yet — nothing to reconcile.
  final Future<int?> Function()? channelIdProvider;

  /// Cached channel id + file-name→messageId index for the life of one
  /// reconcile pass (manifest + N partitions). Reset by [invalidate] so a
  /// later pull re-scans and sees newly-uploaded documents.
  int? _channelId;
  Map<String, int>? _index;

  /// Drop the cached channel history index so the next call re-pages
  /// `getChatHistory`. Call between reconcile passes (e.g. per [pullNow]).
  void invalidate() {
    _channelId = null;
    _index = null;
  }

  /// Download + parse the remote manifest, or null if there is no backup
  /// channel or no manifest document on it.
  Future<Manifest?> downloadManifest() async {
    final channelId = await _resolveChannelId();
    if (channelId == null) return null;
    final index = await _ensureIndex(channelId);
    final messageId = index[TelegramMetadataUploader.manifestChannelFileName];
    if (messageId == null) return null;
    final json = await _downloadJsonString(channelId, messageId);
    if (json == null) return null;
    return Manifest.fromJsonString(json);
  }

  /// Download + parse a single partition document by its partition id (e.g.
  /// `2026/07`), or null if that partition has no document on the channel.
  Future<MetadataPartition?> downloadPartition(String partitionId) async {
    final channelId = await _resolveChannelId();
    if (channelId == null) return null;
    final index = await _ensureIndex(channelId);
    final fileName = TelegramMetadataUploader.partitionChannelFileName(
      partitionId,
    );
    final messageId = index[fileName];
    if (messageId == null) return null;
    final json = await _downloadJsonString(channelId, messageId);
    if (json == null) return null;
    return MetadataPartition.fromJsonString(json);
  }

  Future<int?> _resolveChannelId() async {
    final override = channelIdProvider;
    if (override != null) return override();
    final service = storageChannelService;
    if (service == null) return null;
    final result = await service.findExistingChannel();
    switch (result) {
      case StorageChannelFound(:final channelId):
      case StorageChannelCreated(:final channelId):
        return channelId;
      case StorageChannelNotFound():
      case StorageChannelError():
        return null;
    }
  }

  Future<Map<String, int>> _ensureIndex(int channelId) async {
    final cached = _index;
    if (cached != null && _channelId == channelId) return cached;
    final index = await _buildIndex(channelId);
    _channelId = channelId;
    _index = index;
    return index;
  }

  /// Page size requested from `getChatHistory`. A request ceiling, not an
  /// end-of-history signal (mirrors [ChannelScanService]).
  static const int _pageLimit = 100;

  /// Page channel history and index metadata documents by `file_name`,
  /// keeping the newest message id per name. getChatHistory returns newest
  /// first, so the first id seen for a name is the newest — later (older)
  /// duplicates are ignored.
  Future<Map<String, int>> _buildIndex(int channelId) async {
    final index = <String, int>{};
    int? fromMessageId;
    int? previousFromMessageId;

    while (true) {
      final result = await _sendRequest(
        method: 'getChatHistory',
        params: <String, dynamic>{
          'chat_id': channelId,
          'limit': _pageLimit,
          'from_message_id': fromMessageId ?? 0,
          'offset': 0,
        },
      );

      final messagesList = (result['messages'] as List<dynamic>?) ?? [];
      if (messagesList.isEmpty) break;

      for (final msg in messagesList) {
        final msgMap = msg as Map<String, dynamic>;
        final msgId = msgMap['id'] as int?;
        final content = msgMap['content'] as Map<String, dynamic>?;
        if (content?['@type'] == 'messageDocument') {
          final document = content?['document'] as Map<String, dynamic>?;
          final fileName = document?['file_name'] as String?;
          if (fileName != null &&
              fileName.startsWith('lumovault_metadata_') &&
              msgId != null) {
            // Newest-first: only record the first (newest) id per name.
            index.putIfAbsent(fileName, () => msgId);
          }
        }
        fromMessageId = msgId;
      }

      // Terminate only on an empty page (getChatHistory may return fewer than
      // `limit` even with history remaining) or a stalled cursor.
      if (fromMessageId == null || fromMessageId == previousFromMessageId) {
        break;
      }
      previousFromMessageId = fromMessageId;
    }

    return index;
  }

  Future<String?> _downloadJsonString(int channelId, int messageId) async {
    try {
      final result = await downloadService.downloadFile(
        taskId: 'metadata_pull_$messageId',
        messageId: messageId,
        channelId: channelId,
      );
      final file = File(result.filePath);
      if (!await file.exists()) return null;
      final data = await file.readAsString();
      // Drop TDLib's cached copy once read — the parsed value is what we keep,
      // and metadata documents change every sync, so caching them is waste.
      try {
        await file.delete();
      } catch (_) {
        // Non-critical: cache cleanup failure.
      }
      return data;
    } catch (e) {
      debugPrint(
        '[TelegramMetadataDownloader] Download failed for '
        'message $messageId: $e',
      );
      return null;
    }
  }
}
