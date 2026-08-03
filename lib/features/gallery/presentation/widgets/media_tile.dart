import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/storage/thumbnail_cache.dart';
import '../../data/models/media_item.dart';

class MediaTile extends StatefulWidget {
  const MediaTile({
    super.key,
    required this.mediaItem,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.showStatus = false,
    this.size,
    this.thumbnailLoader,
    this.reloadGeneration = 0,
  });
  final MediaItem mediaItem;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool showStatus;
  final double? size;

  /// Optional thumbnail source override. Defaults to [defaultThumbnailLoader].
  /// Injectable so tests can stub thumbnail bytes without photo_manager.
  final Future<Uint8List?> Function(MediaItem item)? thumbnailLoader;

  /// Version counter that forces the thumbnail to reload even when [mediaItem]
  /// is unchanged. The timeline bumps this when a channel scan completes, a
  /// new upload lands, or the thumbnail cache is cleared — tiles that
  /// previously timed out (placeholder) re-run their loader instead of staying
  /// blank for the rest of the session.
  final int reloadGeneration;

  /// Default thumbnail source: consult [ThumbnailCache] first (Telegram items
  /// get their bytes written there by the channel scan/restore), then fall
  /// back to generating a thumbnail from the device asset via photo_manager
  /// for local items — mirroring [AssetTile]. If that fails or stalls, an
  /// image item's on-disk file is read directly as a last resort. Generated
  /// bytes are written back to the cache so re-renders and scroll-back hit
  /// memory/disk instead of repeating the platform lookup.
  ///
  /// Static so it can be unit-tested directly (a widget test's FakeAsync zone
  /// can't drive the real file I/O in the fallback).
  static Future<Uint8List?> defaultThumbnailLoader(MediaItem item) async {
    final cached = await ThumbnailCache.instance.get(item.localId);
    if (cached != null) return cached;

    if (item.isTelegram) return null;

    Uint8List? bytes;
    try {
      // Same defensive pattern as the scanners: photo_manager platform calls
      // can stall indefinitely (e.g. permission revoked, plugin deadlock), so
      // bound them and fall back instead of blocking the grid on a stuck tile.
      final asset = await AssetEntity.fromId(
        item.localId,
      ).timeout(const Duration(seconds: 15));
      if (asset == null) return _readFileFallback(item);
      bytes = await asset
          .thumbnailDataWithSize(const ThumbnailSize(300, 300))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Timeout, photo permission revoked, platform error, etc. — fall
      // through to the on-disk file rather than giving up.
    }
    if (bytes != null) {
      try {
        await ThumbnailCache.instance.put(item.localId, bytes);
      } catch (_) {
        // Cache write failure is non-fatal — render the bytes anyway.
      }
      return bytes;
    }
    return _readFileFallback(item);
  }

  /// Last-resort source for local image items whose photo_manager lookup
  /// failed or timed out: read the actual file on disk. photo_manager remains
  /// the primary source (it keeps working under Android 13+ partial media
  /// access), so this is only reached when that path is unavailable.
  static Future<Uint8List?> _readFileFallback(MediaItem item) async {
    if (item.mediaType != MediaType.image || item.filePath.isEmpty) {
      return null;
    }
    try {
      final bytes = await File(item.filePath).readAsBytes().timeout(
        const Duration(seconds: 5),
      );
      if (bytes.isEmpty) return null;
      try {
        await ThumbnailCache.instance.put(item.localId, bytes);
      } catch (_) {
        // Non-fatal — the tile still renders from [bytes].
      }
      return bytes;
    } catch (_) {
      // Unreadable or missing file — the placeholder is the correct fallback.
      return null;
    }
  }

  @override
  State<MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<MediaTile> {
  late Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant MediaTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload when the item changes or when the caller signals that thumbnail
    // sources may have changed (scan completed, upload landed, cache cleared).
    if (oldWidget.mediaItem.localId != widget.mediaItem.localId ||
        oldWidget.reloadGeneration != widget.reloadGeneration) {
      _thumbnailFuture = _loadThumbnail();
    }
  }

  Future<Uint8List?> _loadThumbnail() {
    final item = widget.mediaItem;
    final loader = widget.thumbnailLoader ?? MediaTile.defaultThumbnailLoader;
    return loader(item);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: widget.isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                )
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildThumbnail(context),
              if (widget.mediaItem.isVideo) _buildVideoIndicator(context),
              if (widget.showStatus) _buildStatusIndicator(context),
              if (widget.isSelected) _buildSelectionOverlay(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _thumbnailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          );
        }
        final bytes = snapshot.data;
        if (bytes != null) {
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) =>
                _buildPlaceholder(context),
          );
        }
        return _buildPlaceholder(context);
      },
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        widget.mediaItem.isVideo ? Icons.videocam : Icons.image,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        size: 32,
      ),
    );
  }

  Widget _buildVideoIndicator(BuildContext context) {
    return Positioned(
      bottom: 4,
      right: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow, color: Colors.white, size: 12),
            const SizedBox(width: 2),
            Text(
              _formatDuration(widget.mediaItem.durationMs),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(BuildContext context) {
    IconData icon;
    Color color;

    switch (widget.mediaItem.status) {
      case MediaStatus.pending:
        icon = Icons.cloud_upload_outlined;
        color = Colors.orange;
      case MediaStatus.uploading:
        icon = Icons.cloud_sync;
        color = Colors.blue;
      case MediaStatus.uploaded:
        icon = Icons.cloud_done;
        color = Colors.green;
      case MediaStatus.failed:
        icon = Icons.cloud_off;
        color = Colors.red;
      case MediaStatus.excluded:
        icon = Icons.block;
        color = Colors.grey;
    }

    return Positioned(
      top: 4,
      left: 4,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: color, size: 14),
      ),
    );
  }

  Widget _buildSelectionOverlay(BuildContext context) {
    return Positioned(
      top: 4,
      right: 4,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 16),
      ),
    );
  }

  String _formatDuration(int? durationMs) {
    if (durationMs == null) return '0:00';
    final seconds = (durationMs / 1000).floor();
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
