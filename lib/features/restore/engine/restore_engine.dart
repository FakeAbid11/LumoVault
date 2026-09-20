import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/storage/thumbnail_cache.dart';
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
    this.ensureTdLibConnected,
  });

  final RestoreRepository restoreRepository;
  final GalleryRepository galleryRepository;
  final MetadataRepository metadataRepository;
  final ManifestService manifestService;
  final PartitionService partitionService;
  final SearchIndexService searchIndexService;

  /// Ensures TDLib is initialized and its auth state has settled before any
  /// restore operation touches it. Same gap, same fix as
  /// [BackupEngine.ensureTdLibConnected] — TDLib only ever gets initialized
  /// via the onboarding auth screens and the Account settings screen, so a
  /// restore triggered any other way (including right after a fresh login,
  /// which is precisely when restore is most likely to be needed) would
  /// otherwise hit "TDLib client not initialized" and hang/fail exactly
  /// like backups did before this was fixed there.
  final Future<void> Function()? ensureTdLibConnected;

  final _progressController = StreamController<RestoreProgress>.broadcast();
  RestoreProgress _progress = const RestoreProgress();
  bool _isCancelled = false;
  bool _isPaused = false;

  /// The phase [pauseRestore] replaced with `paused`, so resuming can go back
  /// to where the user actually left off.
  RestorePhase? _phaseBeforePause;

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
    _phaseBeforePause = null;
    _progress = const RestoreProgress();
    _updateProgress(phase: RestorePhase.detecting);

    try {
      await ensureTdLibConnected?.call();
    } catch (e) {
      _fail(
        RestoreError(
          category: RestoreErrorCategory.unknown,
          message: 'Could not connect to Telegram',
          detail: e.toString(),
          retryable: true,
          occurredAt: DateTime.now(),
        ),
      );
      return false;
    }

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

      if (!detection.hasBackup) {
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
          _cancel();
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
          // The caption already records when this item was backed up. Using
          // DateTime.now() here would rewrite every restored item's backup
          // date to the moment of the restore.
          backedUpAt: metadata.backedUpAt,
          mimeType: metadata.mimeType,
          fileSize: metadata.fileSize,
          width: metadata.width,
          height: metadata.height,
          durationMs: metadata.durationMs,
          isFavorite: metadata.isFavorite,
          isHidden: metadata.isHidden,
          isArchived: metadata.isArchived,
          isTrashed: metadata.isTrashed,
          trashedAt: metadata.trashedAt,
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

      await _rebuildDatabase(metadataByPartition, manifest);

      // Phase 5: Download thumbnails (progressive)
      _updateProgress(
        phase: RestorePhase.thumbnailDownload,
        currentPhaseDescription: 'Loading thumbnails...',
      );

      final thumbnailsDone = await _downloadThumbnails(
        channelId,
        messages,
        allMetadata,
      );
      // A cancelled thumbnail phase must not fall through to "Restore
      // complete!" — the loop used to just `break`, and startRestore then
      // reported success for a cancelled run.
      if (!thumbnailsDone) return false;

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
    // Remember where we were: this overwrites the phase with `paused`, so
    // without it the information is gone by the time the user resumes.
    if (_progress.phase != RestorePhase.paused) {
      _phaseBeforePause = _progress.phase;
    }
    _isPaused = true;
    _updateProgress(phase: RestorePhase.paused, isPaused: true);
  }

  /// Resume the restore process.
  void resumeRestore() {
    _isPaused = false;
    // Restore to the previous active phase.
    if (_progress.phase == RestorePhase.paused) {
      _updateProgress(
        // Used to hardcode metadataDownload, so resuming partway through the
        // thumbnail phase re-announced an earlier step and the progress screen
        // showed the wrong stage for the remainder of the run.
        phase:
            _phaseBeforePause ??
            (_progress.manifestInfo != null
                ? RestorePhase.metadataDownload
                : RestorePhase.detecting),
        isPaused: false,
      );
      _phaseBeforePause = null;
    }
  }

  /// Cancel the restore process.
  void cancelRestore() {
    _isCancelled = true;
    _cancel();
  }

  /// Report the user-initiated cancellation.
  ///
  /// This used to route through [_fail], so a cancel showed as "Restore
  /// failed" and [RestorePhase.cancelled] was dead code no engine path ever
  /// set — while a test had grown up asserting the wrong shape.
  void _cancel() {
    _progress = _progress.copyWith(
      phase: RestorePhase.cancelled,
      error: RestoreError.cancelled(),
    );
    _progressController.add(_progress);
  }

  /// Rebuild the local database from downloaded metadata.
  ///
  /// Per PRD Section 10.2 Step 5: create all MediaItem records,
  /// DeviceFolder records, build SearchIndex, mark items as uploaded.
  ///
  /// Merge-only by design — it reads into the catalog already on this device
  /// rather than replacing it. See [_keepPriorRecord] for which record wins.
  Future<void> _rebuildDatabase(
    Map<String, List<PartitionItem>> metadataByPartition,
    Manifest channelManifest,
  ) async {
    // A deletion may be known locally (via a Layer-3 reconcile) even though the
    // channel media message — and therefore its caption — still exists. Treat
    // such an item as tombstoned so the caption rebuild below can't resurrect
    // it, exactly as an in-partition isDeleted flag would.
    bool isTombstoned(PartitionItem item) {
      if (item.isDeleted) return true;
      return metadataRepository.getItemMetadata(item.localId)?.isDeleted ??
          false;
    }

    // Snapshot local knowledge BEFORE writing anything. partitionService.clear()
    // used to be the first statement here, throwing away deletion tombstones and
    // every Layer-3 field a caption never carried (albums, tags, AI labels,
    // locationName, post-upload favorite/archive/hidden edits). The restored,
    // thinner catalog was then pushed back to the channel, un-deleting on BOTH
    // devices items the user had deleted for good.
    final priorItems = <String, PartitionItem>{
      for (final partition in partitionService.getAllPartitions())
        for (final item in partition.items) item.localId: item,
    };

    // Install the manifest downloaded from the channel. This used to read
    // manifestService.getCurrentManifest() and set that same value straight
    // back — a no-op — so a fresh device had no baseline hash and every
    // partition looked permanently dirty to the sync layer.
    manifestService.setManifest(channelManifest);

    final adopted = <PartitionItem>[];
    for (final entry in metadataByPartition.entries) {
      for (final item in entry.value) {
        final prior = priorItems[item.localId];
        if (prior != null && _keepPriorRecord(prior, item)) continue;
        partitionService.upsertItem(item);
        adopted.add(item);
      }
    }

    // Rebuild the search index from the MERGED partitions rather than from the
    // caption list. Clearing and re-indexing only captions would drop every
    // local record this restore just decided to keep — including the
    // tombstones, which is the opposite of why they are kept.
    searchIndexService.clear();
    for (final partition in partitionService.getAllPartitions()) {
      for (final item in partition.items) {
        if (item.isDeleted) continue;
        searchIndexService.indexItem(item);
      }
    }

    // Populate gallery repository with restored items
    //
    // The in-memory metadata layers above are persisted to their own files,
    // but the gallery (timeline/albums/search) is backed by the drift
    // database. Previously nothing wrote restored items into [galleryRepository],
    // so a freshly restored library showed up empty in the app until the next
    // device scan happened to re-discover the files. mergeTelegramItems adds
    // them to the in-memory read model AND persists them through MediaDao.
    final galleryItems = <MediaItem>[];
    for (final item in adopted) {
      // A tombstoned item was deleted on another device (or here, and the
      // deletion propagated through Layer 3). Rebuilding it from its still-
      // present media caption would resurrect it, so skip it entirely — this
      // is the whole reason the deletion tombstone survives in the partition.
      if (isTombstoned(item)) continue;
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
      galleryItems.add(mediaItem);
    }

    await galleryRepository.mergeTelegramItems(galleryItems);
  }

  /// Whether a record already held locally should survive a restore untouched.
  ///
  /// A tombstone always wins: "this was deleted on purpose" is information a
  /// caption — written once at upload, while the item still existed — can
  /// never carry. Otherwise the later modification does, because captions are
  /// never rewritten after upload, so anything already in the local partition
  /// reflects an edit made after the file went up.
  static bool _keepPriorRecord(PartitionItem prior, PartitionItem fromCaption) {
    if (prior.isDeleted) return true;
    return prior.modifiedAt.isAfter(fromCaption.modifiedAt);
  }

  /// Download thumbnails for all restored items.
  ///
  /// Per PRD Section 10.3: thumbnails download first for fast gallery display.
  ///
  /// Items whose thumbnail is already in the shared cache are skipped — this
  /// is what makes a re-run after an interruption (or a plain re-restore)
  /// differential instead of re-fetching every file. Note the cache key is
  /// the caption mediaItemId (`msg_<id>` fallback), the same scheme the
  /// channel scan uses, so a restore that runs over an existing library also
  /// skips everything the user still has from before.
  ///
  /// Returns false when the restore was cancelled mid-phase, true when every
  /// message was processed (downloaded, skipped, or failed).
  Future<bool> _downloadThumbnails(
    int channelId,
    List<ChannelMessage> messages,
    List<PartitionItem> allMetadata,
  ) async {
    int downloaded = 0;
    int skipped = 0;
    int failed = 0;
    final total = messages.length;

    for (final message in messages) {
      if (_isCancelled) return false;
      while (_isPaused) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_isCancelled) return false;
      }
      if (_isCancelled) return false;

      final metadata = message.captionMetadata;
      final localId = (metadata == null || metadata.mediaItemId.isEmpty)
          ? 'msg_${message.messageId}'
          : metadata.mediaItemId;

      final processed = downloaded + skipped + failed;
      if (await ThumbnailCache.instance.contains(localId)) {
        skipped++;
        _updateProgress(
          completedItems: processed + 1,
          skippedItems: skipped,
          overallProgress: (processed + 1) / total,
          currentFileName: message.fileName,
        );
        continue;
      }

      try {
        final result = await restoreRepository.downloadFile(
          messageId: message.messageId,
          channelId: channelId,
          fileName: message.fileName,
          mode: DownloadMode.thumbnail,
          onProgress: (progress) {
            // Base on `processed` (everything finished before this item) —
            // the old formula used `downloaded` alone, so with skipped items
            // in the mix every intra-file tick made the bar jump backwards.
            _updateProgress(overallProgress: (processed + progress) / total);
          },
        );

        downloaded++;
        _updateProgress(
          completedItems: processed + 1,
          overallProgress: (processed + 1) / total,
          currentFileName: message.fileName,
        );

        // Write the thumbnail into the shared cache under the same key
        // scheme as the channel scan (caption mediaItemId, or the
        // msg_<messageId> fallback) so the timeline shows it immediately
        // instead of re-downloading per tile. These bytes used to be
        // discarded after download, which left every restored item's tile
        // stuck on the placeholder.
        try {
          final bytes = await File(result.filePath).readAsBytes();
          await ThumbnailCache.instance.put(localId, bytes);
        } catch (e) {
          debugPrint('[RestoreEngine] Thumbnail cache write failed: $e');
        }
        // Same cleanup the channel scan does after caching: without it every
        // restore leaves a full temp copy of the library behind in the cache
        // dir (the bytes live on in ThumbnailCache under the localId key).
        try {
          await File(result.filePath).delete();
        } catch (_) {
          // Non-critical: temp file cleanup failure.
        }
      } catch (e) {
        debugPrint('[RestoreEngine] Thumbnail download failed: $e');
        // Thumbnails are non-critical, but the failure still counts toward
        // overall progress — otherwise completedItems could never reach
        // `total` and the bar never filled.
        failed++;
        _updateProgress(
          completedItems: processed + 1,
          overallProgress: (processed + 1) / total,
          currentFileName: message.fileName,
        );
      }
    }
    return true;
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

    return result.filePath;
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
