import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/theme/status_color.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../../data/models/media_item.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Grid tile for the timeline, backed directly by a device [AssetEntity]
/// rather than a scanned/hashed [MediaItem].
///
/// [MediaTile] only ever renders [MediaItem.thumbnailPath], which nothing
/// in the scan pipeline actually sets — so every tile fell back to a plain
/// placeholder icon instead of the real photo. This widget renders the
/// actual thumbnail via [AssetEntity.thumbnailDataWithSize], which
/// photo_manager generates and caches cheaply without needing the full
/// file read or hash that the backup scan does.
class AssetTile extends StatefulWidget {
  const AssetTile({
    super.key,
    required this.asset,
    this.status,
    this.isSelectedForBackup = false,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.size,
  });

  final AssetEntity asset;

  /// Backup status for this asset, if it's been scanned/backed up before.
  /// Only meaningful when [isSelectedForBackup] is true — an item that
  /// isn't selected for backup shows no status badge regardless of this.
  final MediaStatus? status;

  /// Whether the user has chosen this photo for backup. Backup is opt-in:
  /// most photos won't be selected, so the badge only appears for ones
  /// that are — showing the old "about to upload" icon on every single
  /// photo by default would say the opposite of what's actually true.
  final bool isSelectedForBackup;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Multi-select (grid selection) state — unrelated to
  /// [isSelectedForBackup], despite the similar name.
  final bool isSelected;
  final double? size;

  @override
  State<AssetTile> createState() => _AssetTileState();
}

class _AssetTileState extends State<AssetTile>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Cache the thumbnail future so a rebuild (selection toggles, scroll
  // keep-alive, status changes) reuses the same request instead of kicking
  // off a fresh decode every frame. Refreshed only when the asset changes.
  late Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _loadThumbnail();
  }

  @override
  void didUpdateWidget(AssetTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) {
      _thumbnailFuture = _loadThumbnail();
    }
  }

  // A fixed thumbnail size keeps every tile requesting the same cache
  // key from photo_manager's thumbnail cache regardless of the grid's
  // actual pixel size, so scrolling doesn't keep re-decoding.
  Future<Uint8List?> _loadThumbnail() =>
      widget.asset.thumbnailDataWithSize(const ThumbnailSize(300, 300));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildThumbnail(context),
              if (widget.asset.type == AssetType.video)
                _buildVideoIndicator(context),
              if (widget.isSelectedForBackup) _buildStatusIndicator(context)!,
              if (widget.isSelected) ...[
                _buildDimOverlay(context),
                _buildSelectionOverlay(context),
              ],
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
          return const ShimmerPlaceholder();
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return _buildPlaceholder(context);
        }
        return Hero(
          tag: 'asset_${widget.asset.id}',
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) =>
                _buildPlaceholder(context),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        widget.asset.type == AssetType.video ? Symbols.videocam : Symbols.image,
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
            const Icon(Symbols.play_arrow, color: Colors.white, size: 12),
            const SizedBox(width: 2),
            Text(
              _formatDuration(widget.asset.duration),
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

  Widget? _buildStatusIndicator(BuildContext context) {
    // Nothing shown for an unselected item — that's most photos, by
    // design, and badging every single one would read as "about to be
    // uploaded" for photos that were never chosen for backup at all.
    if (!widget.isSelectedForBackup) return null;

    IconData icon;

    switch (widget.status) {
      case null:
      case MediaStatus.pending:
        icon = Symbols.cloud_queue;
      case MediaStatus.uploading:
        icon = Symbols.cloud_sync;
      case MediaStatus.uploaded:
        icon = Symbols.cloud_done;
      case MediaStatus.failed:
        icon = Symbols.cloud_off;
      case MediaStatus.excluded:
        icon = Symbols.block;
    }

    final color = statusColor(context, widget.status);

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

  Widget _buildDimOverlay(BuildContext context) {
    return Positioned.fill(
      child: Container(color: Colors.black38),
    );
  }

  Widget _buildSelectionOverlay(BuildContext context) {
    return Positioned(
      bottom: 4,
      left: 4,
      child: Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Symbols.check,
          color: Theme.of(context).colorScheme.primary,
          size: 16,
        ),
      ),
    );
  }

  String _formatDuration(int durationSeconds) {
    final minutes = (durationSeconds / 60).floor();
    final remainingSeconds = durationSeconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
