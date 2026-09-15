import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/gallery_providers.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../gallery/data/models/media_item.dart';
import '../../../gallery/presentation/widgets/asset_tile.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Archive screen — shows media the user has archived out of the timeline.
///
/// Mirrors the hidden album: resolve each archived item's [MediaItem.localId]
/// to a device [AssetEntity] so [AssetTile] renders the real thumbnail, tap
/// through to the media viewer, long-press to unarchive.
class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = ref.watch(archivedItemsProvider);
    final deviceAssets = ref.watch(deviceAssetsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Archive')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(archivedItemsProvider);
          ref.invalidate(deviceAssetsProvider);
          await Future<void>.delayed(const Duration(milliseconds: 300));
        },
        child: archived.when(
          data: (items) => deviceAssets.when(
            data: (assets) => _buildBody(context, ref, items, assets),
            loading: () => const Center(child: CircularProgressIndicator()),
            // An asset-list failure must not render as "Archive is empty" —
            // show the shared error state with a retry instead.
            error: (e, s) => items.isEmpty
                ? _buildEmptyState(context)
                : ErrorState(
                    error: e.toString(),
                    onRetry: () => ref.invalidate(deviceAssetsProvider),
                  ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => Center(child: Text('$e')),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<MediaItem> items,
    List<AssetEntity> allAssets,
  ) {
    if (items.isEmpty) return _buildEmptyState(context);

    final byId = {for (final a in allAssets) a.id: a};
    final resolved = <MediaItem>[];
    final assets = <AssetEntity>[];
    var unavailable = 0;
    for (final item in items) {
      final asset = byId[item.localId];
      // Counted, not silently dropped — the same condition already counts
      // and surfaces a banner on Favorites; an archive of deleted photos
      // used to look like an empty archive.
      if (asset == null) {
        unavailable++;
        continue;
      }
      resolved.add(item);
      assets.add(asset);
    }

    if (resolved.isEmpty) {
      return EmptyState(
        icon: Symbols.archive,
        title: 'Nothing left on this device',
        message:
            '$unavailable archived ${unavailable == 1 ? 'photo is' : 'photos are'} '
            'no longer on this device.',
      );
    }

    final grid = GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: galleryCrossAxisCount(
          ref.watch(settingsGridSizeProvider),
          ref.watch(settingsCompactModeProvider),
        ),
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: resolved.length,
      itemBuilder: (context, index) {
        final item = resolved[index];
        final asset = assets[index];
        return AssetTile(
          asset: asset,
          onTap: () => context.push(
            '/gallery/media/${asset.id}',
            extra: (assets: assets, initialIndex: index),
          ),
          onLongPress: () => _unarchive(context, ref, item.localId),
        );
      },
    );

    if (unavailable == 0) return grid;
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '$unavailable archived '
            '${unavailable == 1 ? 'photo is' : 'photos are'} not on this '
            'device.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: grid),
      ],
    );
  }

  Future<void> _unarchive(
    BuildContext context,
    WidgetRef ref,
    String localId,
  ) async {
    await ref.read(galleryRepositoryProvider).toggleArchived(localId);
    ref.invalidate(archivedItemsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Removed from archive'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return const EmptyState(
      icon: Symbols.archive,
      title: 'Archive is empty',
      message: 'Archived items are removed from\nthe main timeline.',
    );
  }
}
