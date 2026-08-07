import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/channel_scan_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../data/models/media_item.dart';
import '../widgets/media_tile.dart';

/// Album detail screen — media inside a device album.
///
/// Previously a permanent "Album empty" placeholder regardless of contents;
/// now backed by [albumItemsProvider], which reads the gallery repository's
/// album-filtered items.
class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({required this.albumId, super.key});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(albumItemsProvider(albumId));
    final telegramFetcher = ref.watch(telegramThumbnailFetcherProvider);

    return Scaffold(
      appBar: AppBar(title: Text(albumId)),
      body: itemsAsync.when(
        data: (items) => items.isEmpty
            ? _buildEmptyState(context)
            : _buildGrid(context, ref, items, telegramFetcher.fetch),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load album: $error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    WidgetRef ref,
    List<MediaItem> items,
    Future<Uint8List?> Function(MediaItem item) telegramFetch,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return MediaTile(
          mediaItem: item,
          reloadGeneration: ref.watch(thumbnailGenerationProvider),
          telegramThumbnailFetcher: telegramFetch,
          onTap: () => _onItemTap(context, item, items),
        );
      },
    );
  }

  void _onItemTap(BuildContext context, MediaItem item, List<MediaItem> all) {
    if (item.isTelegram) {
      final telegramItems = all.where((i) => i.isTelegram).toList();
      final index = telegramItems.indexWhere((i) => i.localId == item.localId);
      context.push(
        '/gallery/telegram-media/${item.localId}',
        extra: (items: telegramItems, initialIndex: index < 0 ? 0 : index),
      );
      return;
    }

    AssetEntity.fromId(item.localId).then((asset) {
      if (asset != null && context.mounted) {
        context.push(
          '/gallery/media/${asset.id}',
          extra: (assets: [asset], initialIndex: 0),
        );
      }
    });
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text('Album empty', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'This album has no media yet.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
