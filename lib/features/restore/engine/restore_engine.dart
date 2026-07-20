import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../gallery/data/models/media_item.dart';
import '../../gallery/data/repositories/gallery_repository.dart';
import '../../gallery/data/repositories/telegram_download_service.dart';
import '../../metadata/data/models/manifest.dart';
import '../../metadata/data/models/metadata_partition.dart';
import '../../metadata/data/repositories/manifest_service.dart';
import '../../metadata/data/repositories/metadata_repository.dart';
import '../../metadata/data/repositories/partition_service.dart';
import '../../metadata/data/repositories/search_index_service.dart';
import '../data/models/restore_progress.dart';
import '../data/repositories/restore_repository.dart';

/// Core restore engine orchestrating the full restore flow per PRD Section 10.
///
/// Phases:
/// 1. Detect existing backup channel
/// 2. Download manifest
/// 3. Download partition metadata
/// 4. Rebuild local database
/// 5. Download thumbnails (fast, progressive)
/// 6. Download originals (background, on-demand)
class RestoreEngine {
  RestoreEngine({
    required this.restoreRepository,
    required this.galleryRepository,
    required this.metadataRepository,
    required this.manifestService,
    required this.partitionService,
    required this.searchIndexService,
  });

  final RestoreRepository restoreRepository;
  final GalleryRepository galleryRepository;
  final MetadataRepository metadataRepository;
  final ManifestService manifestService;
  final PartitionService partitionService;
  final SearchIndexService searchIndexService;

  final _progressController = StreamController<RestoreProgress>.broadcast();
  RestoreProgress _progress = const RestoreProgress();
  bool _isCancelled = false;
  bool _isPaused = false;

  Stream<RestoreProgress> get progressStream => _progressController.stream;
  RestoreProgress get currentProgress => _progress;

  /// Start the full restore process.
  ///
  /// Per PRD Section 10.1, this orchestrates:
  /// 1. Channel discovery
  /// 2. Manifest fetch
  /// 3. File download (batch)
  /// 4. Database population
  /// 5. Search index rebuild
  Future<bool> startRestore() async {
    _isCancelled = false;
    _isPaused = false;
    _progress = const RestoreProgress();
    _updateProgress(phase: RestorePhase.detecting);

    try {
      // Phase 1: Detect existing backup
      final detection = await restoreRepository.detectExistingBackup();

      if (detection.hasError) {
        _fail(
          RestoreError(
            category: RestoreErrorCategory.channelNotFound,
            message: detection.error ?? 'Failed to check for backup',
            retryable: true,
            occurredAt: DateTime.now(),
          ),
        );
        return false;
      }

      if (detection.isNew) {
        _fail(RestoreError.channelNotFound());
        return false;
      }

      final channelId = detection.channelId!;

      // Phase 2: Download manifest
      _updateProgress(phase: RestorePhase.manifestDownload);
      final manifest = await restoreRepository.fetchManifest(channelId);

      if (manifest == null) {
        _fail(RestoreError.manifestCorrupted());
        return false;
      }

      if (!manifest.isCompatibleWith(Manifest.currentSchemaVersion)) {
        _fail(
          RestoreError(
            category: RestoreErrorCategory.manifestCorrupted,
            message: 'Incompatible backup version',
            detail:
                'This backup was created with a newer version of LumoVault. '
                'Please update your app to restore.',
            retryable: false,
            occurredAt: DateTime.now(),
          ),
        );
        return false;
      }

      final manifestInfo = ManifestInfo(
        totalMedia: manifest.totalMedia,
        totalSizeBytes: manifest.totalSizeBytes,
        created: manifest.created,
        lastSync: manifest.lastSync,
        chunkCount: manifest.chunks.length,
        deviceHash: manifest.deviceHash,
      );

      _updateProgress(
        phase: RestorePhase.metadataDownload,
        manifestInfo: manifestInfo,
        totalItems: manifest.totalMedia,
        totalBytes: manifest.totalSizeBytes,
      );

      // Phase 3: Download partition metadata
      final messages = await restoreRepository.fetchChannelMessages(channelId);

      if (messages.isEmpty) {
        _fail(RestoreError.manifestCorrupted());
        return false;
      }

      // Build metadata items from channel messages
      final allMetadata = <PartitionItem>[];
      final metadataByPartition = <String, List<PartitionItem>>{};

      for (final message in messages) {
        if (_isCancelled) {
          _fail(RestoreError.cancelled());
          return false;
        }
        while (_isPaused) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (_isCancelled) {
            _fail(RestoreError.cancelled());
            return false;
          }
        }

        final metadata = message.captionMetadata;
        if (metadata == null) continue;

        final partitionItem = PartitionItem(
          localId: metadata.mediaItemId.isEmpty
              ? 'msg_${message.messageId}'
              : metadata.mediaItemId,
          fileHash: metadata.fileHash,
          telegramMessageId: message.messageId.toString(),
          telegramFileId: message.fileId.toString(),
          createdAt: metadata.createdAt,
          modifiedAt: metadata.modifiedAt,
          backedUpAt: DateTime.now(),
          mimeType: metadata.mimeType,
          fileSize: metadata.fileSize,
          width: metadata.width,
          height: metadata.height,
          durationMs: metadata.durationMs,
          isFavorite: metadata.isFavorite,
          isHidden: metadata.isHidden,
          isArchived: metadata.isArchived,
          albumName: metadata.albumName,
          deviceFolder: metadata.deviceFolder,
          description: metadata.description,
          tags: metadata.tags,
          status: MediaStatus.uploaded,
          fileName: message.fileName,
        );

        allMetadata.add(partitionItem);

        final partitionKey = MetadataPartition.partitionKeyFromDate(
          partitionItem.createdAt,
        );
        metadataByPartition
            .putIfAbsent(partitionKey, () => [])
            .add(partitionItem);

        _updateProgress(
          completedItems: allMetadata.length,
          currentFileName: message.fileName,
        );
      }

      // Phase 4: Rebuild local database
      _updateProgress(
        phase: RestorePhase.databaseRebuild,
        currentPhaseDescription: 'Rebuilding your library...',
      );

      await _rebuildDatabase(allMetadata, metadataByPartition);

      // Phase 5: Download thumbnails (progressive)
      _updateProgress(
        phase: RestorePhase.thumbnailDownload,
        currentPhaseDescription: 'Loading thumbnails...',
      );

      await _downloadThumbnails(channelId, messages, allMetadata);

      // Phase 6: Mark as complete (originals download on-demand)
      _updateProgress(
        phase: RestorePhase.completed,
        overallProgress: 1.0,
        completedItems: allMetadata.length,
        currentPhaseDescription: 'Restore complete!',
      );

      return true;
    } catch (e) {
      _fail(
        RestoreError(
          category: RestoreErrorCategory.unknown,
          message: 'Unexpected error during restore',
          detail: e.toString(),
          retryable: true,
          occurredAt: DateTime.now(),
        ),
      );
      return false;
    }
  }

  /// Pause the restore process.
  void pauseRestore() {
    _isPaused = true;
    _updateProgress(phase: RestorePhase.paused, isPaused: true);
  }

  /// Resume the restore process.
  void resumeRestore() {
    _isPaused = false;
    // Restore to the previous active phase
    if (_progress.phase == RestorePhase.paused) {
      _updateProgress(
        phase: _progress.manifestInfo != null
            ? RestorePhase.metadataDownload
            : RestorePhase.detecting,
        isPaused: false,
      );
    }
  }

  /// Cancel the restore process.
  void cancelRestore() {
    _isCancelled = true;
    _fail(RestoreError.cancelled());
  }

  /// Rebuild the local database from downloaded metadata.
  ///
  /// Per PRD Section 10.2 Step 5: create all MediaItem records,
  /// DeviceFolder records, build SearchIndex, mark items as uploaded.
  Future<void> _rebuildDatabase(
    List<PartitionItem> allMetadata,
    Map<String, List<PartitionItem>> metadataByPartition,
  ) async {
    // Set the manifest in the manifest service
    final manifest = manifestService.getCurrentManifest();
    if (manifest != null) {
      manifestService.setManifest(manifest);
    }

    // Rebuild partitions
    partitionService.clear();
    for (final entry in metadataByPartition.entries) {
      // Add items to partition
      for (int i = 0; i < entry.value.length; i++) {
        partitionService.upsertItem(entry.value[i]);
      }
    }

    // Rebuild search index
    searchIndexService.clear();
    for (final item in allMetadata) {
      searchIndexService.indexItem(item);
    }

    // Populate gallery repository with restored items
    for (final item in allMetadata) {
      final mediaItem = MediaItem(
        localId: item.localId,
        fileHash: item.fileHash,
        telegramMessageId: item.telegramMessageId,
        telegramFileId: item.telegramFileId,
        filePath: '', // Will be populated when file is downloaded
        fileName: item.fileName ?? 'unknown',
        mimeType: item.mimeType ?? 'application/octet-stream',
        fileSize: item.fileSize,
        width: item.width,
        height: item.height,
        durationMs: item.durationMs,
        createdAt: item.createdAt,
        modifiedAt: item.modifiedAt,
        scannedAt: DateTime.now(),
        backedUpAt: item.backedUpAt,
        status: MediaStatus.uploaded,
        isFavorite: item.isFavorite,
        isHidden: item.isHidden,
        isArchived: item.isArchived,
        isTrashed: item.isTrashed,
        trashedAt: item.trashedAt,
        albumName: item.albumName,
        deviceFolder: item.deviceFolder,
        description: item.description,
        tags: item.tags,
      );

      // Record in metadata repository
      await metadataRepository.recordNewItem(mediaItem);
    }
  }

  /// Download thumbnails for all restored items.
  ///
  /// Per PRD Section 10.3: thumbnails download first for fast gallery display.
  Future<void> _downloadThumbnails(
    int channelId,
    List<ChannelMessage> messages,
    List<PartitionItem> allMetadata,
  ) async {
    int downloaded = 0;
    final total = messages.length;

    for (final message in messages) {
      if (_isCancelled) break;
      while (_isPaused) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_isCancelled) break;
      }
      if (_isCancelled) break;

      try {
        final result = await restoreRepository.downloadFile(
          messageId: message.messageId,
          channelId: channelId,
          fileName: message.fileName,
          mode: DownloadMode.thumbnail,
          onProgress: (progress) {
            _updateProgress(overallProgress: (downloaded + progress) / total);
          },
        );

        if (result != null) {
          downloaded++;
          _updateProgress(
            completedItems: downloaded,
            overallProgress: downloaded / total,
            currentFileName: message.fileName,
          );
        }
      } catch (e) {
        debugPrint('[RestoreEngine] Thumbnail download failed: $e');
        // Continue with next item - thumbnails are non-critical
      }
    }
  }

  /// Download a full-resolution file on-demand.
  ///
  /// Called when a user opens an item whose original hasn't been restored yet.
  Future<String?> downloadOriginal({
    required int messageId,
    required int channelId,
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    final result = await restoreRepository.downloadFile(
      messageId: messageId,
      channelId: channelId,
      fileName: fileName,
      mode: DownloadMode.original,
      onProgress: onProgress,
    );

    return result?.filePath;
  }

  /// Resume interrupted restore by checking what's already been done.
  ///
  /// Per PRD Section 10.4: differential restore - skip files already present.
  Future<void> resumeInterruptedRestore() async {
    final existingItems = galleryRepository.mediaItems;
    final existingHashes = existingItems.map((item) => item.fileHash).toSet();

    // Store for differential restore filtering
    _existingHashes = existingHashes;
  }

  Set<String> _existingHashes = {};

  /// Check if a file hash already exists locally.
  bool isAlreadyRestored(String fileHash) {
    return _existingHashes.contains(fileHash);
  }

  void _updateProgress({
    RestorePhase? phase,
    double? overallProgress,
    int? totalItems,
    int? completedItems,
    int? failedItems,
    int? skippedItems,
    String? currentFileName,
    String? currentPhaseDescription,
    int? totalBytes,
    int? downloadedBytes,
    DateTime? startedAt,
    DateTime? estimatedCompletion,
    RestoreError? error,
    bool? isPaused,
    ManifestInfo? manifestInfo,
    bool clearError = false,
    bool clearFileName = false,
  }) {
    _progress = _progress.copyWith(
      phase: phase,
      overallProgress: overallProgress,
      totalItems: totalItems,
      completedItems: completedItems,
      failedItems: failedItems,
      skippedItems: skippedItems,
      currentFileName: currentFileName,
      currentPhaseDescription: currentPhaseDescription,
      totalBytes: totalBytes,
      downloadedBytes: downloadedBytes,
      startedAt: startedAt ?? (_progress.startedAt ?? DateTime.now()),
      estimatedCompletion: estimatedCompletion,
      error: error,
      isPaused: isPaused,
      manifestInfo: manifestInfo,
      clearError: clearError,
      clearFileName: clearFileName,
    );
    _progressController.add(_progress);
  }

  void _fail(RestoreError error) {
    _progress = _progress.copyWith(phase: RestorePhase.failed, error: error);
    _progressController.add(_progress);
  }

  void dispose() {
    _progressController.close();
  }
}
