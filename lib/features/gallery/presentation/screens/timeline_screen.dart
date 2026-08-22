import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/backup_providers.dart';
import '../../../../core/di/channel_scan_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/lumo_loading.dart';
import '../../data/models/media_item.dart';
import '../widgets/date_header.dart';
import '../widgets/media_tile.dart';

/// Timeline screen — shows backed-up photos/videos from both the local
/// device and the Telegram storage channel.
///
/// Local items (from device scan) and Telegram-only items (from channel scan)
/// are merged and grouped by date. Tapping a local item opens the media
/// viewer; tapping a Telegram-only item shows the detail info.
///
/// Uses lazy pagination: only the first [AppConstants.galleryPageSize]
/// items are rendered initially, with more loaded as the user scrolls down.
/// The full filtered list is still computed once per build (it lives in
/// memory), but the expensive widget construction is deferred.
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  /// How many items are currently visible (grows as user scrolls).
  int _visibleCount = AppConstants.galleryPageSize;

  @override
  void didUpdateWidget(TimelineScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset pagination when the widget rebuilds from scratch (e.g. tab switch).
    _visibleCount = AppConstants.galleryPageSize;
  }

  @override
  Widget build(BuildContext context) {
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
      body: _buildBody(
        context,
        uploadedItems,
        isScanning,
        scanned,
        total,
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<MediaItem> uploadedItems,
    bool isScanning,
    int scanned,
    int total,
  ) {
    if (uploadedItems.isEmpty && !isScanning) {
      return _buildEmptyState(context);
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
      child: _buildGrid(context, uploadedItems, grouped),
    );
  }

  Map<String, List<MediaItem>> _groupByDate(List<MediaItem> items) {
    final grouped = <String, List<MediaItem>>{};
    for (final item in items) {
      final key = formatDateKey(item.createdAt);
      grouped.putIfAbsent(key, () => []).add(item);
    }
    return grouped;
  }

  Widget _buildGrid(
    BuildContext context,
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
    final telegramFetcher = ref.watch(telegramThumbnailFetcherProvider);
    final reloadGeneration = Object.hash(
      scanState.status,
      scanState.scannedItems,
      backupStats.backedUpCount,
      thumbnailGeneration,
    );

    // Build a flat list of (DateHeader | MediaTile) entries so we can
    // paginate across date boundaries without rendering entire date groups.
    final entries = <_TimelineEntry>[];
    for (int i = 0; i < dateKeys.length; i++) {
      final key = dateKeys[i];
      final items = groupedItems[key]!;
      entries.add(_TimelineEntry.header(key, items.length));
      for (final item in items) {
        entries.add(_TimelineEntry.item(item));
      }
    }

    // Clamp visible count so it never exceeds the actual entry count.
    final visibleEntries = entries.take(_visibleCount).toList();
    final hasMore = _visibleCount < entries.length;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Load more when the user scrolls within [galleryLoadThreshold] items
        // of the bottom.
        if (notification is ScrollUpdateNotification &&
            notification.depth == 0) {
          final metrics = notification.metrics;
          if (metrics.pixels >
              metrics.maxScrollExtent -
                  AppConstants.galleryLoadThreshold * 50) {
            _loadMore();
          }
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = visibleEntries[index];
                if (entry.isHeader) {
                  return DateHeader(
                    dateText: entry.dateKey!,
                    itemCount: entry.itemCount,
                  );
                }
                return MediaTile(
                  mediaItem: entry.item!,
                  showStatus: true,
                  reloadGeneration: reloadGeneration,
                  telegramThumbnailFetcher: telegramFetcher.fetch,
                  onTap: () => _onItemTap(context, entry.item!, allItems),
                );
              },
              childCount: visibleEntries.length,
            ),
          ),
          if (hasMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  void _loadMore() {
    if (!mounted) return;
    setState(() {
      _visibleCount += AppConstants.galleryPageSize;
    });
  }

  void _onItemTap(
    BuildContext context,
    MediaItem item,
    List<MediaItem> allItems,
  ) {
    if (item.isTelegram) {
      // Telegram-only items have no local asset to open — show them in the
      // Telegram viewer, swiping through every Telegram item in the timeline.
      final telegramItems = allItems.where((i) => i.isTelegram).toList();
      final index = telegramItems.indexWhere((i) => i.localId == item.localId);
      context.push(
        '/gallery/telegram-media/${item.localId}',
        extra: (items: telegramItems, initialIndex: index < 0 ? 0 : index),
      );
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

  Widget _buildScanningState(int scanned, int total) {
    return LumoLoading(
      value: total > 0 ? (scanned / total).clamp(0.0, 1.0) : null,
      message: 'Scanning backup channel…',
      sub: total > 0 ? '$scanned / $total items' : null,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_done_outlined,
      title: 'No backed up photos yet',
      message:
          'Photos and videos will appear here\n'
          'once they\'ve been backed up to Telegram.',
      action: FilledButton.icon(
        onPressed: () => context.push('/settings/backup'),
        icon: const Icon(Icons.cloud_upload_outlined),
        label: const Text('Go to Backup'),
      ),
    );
  }
}

/// A single entry in the flattened timeline — either a date header or a
/// media item. This enables pagination across date boundaries.
class _TimelineEntry {
  const _TimelineEntry.header(this.dateKey, this.itemCount)
      : item = null,
        isHeader = true;

  const _TimelineEntry.item(this.item)
      : dateKey = null,
        itemCount = 0,
        isHeader = false;

  final String? dateKey;
  final int itemCount;
  final MediaItem? item;
  final bool isHeader;
}