import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/gallery_providers.dart';
import '../../../../shared/widgets/empty_state.dart';
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
            error: (e, s) => _buildBody(context, ref, items, const []),
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
    for (final item in items) {
      final asset = byId[item.localId];
      if (asset == null) continue;
      resolved.add(item);
      assets.add(asset);
    }

    if (resolved.isEmpty) return _buildEmptyState(context);

    return GridView.builder(
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
