import 'dart:async';
import 'dart:io';

import 'package:convert/convert.dart' show AccumulatorSink;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/media_item.dart';

/// Result of an incremental scan.
class IncrementalScanResult {
  const IncrementalScanResult({
    required this.newItems,
    required this.updatedItems,
    required this.deletedIds,
    required this.totalChecked,
    required this.duration,
  });

  /// New media items discovered (not in the existing set).
  final List<MediaItem> newItems;

  /// Existing items whose modifiedAt timestamp changed.
  final List<MediaItem> updatedItems;

  /// Local IDs of items that were deleted from the device.
  final List<String> deletedIds;

  /// Total number of device items checked.
  final int totalChecked;

  /// How long the scan took.
  final Duration duration;

  bool get hasChanges =>
      newItems.isNotEmpty || updatedItems.isNotEmpty || deletedIds.isNotEmpty;
}

/// Performs incremental device scans by comparing against a known set.
///
/// Uses a lightweight approach: fetches device assets and compares
/// modifiedAt timestamps or local IDs against the existing set,
/// avoiding full hash recomputation for unchanged files.
class IncrementalScanner {
  IncrementalScanner();

  /// Scan for changes since [lastKnownItems].
  ///
  /// [lastKnownItems] is the set of items already tracked by the app,
  /// keyed by [MediaItem.localId]. [includedFolders] optionally limits
  /// the scan to specific device folders. [onBatch], if given, is called
  /// periodically with newly-processed items so the caller can persist them
  /// as the scan runs rather than only once at the very end — otherwise a
  /// slow scan that gets interrupted (or that the user closes the app
  /// during) loses all its progress and starts over from scratch next time.
  Future<IncrementalScanResult> scanForChanges({
    required Map<String, MediaItem> lastKnownItems,
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
    void Function(List<MediaItem> newItems, List<MediaItem> updatedItems)?
    onBatch,
  }) async {
    final stopwatch = Stopwatch()..start();

    // Get all albums from the device.
    final albums = await PhotoManager.getAssetPathList(type: RequestType.all);

    final newItems = <MediaItem>[];
    final updatedItems = <MediaItem>[];
    final seenIds = <String>{};
    var totalChecked = 0;

    var pendingNew = <MediaItem>[];
    var pendingUpdated = <MediaItem>[];
    const batchFlushSize = 50;

    void flushBatch() {
      if (onBatch == null) return;
      if (pendingNew.isEmpty && pendingUpdated.isEmpty) return;
      onBatch(pendingNew, pendingUpdated);
      pendingNew = [];
      pendingUpdated = [];
    }

    // Same fix as PhotoManagerScannerService: `totalChecked` accumulates
    // across every album, so it must be compared against a grand total
    // summed across all included albums up front, not each album's own
    // (much smaller) asset count.
    var grandTotal = 0;
    for (final album in albums) {
      if (includedFolders != null && includedFolders.isNotEmpty) {
        if (!includedFolders.contains(album.name)) continue;
      }
      grandTotal += await album.assetCountAsync;
    }

    for (final album in albums) {
      // Filter by included folders if specified.
      if (includedFolders != null && includedFolders.isNotEmpty) {
        if (!includedFolders.contains(album.name)) continue;
      }

      final assetCount = await album.assetCountAsync;

      // Fetching the entire album in one getAssetListPaged call means a
      // single slow/stuck page blocks the whole album (and, since progress
      // is per-item, looks identical to a per-item hang from the outside).
      // Paginating keeps each native call small and bounded, and — more
      // importantly right now — a page that times out only loses that one
      // page's items for this pass (they'll be picked up on the next scan,
      // since they're never marked seen) instead of hanging indefinitely.
      const pageSize = 200;
      final totalPages = (assetCount / pageSize).ceil();

      for (var page = 0; page < totalPages; page++) {
        List<AssetEntity> assets;
        try {
          assets = await album
              .getAssetListPaged(page: page, size: pageSize)
              .timeout(const Duration(seconds: 30));
        } on TimeoutException {
          debugPrint(
            '[IncrementalScanner] Timed out fetching ${album.name} '
            'page $page (assets ${page * pageSize}-'
            '${(page + 1) * pageSize} of $assetCount) — skipping this '
            'page for now, will retry next scan.',
          );
          totalChecked += pageSize;
          onProgress?.call(totalChecked, grandTotal);
          continue;
        }

        for (var i = 0; i < assets.length; i++) {
          final asset = assets[i];
          final localId = asset.id;
          seenIds.add(localId);
          totalChecked++;

          final existingItem = lastKnownItems[localId];

          if (existingItem == null) {
            // Brand new item — need full scan.
            debugPrint(
              '[IncrementalScanner] Processing new asset $totalChecked/'
              '$grandTotal: $localId',
            );
            // An outer timeout on top of the internal ones in
            // _buildMediaItemFromAsset — originFile and the hash aren't
            // the only platform-channel calls in there (titleAsync is
            // another, unprotected one), and rather than track down and
            // wrap every individual call that could stall, bounding the
            // whole operation guarantees the loop keeps moving regardless
            // of which specific line turns out to be the actual culprit.
            final item = await _buildMediaItemFromAsset(
              asset,
            ).timeout(const Duration(seconds: 90), onTimeout: () => null);
            if (item != null) {
              newItems.add(item);
              pendingNew.add(item);
            } else {
              debugPrint(
                '[IncrementalScanner] Asset $localId timed out or failed — '
                'skipping, will retry next scan.',
              );
            }
          } else {
            // Check if modified timestamp changed.
            final deviceModified = asset.modifiedDateTime;
            if (deviceModified.isAfter(existingItem.modifiedAt)) {
              // File was modified — rebuild metadata.
              final updated = await _buildMediaItemFromAsset(
                asset,
              ).timeout(const Duration(seconds: 90), onTimeout: () => null);
              if (updated != null) {
                updatedItems.add(updated);
                pendingUpdated.add(updated);
              }
            }
            // else: unchanged, skip.
          }

          if (onProgress != null &&
              (totalChecked % 50 == 0 || totalChecked == grandTotal)) {
            onProgress(totalChecked, grandTotal);
          }

          if (pendingNew.length + pendingUpdated.length >= batchFlushSize) {
            flushBatch();
          }
        }
      }
    }

    flushBatch();

    // Step 3: Detect deletions.
    final deletedIds = lastKnownItems.keys
        .where((id) => !seenIds.contains(id))
        .toList();

    stopwatch.stop();

    return IncrementalScanResult(
      newItems: newItems,
      updatedItems: updatedItems,
      deletedIds: deletedIds,
      totalChecked: totalChecked,
      duration: stopwatch.elapsed,
    );
  }

  /// Build full backup metadata (including the file hash) for a single
  /// asset, on demand — for when the user acts on one specific photo (e.g.
  /// toggling it in/out of backup from the viewer) before it's ever been
  /// through a full scan, rather than needing to wait for one.
  Future<MediaItem?> buildSingleItem(AssetEntity asset) =>
      _buildMediaItemFromAsset(asset);

  /// Build a [MediaItem] from a device [AssetEntity].
  Future<MediaItem?> _buildMediaItemFromAsset(AssetEntity asset) async {
    try {
      // `originFile` can hang far longer than expected for assets that
      // aren't actually resident on-device — e.g. a photo whose local copy
      // was freed up by a cloud-backup app and now has to be re-downloaded
      // on demand before this returns. A single such asset in a library of
      // thousands would otherwise stall the entire scan indefinitely with
      // no visible error, which is what "stuck at N/total, not moving" is.
      final file = await asset.originFile.timeout(
        const Duration(seconds: 30),
        onTimeout: () => null,
      );
      if (file == null) return null;

      // titleAsync is another platform-channel call, same risk profile as
      // originFile — falls back to a generic name on timeout rather than
      // losing the whole item over a filename lookup.
      final title = await asset.titleAsync.timeout(
        const Duration(seconds: 15),
        onTimeout: () => asset.id,
      );
      final mimeType = _getMimeType(asset);
      final durationMs = asset.type == AssetType.video
          ? asset.duration * 1000
          : null;

      // Hashing runs on a background isolate via compute() — sha256 over a
      // full-resolution photo or video is CPU-heavy synchronous work, and
      // running it on the main isolate blocks the UI thread for its
      // duration, which is what caused the visible lag/stutter while
      // scanning. compute() needs a top-level function, so this calls
      // _hashFileInIsolate below rather than an instance method. Also
      // timed out for the same reason as originFile above — an unusually
      // large or slow-to-read file shouldn't be able to stall the scan.
      final hash = await compute(
        _hashFileInIsolate,
        file.path,
      ).timeout(const Duration(seconds: 60), onTimeout: () => '');
      if (hash.isEmpty) return null;

      return MediaItem(
        localId: asset.id,
        fileHash: hash,
        filePath: file.path,
        fileName: title,
        mimeType: mimeType,
        fileSize: file.lengthSync(),
        width: asset.width,
        height: asset.height,
        durationMs: durationMs != null && durationMs > 0 ? durationMs : null,
        createdAt: asset.createDateTime,
        modifiedAt: asset.modifiedDateTime,
        scannedAt: DateTime.now(),
        status: MediaStatus.pending,
        // Backup is opt-in: newly-discovered items start excluded and stay
        // that way until the user explicitly selects them (in the media
        // viewer, or via multi-select) — a bulk scan should never quietly
        // decide to back up someone's whole camera roll on its own.
        // GalleryRepository.setBackupExcluded overrides this immediately
        // when the caller is the one explicitly including something the
        // scanner had never seen before, so this default only actually
        // governs the bulk-scan discovery path.
        isExcluded: true,
        deviceFolder: asset.relativePath,
      );
    } catch (e) {
      debugPrint(
        '[IncrementalScanner] Failed to process asset ${asset.id}: $e',
      );
      return null;
    }
  }

  /// Infer MIME type from asset type.
  String _getMimeType(AssetEntity asset) {
    return switch (asset.type) {
      AssetType.image => 'image/jpeg',
      AssetType.video => 'video/mp4',
      AssetType.audio => 'audio/mpeg',
      _ => 'application/octet-stream',
    };
  }
}

/// Compute the SHA-256 hash of a file, streamed in chunks rather than
/// loaded fully into memory at once (a multi-hundred-MB video file used to
/// get read entirely into a single byte array just to hash it). Must be a
/// top-level function — [compute] spawns an isolate that can't capture
/// instance state.
Future<String> _hashFileInIsolate(String path) async {
  final file = File(path);
  if (!await file.exists()) return '';
  final output = AccumulatorSink<Digest>();
  final input = sha256.startChunkedConversion(output);
  await for (final chunk in file.openRead()) {
    input.add(chunk);
  }
  input.close();
  return output.events.single.toString();
}
