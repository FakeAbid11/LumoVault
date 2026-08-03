import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/backup_providers.dart';
import '../../../../core/di/channel_scan_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../data/models/media_item.dart';
import '../widgets/date_header.dart';
import '../widgets/media_tile.dart';

/// Timeline screen — shows backed-up photos/videos from both the local
/// device and the Telegram storage channel.
///
/// Local items (from device scan) and Telegram-only items (from channel scan)
/// are merged and grouped by date. Tapping a local item opens the media
/// viewer; tapping a Telegram-only item shows the detail info.
class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch backup stats for live refresh on upload completion.
    ref.watch(backupStatsProvider);
    // Watch gallery changes (channel scan adds items here).
    final repository = ref.watch(galleryRepositoryProvider);

    // Watch channel scan progress for loading indicator.
    final (scanned, total, isScanning) = ref.watch(channelScanProgressProvider);

    final uploadedItems = repository.mediaItems
        .where(
          (item) =>
              item.status == MediaStatus.uploaded &&
              !item.isTrashed &&
              !item.isHidden,
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timeline'),
        actions: [
          if (isScanning)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: _buildBody(context, ref, uploadedItems, isScanning, scanned, total),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<MediaItem> uploadedItems,
    bool isScanning,
    int scanned,
    int total,
  ) {
    if (uploadedItems.isEmpty && !isScanning) {
      return _buildEmptyState(context, ref);
    }

    if (uploadedItems.isEmpty && isScanning) {
      return _buildScanningState(scanned, total);
    }

    final grouped = _groupByDate(uploadedItems);

    return RefreshIndicator(
      onRefresh: () async {
        // Re-trigger channel scan on pull-to-refresh.
        final scanNotifier = ref.read(channelScanStateProvider.notifier);
        await scanNotifier.scan(forceRescan: true);
      },
      child: _buildGrid(context, ref, uploadedItems, grouped),
    );
  }

  Map<String, List<MediaItem>> _groupByDate(List<MediaItem> items) {
    final grouped = <String, List<MediaItem>>{};
    for (final item in items) {
      final key = _dateKey(item.createdAt);
      grouped.putIfAbsent(key, () => []).add(item);
    }
    return grouped;
  }

  String _dateKey(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(date.year, date.month, date.day);

    if (itemDate == today) return 'Today';
    if (itemDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }
    return '${date.month}/${date.day}/${date.year}';
  }

  Widget _buildGrid(
    BuildContext context,
    WidgetRef ref,
    List<MediaItem> allItems,
    Map<String, List<MediaItem>> groupedItems,
  ) {
    final dateKeys = groupedItems.keys.toList();

    // Reload generation: bumps when a channel scan completes/progresses, a
    // new upload lands, or the thumbnail cache is cleared — tiles that
    // previously timed out re-run their loaders instead of staying on the
    // placeholder for the whole session. Derived from *values* only, so
    // high-frequency progress updates (byte-level upload stats) don't churn
    // every tile's reload.
    final scanState = ref.watch(channelScanStateProvider);
    final backupStats = ref.watch(backupStatsProvider);
    final thumbnailGeneration = ref.watch(thumbnailGenerationProvider);
    final reloadGeneration = Object.hash(
      scanState.status,
      scanState.scannedItems,
      backupStats.backedUpCount,
      thumbnailGeneration,
    );

    return CustomScrollView(
      slivers: [
        for (int i = 0; i < dateKeys.length; i++) ...[
          SliverToBoxAdapter(
            child: DateHeader(
              dateText: dateKeys[i],
              itemCount: groupedItems[dateKeys[i]]?.length,
            ),
          ),
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final items = groupedItems[dateKeys[i]]!;
              final item = items[index];

              return MediaTile(
                mediaItem: item,
                showStatus: true,
                reloadGeneration: reloadGeneration,
                onTap: () => _onItemTap(context, ref, item, allItems),
              );
            }, childCount: groupedItems[dateKeys[i]]?.length ?? 0),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  void _onItemTap(
    BuildContext context,
    WidgetRef ref,
    MediaItem item,
    List<MediaItem> allItems,
  ) {
    if (item.isTelegram) {
      _showTelegramItemDetail(context, item);
      return;
    }

    // For local items, try to find the corresponding AssetEntity and open
    // the media viewer.
    final assetFuture = AssetEntity.fromId(item.localId);
    assetFuture.then((asset) {
      if (asset != null && context.mounted) {
        context.push(
          '/gallery/media/${asset.id}',
          extra: (assets: [asset], initialIndex: 0),
        );
      }
    });
  }

  void _showTelegramItemDetail(BuildContext context, MediaItem item) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.cloud_done,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Backed up to Telegram',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _detailRow(context, 'File name', item.fileName),
              _detailRow(context, 'Size', _formatFileSize(item.fileSize)),
              _detailRow(
                context,
                'Created',
                item.createdAt.toString().split('.').first,
              ),
              if (item.isVideo && item.durationMs != null)
                _detailRow(
                  context,
                  'Duration',
                  _formatDuration(item.durationMs),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDuration(int? durationMs) {
    if (durationMs == null) return '0:00';
    final seconds = (durationMs / 1000).floor();
    final minutes = (seconds / 60).floor();
    final remaining = seconds % 60;
    return '$minutes:${remaining.toString().padLeft(2, '0')}';
  }

  Widget _buildScanningState(int scanned, int total) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Scanning backup channel...',
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
          if (total > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$scanned / $total items',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_done_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'No backed up photos yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Photos and videos will appear here\n'
              'once they\'ve been backed up to Telegram.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/settings/backup'),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Go to Backup'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Re-export backupStatsProvider so the timeline can watch it for refresh.
/// This is already defined in backup_providers.dart; the import handles it.
