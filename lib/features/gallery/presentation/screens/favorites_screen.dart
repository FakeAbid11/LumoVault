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

/// Favorites screen — shows media the user has marked as favorite.
///
/// Resolves each favorite item's [MediaItem.localId] to a device
/// [AssetEntity] for thumbnail rendering. Long-press to unfavorite.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteItemsProvider);
    final deviceAssets = ref.watch(deviceAssetsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(favoriteItemsProvider);
          ref.invalidate(deviceAssetsProvider);
          await Future<void>.delayed(const Duration(milliseconds: 300));
        },
        child: favorites.when(
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
    if (items.isEmpty) return _buildEmptyState();

    final byId = {for (final a in allAssets) a.id: a};
    final resolved = <MediaItem>[];
    final assets = <AssetEntity>[];
    for (final item in items) {
      final asset = byId[item.localId];
      if (asset == null) continue;
      resolved.add(item);
      assets.add(asset);
    }

    if (resolved.isEmpty) return _buildEmptyState();

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
          isFavorite: true,
          onTap: () => context.push(
            '/gallery/media/${asset.id}',
            extra: (assets: assets, initialIndex: index),
          ),
          onLongPress: () => _unfavorite(context, ref, item.localId),
        );
      },
    );
  }

  Future<void> _unfavorite(
    BuildContext context,
    WidgetRef ref,
    String localId,
  ) async {
    await ref.read(galleryRepositoryProvider).toggleFavorite(localId);
    ref.invalidate(favoriteItemsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Removed from favorites'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const EmptyState(
      icon: Symbols.favorite,
      title: 'No favorites yet',
      message: 'Tap the heart icon on any photo\nto mark it as a favorite.',
    );
  }
}
