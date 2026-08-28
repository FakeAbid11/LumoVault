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

/// Hidden album screen — shows media the user has hidden from the timeline.
///
/// Same rendering approach as the timeline: resolve each hidden item's
/// [MediaItem.localId] to a device [AssetEntity] so [AssetTile] renders the
/// real thumbnail, and tap through to the media viewer. Hidden items are
/// excluded from the timeline (see `MediaDao.timeline`), so this is the only
/// place they surface.
class HiddenAlbumScreen extends ConsumerWidget {
  const HiddenAlbumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hiddenItemsProvider);
    final deviceAssets = ref.watch(deviceAssetsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Hidden Album')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(hiddenItemsProvider);
          ref.invalidate(deviceAssetsProvider);
          await Future<void>.delayed(const Duration(milliseconds: 300));
        },
        child: hidden.when(
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

    // Resolve each hidden item to its AssetEntity for thumbnail rendering.
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
          onLongPress: () => _unhide(context, ref, item.localId),
        );
      },
    );
  }

  Future<void> _unhide(
    BuildContext context,
    WidgetRef ref,
    String localId,
  ) async {
    await ref.read(galleryRepositoryProvider).toggleHidden(localId);
    ref.invalidate(hiddenItemsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Removed from hidden album'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return const EmptyState(
      icon: Symbols.lock,
      title: 'Hidden album is empty',
      message: 'Items moved here will be hidden\nfrom the main timeline.',
    );
  }
}
