import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/models/media_item.dart';

class MediaTile extends StatelessWidget {
  const MediaTile({
    super.key,
    required this.mediaItem,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.showStatus = false,
    this.size,
  });
  final MediaItem mediaItem;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool showStatus;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: isSelected
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
              if (mediaItem.isVideo) _buildVideoIndicator(context),
              if (showStatus) _buildStatusIndicator(context),
              if (isSelected) _buildSelectionOverlay(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    if (mediaItem.thumbnailPath != null) {
      final file = File(mediaItem.thumbnailPath!);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildPlaceholder(context);
          },
        );
      }
    }

    return _buildPlaceholder(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        mediaItem.isVideo ? Icons.videocam : Icons.image,
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
              _formatDuration(mediaItem.durationMs),
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

    switch (mediaItem.status) {
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
