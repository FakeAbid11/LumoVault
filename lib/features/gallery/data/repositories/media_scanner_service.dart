import 'dart:async';
import 'dart:io';

import 'package:convert/convert.dart' show AccumulatorSink;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import '../models/media_item.dart';
import '../models/device_folder.dart';

class ScanResult {
  const ScanResult({
    required this.mediaItems,
    required this.folders,
    required this.totalScanned,
    required this.newItems,
    required this.updatedItems,
    required this.duration,
  });
  final List<MediaItem> mediaItems;
  final List<DeviceFolder> folders;
  final int totalScanned;
  final int newItems;
  final int updatedItems;
  final Duration duration;
}

abstract class MediaScannerService {
  Future<bool> checkPermission();
  Future<bool> requestPermission();
  Future<ScanResult> scanDevice({
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
  });

  /// Lists every photo/video on the device for display purposes — no file
  /// reads or hashing, just metadata (already cached by the OS), so this is
  /// fast even for a large library. Used to populate the timeline directly,
  /// decoupled from the much slower hash-based scan that [scanDevice] does
  /// (that one's still needed, but only when actually backing files up).
  Future<List<AssetEntity>> listAllAssets({
    void Function(int loaded)? onProgress,
  });
  Future<Uint8List?> getThumbnail(String assetId);
  Future<File?> getFullFile(String assetId);
  Future<List<DeviceFolder>> getDeviceFolders();
}

class PhotoManagerScannerService implements MediaScannerService {
  PhotoManagerScannerService();

  @override
  Future<bool> checkPermission() async {
    final state = await PhotoManager.requestPermissionExtend();
    return state.isAuth || state.hasAccess;
  }

  @override
  Future<bool> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend();
    return state.isAuth;
  }

  @override
  Future<ScanResult> scanDevice({
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
    );

    final allMedia = <MediaItem>[];
    final folders = <DeviceFolder>[];
    int totalScanned = 0;

    // `totalScanned` below accumulates across every album, but each album's
    // own asset count only covers that one album — reporting progress as
    // (totalScanned, album.assetCount) compares a running grand total against
    // a per-album denominator, which drifts further out of sync with every
    // album processed (e.g. "3995/63" once a handful of albums have been
    // scanned). Sum the included albums' counts up front so progress is
    // reported against one consistent grand total throughout the scan.
    int grandTotal = 0;
    for (final album in albums) {
      final albumName = p.basename(album.name);
      if (includedFolders != null && !includedFolders.contains(albumName)) {
        continue;
      }
      grandTotal += await album.assetCountAsync;
    }

    for (final album in albums) {
      final albumName = p.basename(album.name);

      if (includedFolders != null && !includedFolders.contains(albumName)) {
        continue;
      }

      final assetCount = await album.assetCountAsync;

      folders.add(
        DeviceFolder(
          path: album.name,
          name: albumName,
          isIncluded: includedFolders?.contains(albumName) ?? true,
          totalItems: assetCount,
          totalSize: 0,
          lastScannedAt: DateTime.now(),
          createdAt: DateTime.now(),
        ),
      );

      // Same reasoning as IncrementalScanner: fetching an entire large
      // album in one getAssetListPaged call means a single slow/stuck page
      // blocks the whole album with no visible error. Paginating bounds
      // each native call and lets a timed-out page be skipped (and picked
      // up on the next scan) instead of hanging the whole thing.
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
            '[PhotoManagerScannerService] Timed out fetching $albumName '
            'page $page — skipping this page for now, will retry next scan.',
          );
          totalScanned += pageSize;
          onProgress?.call(totalScanned, grandTotal);
          continue;
        }

        for (int i = 0; i < assets.length; i++) {
          final asset = assets[i];
          totalScanned++;
          onProgress?.call(totalScanned, grandTotal);

          if (asset.type != AssetType.image && asset.type != AssetType.video) {
            continue;
          }

          // Same backstop as IncrementalScanner: an outer timeout on top of
          // the internal ones in _buildMediaItemFromAsset, so the loop keeps
          // moving even if some platform-channel call in there other than
          // originFile or the hash turns out to be the one that stalls.
          final mediaItem = await _buildMediaItemFromAsset(
            asset: asset,
            albumName: albumName,
            album: album,
          ).timeout(const Duration(seconds: 90), onTimeout: () => null);

          if (mediaItem == null) continue;
          allMedia.add(mediaItem);
        }
      }
    }

    stopwatch.stop();

    return ScanResult(
      mediaItems: allMedia,
      folders: folders,
      totalScanned: totalScanned,
      newItems: allMedia.length,
      updatedItems: 0,
      duration: stopwatch.elapsed,
    );
  }

  @override
  Future<Uint8List?> getThumbnail(String assetId) async {
    final list = await PhotoManager.getAssetPathList(type: RequestType.common);

    for (final album in list) {
      final assets = await album.getAssetListPaged(page: 0, size: 100);
      for (final asset in assets) {
        if (asset.id == assetId) {
          return asset.thumbnailData;
        }
      }
    }

    return null;
  }

  @override
  Future<File?> getFullFile(String assetId) async {
    final list = await PhotoManager.getAssetPathList(type: RequestType.common);

    for (final album in list) {
      final assets = await album.getAssetListPaged(page: 0, size: 100);
      for (final asset in assets) {
        if (asset.id == assetId) {
          return asset.originFile;
        }
      }
    }

    return null;
  }

  @override
  Future<List<DeviceFolder>> getDeviceFolders() async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
    );

    final folders = <DeviceFolder>[];
    for (final album in albums) {
      final assetCount = await album.assetCountAsync;
      final albumName = p.basename(album.name);

      folders.add(
        DeviceFolder(
          path: album.name,
          name: albumName,
          isIncluded: true,
          totalItems: assetCount,
          totalSize: 0,
          lastScannedAt: DateTime.now(),
          createdAt: DateTime.now(),
        ),
      );
    }

    return folders;
  }

  @override
  Future<List<AssetEntity>> listAllAssets({
    void Function(int loaded)? onProgress,
  }) async {
    // onlyAll gets the single OS-provided "all photos" pseudo-album instead
    // of per-folder albums, so the same asset appearing in both e.g.
    // "Camera" and "All Photos" doesn't get listed (and shown) twice.
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
    );
    if (albums.isEmpty) return [];

    final all = albums.first;
    final assetCount = await all.assetCountAsync;

    const pageSize = 200;
    final totalPages = (assetCount / pageSize).ceil();
    final result = <AssetEntity>[];

    for (var page = 0; page < totalPages; page++) {
      List<AssetEntity> pageAssets;
      try {
        pageAssets = await all
            .getAssetListPaged(page: page, size: pageSize)
            .timeout(const Duration(seconds: 30));
      } on TimeoutException {
        debugPrint(
          '[PhotoManagerScannerService] Timed out listing page $page — '
          'skipping (metadata-only listing, so this should be rare).',
        );
        continue;
      }
      result.addAll(pageAssets);
      onProgress?.call(result.length);
    }

    return result;
  }

  /// Build a [MediaItem] from a device [AssetEntity], for one entry in
  /// [album]. Extracted so the caller can wrap the whole thing in one
  /// outer timeout rather than only the individual calls known to be risky.
  Future<MediaItem?> _buildMediaItemFromAsset({
    required AssetEntity asset,
    required String albumName,
    required AssetPathEntity album,
  }) async {
    // `originFile` can hang far longer than expected for assets not
    // actually resident on-device (e.g. freed-up-space cloud photos
    // that need re-downloading first) — a single such file could
    // otherwise stall the entire scan with no visible error.
    final file = await asset.originFile.timeout(
      const Duration(seconds: 30),
      onTimeout: () => null,
    );
    if (file == null) return null;

    // Was MD5 computed via readAsBytes() on the main isolate — two
    // problems: (1) IncrementalScanner (used for every scan after the
    // first) hashes with SHA-256, so the same file could get a
    // different fileHash depending on which scanner last touched it,
    // breaking hash-based dedup between the two paths; (2) loading a
    // full-resolution video's entire bytes into memory just to hash it
    // synchronously blocks the UI thread for the duration. Matches
    // IncrementalScanner's approach now: streamed, and off the main
    // isolate via compute(), with a timeout for the same reason as
    // originFile above.
    final hash = await compute(
      _hashFileInIsolate,
      file.path,
    ).timeout(const Duration(seconds: 60), onTimeout: () => '');
    if (hash.isEmpty) return null;

    return MediaItem(
      localId: asset.id,
      fileHash: hash,
      filePath: file.path,
      fileName: p.basename(file.path),
      mimeType: _getMimeType(asset),
      fileSize: file.lengthSync(),
      width: asset.width,
      height: asset.height,
      durationMs: asset.type == AssetType.video ? asset.duration * 1000 : null,
      createdAt: asset.createDateTime,
      modifiedAt: asset.modifiedDateTime,
      scannedAt: DateTime.now(),
      // See the matching comment in IncrementalScanner — backup is opt-in,
      // so a bulk scan discovering an item doesn't mean it should be
      // backed up, only that the app now knows it exists.
      isExcluded: true,
      albumName: albumName,
      deviceFolder: album.name,
    );
  }

  String _getMimeType(AssetEntity asset) {
    if (asset.type == AssetType.image) {
      return 'image/jpeg';
    } else if (asset.type == AssetType.video) {
      return 'video/mp4';
    }
    return 'application/octet-stream';
  }
}

/// Compute the SHA-256 hash of a file, streamed in chunks. Must be a
/// top-level function — [compute] spawns an isolate that can't capture
/// instance state. Duplicated from [IncrementalScanner]'s identical helper
/// rather than shared, to keep each scanner file self-contained.
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
