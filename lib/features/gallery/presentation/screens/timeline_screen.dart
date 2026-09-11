import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/channel_scan_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../core/di/tdlib_providers.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../../../shared/utils/date_grouping.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/fast_scroll_scrubber.dart';
import '../../../../shared/widgets/lumo_loading.dart';
import '../../../../shared/widgets/pinch_zoom_wrapper.dart';
import '../../../../shared/widgets/settings_gear_button.dart';
import '../../data/models/media_item.dart';
import '../widgets/date_header.dart';
import '../widgets/media_tile.dart';
import 'package:material_symbols_icons/symbols.dart';

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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Metadata mutations (favorites, trash, upload completion, …) bump the
    // version counter — that's the signal to re-filter the item list. Do NOT
    // watch backupStatsProvider here: its ticks fire every 500 ms during an
    // upload and would rebuild the whole screen for no visible change.
    ref.watch(galleryDataVersionProvider);
    // Watch gallery changes (channel scan adds items here).
    final repository = ref.watch(galleryRepositoryProvider);

    // Watch channel scan progress for loading indicator.
    final (scanned, total, isScanning) = ref.watch(channelScanProgressProvider);

    final isAuthenticated = ref.watch(isAuthenticatedProvider);

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
        title: const Text('Cloud'),
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
          const SettingsGearButton(),
        ],
      ),
      body: _buildBody(
        context,
        uploadedItems,
        isScanning,
        scanned,
        total,
        isAuthenticated,
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<MediaItem> uploadedItems,
    bool isScanning,
    int scanned,
    int total,
    bool isAuthenticated,
  ) {
    if (!isAuthenticated) {
      return _buildNotConnectedState(context);
    }

    if (uploadedItems.isEmpty && !isScanning) {
      return _buildEmptyState(context);
    }

    if (uploadedItems.isEmpty && isScanning) {
      return _buildScanningState(scanned, total);
    }

    final grouped = groupByDate(uploadedItems, (item) => item.createdAt);

    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedback.mediumImpact();
        final scanNotifier = ref.read(channelScanStateProvider.notifier);
        await scanNotifier.scan(forceRescan: true);
      },
      child: _buildGrid(context, uploadedItems, grouped),
    );
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

    // Reload generation: bumps when a channel scan completes or the thumbnail
    // cache is cleared. Deliberately does NOT watch backupStatsProvider —
    // upload progress ticks are high-frequency and would rebuild every tile.
    final scanState = ref.watch(channelScanStateProvider);
    final thumbnailGeneration = ref.watch(thumbnailGenerationProvider);
    final telegramFetcher = ref.watch(telegramThumbnailFetcherProvider);
    final reloadGeneration = Object.hash(
      scanState.status,
      scanState.scannedItems,
      thumbnailGeneration,
    );

    return PinchZoomWrapper(
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
              SliverPersistentHeader(
                pinned: true,
                delegate: StickyDateHeaderDelegate(
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
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
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

    // For local items, find the corresponding AssetEntity and open the media
    // viewer. When the local file is gone (or the item only exists in the
    // channel), fall back to the Telegram viewer so the tap is never dead.
    final assetFuture = AssetEntity.fromId(item.localId);
    assetFuture.then((asset) {
      if (!context.mounted) return;
      if (asset != null) {
        context.push(
          '/gallery/media/${asset.id}',
          extra: (assets: [asset], initialIndex: 0),
        );
        return;
      }
      context.push(
        '/gallery/telegram-media/${item.localId}',
        extra: (items: [item], initialIndex: 0),
      );
    });
  }

  Widget _buildNotConnectedState(BuildContext context) {
    return EmptyState(
      icon: Icons.telegram,
      title: 'Not connected to Telegram',
      message:
          'Sign in to back up your photos\n'
          'to the cloud.',
      action: FilledButton.icon(
        onPressed: () => context.push('/connect-telegram'),
        icon: const Icon(Icons.telegram),
        label: const Text('Sign in to Telegram'),
      ),
    );
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
      icon: Symbols.cloud_done,
      title: 'No backed up photos yet',
      message:
          'Photos and videos will appear here\n'
          'once they\'ve been backed up to Telegram.',
      action: FilledButton.icon(
        onPressed: () => context.push('/settings/backup'),
        icon: const Icon(Symbols.cloud_upload),
        label: const Text('Go to Backup'),
      ),
    );
  }
}
