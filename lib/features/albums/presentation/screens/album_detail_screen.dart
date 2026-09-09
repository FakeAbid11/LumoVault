import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/album_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../gallery/presentation/widgets/asset_tile.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../../../shared/widgets/empty_state.dart';
import 'package:material_symbols_icons/symbols.dart';

class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({required this.albumId, super.key});

  final int albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumAsync = ref.watch(
      albumsListProvider.select(
        (async) => async.whenData(
          (albums) => albums.where((a) => a.id == albumId).firstOrNull,
        ),
      ),
    );
    final itemsAsync = ref.watch(albumItemsProvider(albumId));
    final deviceAssets = ref.watch(deviceAssetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: albumAsync.when(
          data: (album) => Text(album?.name ?? 'Album'),
          loading: () => const Text('Album'),
          error: (_, __) => const Text('Album'),
        ),
        actions: [
          if (itemsAsync.hasValue && itemsAsync.value!.isNotEmpty)
            IconButton(
              icon: const Icon(Symbols.select_all),
              tooltip: 'Select all',
              onPressed: () {},
            ),
        ],
      ),
      body: itemsAsync.when(
        data: (items) => deviceAssets.when(
          data: (assets) => _buildBody(context, ref, items, assets),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _buildBody(context, ref, items, const []),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('$e')),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<dynamic> items,
    List<AssetEntity> allAssets,
  ) {
    if (items.isEmpty) return _buildEmptyState();

    final byId = {for (final a in allAssets) a.id: a};
    final resolved = <dynamic>[];
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
        final asset = assets[index];
        return AssetTile(
          asset: asset,
          onTap: () => context.push(
            '/gallery/media/${asset.id}',
            extra: (assets: assets, initialIndex: index),
          ),
          onLongPress: () => _removeFromAlbum(context, ref, asset.id),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return const EmptyState(
      icon: Symbols.photo_library,
      title: 'Album is empty',
      message: 'Add photos from the viewer\nby tapping "Add to Album".',
    );
  }

  Future<void> _removeFromAlbum(
    BuildContext context,
    WidgetRef ref,
    String mediaId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from album?'),
        content: const Text('This will not delete the photo from your device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(albumActionsProvider).removeFromAlbum(albumId, mediaId);
    }
  }
}
