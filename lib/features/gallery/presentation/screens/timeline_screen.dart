import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/backup_providers.dart';
import '../../../../core/di/channel_scan_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/fast_scroll_scrubber.dart';
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
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  final ScrollController _scrollController = ScrollController();
  double _lastPinchScale = 1.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handlePinchScale(double scale) {
    if ((scale - _lastPinchScale).abs() < 0.25) return;
    _lastPinchScale = scale;

    final currentGrid = ref.read(settingsGridSizeProvider);
    if (scale > 1.25) {
      // Zoom in -> larger thumbnails, fewer columns
      if (currentGrid == GridSize.small) {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(gridSize: GridSize.medium));
        HapticFeedback.lightImpact();
      } else if (currentGrid == GridSize.medium) {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(gridSize: GridSize.large));
        HapticFeedback.lightImpact();
      }
    } else if (scale < 0.75) {
      // Zoom out -> smaller thumbnails, more columns
      if (currentGrid == GridSize.large) {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(gridSize: GridSize.medium));
        HapticFeedback.lightImpact();
      } else if (currentGrid == GridSize.medium) {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(gridSize: GridSize.small));
        HapticFeedback.lightImpact();
      }
    }
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
      body: _buildBody(context, uploadedItems, isScanning, scanned, total),
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
        HapticFeedback.mediumImpact();
        final scanNotifier = ref.read(channelScanStateProvider.notifier);
        await scanNotifier.scan(forceRescan: true);
      },
      child: _buildGrid(context, uploadedItems, grouped),
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
    List<MediaItem> allItems,
    Map<String, List<MediaItem>> groupedItems,
  ) {
    final dateKeys = groupedItems.keys.toList();
    final crossAxisCount = galleryCrossAxisCount(
      ref.watch(settingsGridSizeProvider),
      ref.watch(settingsCompactModeProvider),
    );

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

    return GestureDetector(
      onScaleUpdate: (details) {
        if (details.pointerCount >= 2) {
          _handlePinchScale(details.scale);
        }
      },
      child: FastScrollScrubber(
        scrollController: _scrollController,
        dateResolver: (progress) {
          if (dateKeys.isEmpty) return '';
          final index = (progress * (dateKeys.length - 1)).round().clamp(
            0,
            dateKeys.length - 1,
          );
          return dateKeys[index];
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            for (int i = 0; i < dateKeys.length; i++) ...[
              SliverToBoxAdapter(
                child: DateHeader(
                  dateText: dateKeys[i],
                  itemCount: groupedItems[dateKeys[i]]?.length,
                ),
              ),
              SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
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
                    telegramThumbnailFetcher: telegramFetcher.fetch,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _onItemTap(context, item, allItems);
                    },
                  );
                }, childCount: groupedItems[dateKeys[i]]?.length ?? 0),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
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
