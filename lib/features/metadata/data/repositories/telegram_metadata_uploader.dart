import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/storage/storage_channel_service.dart';
import '../../../gallery/data/models/upload_task.dart';
import '../../../gallery/data/repositories/telegram_upload_service.dart';

/// Uploads the metadata layer's JSON payloads (partition files and the
/// manifest) to the private storage channel as caption-less documents.
///
/// The upload goes through the same [UploadService] the media files use, so
/// progress, cancellation, reconnect handling, and error classification are
/// identical. Captions are suppressed (see [TelegramUploadService.uploadFile])
/// so the restore flow keeps ignoring these messages when it rebuilds the
/// library from media captions.
class TelegramMetadataUploader {
  TelegramMetadataUploader({
    required this.uploadService,
    this.storageChannelService,
    this.channelIdProvider,
    this.tempDirProvider,
    this.deviceHashProvider,
  });

  final UploadService uploadService;

  /// Used to find-or-create the storage channel. Optional when
  /// [channelIdProvider] is supplied instead (tests).
  final StorageChannelService? storageChannelService;

  /// Resolves the channel to upload into. Defaults to
  /// [StorageChannelService.findOrCreateChannel].
  final Future<int> Function()? channelIdProvider;

  /// Where temporary JSON payload files are written before upload.
  /// Defaults to the platform temporary directory.
  final Future<Directory> Function()? tempDirProvider;

  /// Override for the device hash stamped into generated manifests.
  final Future<String> Function()? deviceHashProvider;

  /// The stable per-device hash used in the metadata manifest.
  ///
  /// Delegates to [StorageChannelService.generateDeviceHash] so the manifest
  /// files agree with the pinned manifest message on the channel about which
  /// device produced the backup.
  Future<String> deviceHash() async {
    final override = deviceHashProvider;
    if (override != null) return override();
    final service = storageChannelService;
    if (service == null) {
      throw StateError('No device hash strategy configured');
    }
    return service.generateDeviceHash();
  }

  /// File-name prefix on the channel for metadata payloads. Keeps metadata
  /// documents distinguishable from media documents in the channel history.
  static const String filePrefix = 'metadata/';

  /// Prefix of the temp-file basename the payload is written to before upload.
  ///
  /// TDLib names the uploaded document after the local file's basename (no
  /// explicit file_name is supplied), so the on-channel `document.file_name`
  /// is exactly [channelFileName] below. The downloader matches on that string
  /// to locate metadata documents, so the two must agree — hence these shared
  /// static helpers rather than duplicated string surgery on each side.
  static const String _tempPrefix = 'lumovault_metadata_';

  /// Public alias of [_tempPrefix]. Every metadata document uploaded to the
  /// channel has a `file_name` starting with this, so the channel scan can
  /// recognise and skip them instead of surfacing them as timeline items.
  static const String channelFileNamePrefix = _tempPrefix;

  /// The on-channel `document.file_name` for a logical metadata path such as
  /// `metadata/manifest.json`. Mirrors the temp-path construction in
  /// [_uploadJson]; [TelegramMetadataDownloader] matches on this exact value.
  static String channelFileName(String logicalName) =>
      '$_tempPrefix${logicalName.replaceAll('/', '_')}';

  /// On-channel file name of the manifest document.
  static String get manifestChannelFileName =>
      channelFileName('${filePrefix}manifest.json');

  /// On-channel file name of a partition document, given its partition id.
  static String partitionChannelFileName(String partitionId) {
    final safeId = partitionId.replaceAll('/', '-');
    return channelFileName('$filePrefix$safeId.json');
  }

  /// Message ids of documents this device uploaded very recently, newest last.
  ///
  /// The live channel listener consults [wasRecentlySent] to ignore the echo
  /// of our own uploads instead of triggering a redundant pull. Bounded so it
  /// never grows without limit; reconcile is idempotent, so an evicted id that
  /// slips through is at worst a cheap no-op pull.
  final Queue<int> _recentlySentIds = Queue<int>();
  static const int _recentIdsCap = 64;

  /// Whether [messageId] is one this device uploaded within the last
  /// [_recentIdsCap] metadata uploads (see [_recentlySentIds]).
  bool wasRecentlySent(int messageId) => _recentlySentIds.contains(messageId);

  void _rememberSentId(int? messageId) {
    if (messageId == null) return;
    _recentlySentIds.addLast(messageId);
    while (_recentlySentIds.length > _recentIdsCap) {
      _recentlySentIds.removeFirst();
    }
  }

  Future<int> _resolveChannelId() async {
    final override = channelIdProvider;
    if (override != null) return override();
    final service = storageChannelService;
    if (service == null) {
      throw StateError('No channel resolution strategy configured');
    }
    final result = await service.findOrCreateChannel();
    switch (result) {
      case StorageChannelFound(:final channelId):
      case StorageChannelCreated(:final channelId):
        return channelId;
      case StorageChannelError(:final message, :final code):
        throw StateError('Channel unavailable: $message ($code)');
      case StorageChannelNotFound():
        throw StateError('Channel lookup found nothing');
    }
  }

  /// Upload one partition JSON payload.
  Future<void> uploadPartition(String partitionId, String data) {
    final safeId = partitionId.replaceAll('/', '-');
    return _uploadJson(fileName: '$filePrefix$safeId.json', data: data);
  }

  /// Upload the manifest JSON payload.
  Future<void> uploadManifest(String manifestJson) {
    return _uploadJson(
      fileName: '${filePrefix}manifest.json',
      data: manifestJson,
    );
  }

  Future<void> _uploadJson({
    required String fileName,
    required String data,
  }) async {
    final tempProvider = tempDirProvider;
    final dir = tempProvider != null
        ? await tempProvider()
        : await getTemporaryDirectory();

    // Flat temp path (no subdirectories) so cleanup after upload is a single
    // file delete; the TDLib document name keeps the 'metadata/...' prefix.
    final file = File(
      '${dir.path}/lumovault_metadata_${fileName.replaceAll('/', '_')}',
    );
    await file.writeAsString(data, flush: true);

    final channelId = await _resolveChannelId();

    final bytes = utf8.encode(data);
    final task = UploadTask(
      id: 'metadata_$fileName',
      mediaItemId: 'metadata:$fileName',
      localFilePath: file.path,
      fileName: fileName,
      fileSize: bytes.length,
      fileHash: sha256.convert(bytes).toString(),
      createdAt: DateTime.now(),
    );

    try {
      final result = await uploadService.uploadFile(
        task: task,
        channelId: channelId,
        // Metadata payloads must not carry a media caption: the restore flow
        // rebuilds the library from captions, so caption-less messages are the
        // only kind it can safely ignore.
        includeCaption: false,
      );
      // Remember the message id so the live channel listener can ignore the
      // echo of our own upload (see [wasRecentlySent]).
      _rememberSentId(result.messageId);
    } finally {
      try {
        await file.delete();
      } catch (e) {
        debugPrint('[TelegramMetadataUploader] Temp cleanup failed: $e');
      }
    }
  }
}
