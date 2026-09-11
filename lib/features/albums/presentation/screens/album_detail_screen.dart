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
import '../../../../shared/widgets/error_state.dart';
import 'package:material_symbols_icons/symbols.dart';

class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({this.albumId, this.albumName, super.key});

  final int? albumId;
  final String? albumName;

  bool get isDeviceFolder => albumName != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceAssets = ref.watch(deviceAssetsProvider);

    if (isDeviceFolder) {
      return _buildDeviceFolder(context, ref, deviceAssets);
    }
    return _buildCustomAlbum(context, ref, deviceAssets);
  }

  Widget _buildDeviceFolder(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<AssetEntity>> deviceAssets,
  ) {
    final itemsAsync = ref.watch(deviceFolderItemsProvider(albumName!));

    return Scaffold(
      appBar: AppBar(title: Text(albumName!)),
      body: itemsAsync.when(
        data: (items) => deviceAssets.when(
          data: (assets) =>
              _buildBody(context, ref, items, assets, allowRemove: false),
          loading: () => const Center(child: CircularProgressIndicator()),
          // An asset-list failure must not render as "Folder is empty".
          error: (_, __) => _buildAssetErrorBody(ref, items),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('$e')),
      ),
    );
  }

  Widget _buildCustomAlbum(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<AssetEntity>> deviceAssets,
  ) {
    final albumAsync = ref.watch(
      albumsListProvider.select(
        (async) => async.whenData(
          (albums) => albums.where((a) => a.id == albumId).firstOrNull,
        ),
      ),
    );
    final itemsAsync = ref.watch(albumItemsProvider(albumId!));

    return Scaffold(
      appBar: AppBar(
        title: albumAsync.when(
          data: (album) => Text(album?.name ?? 'Album'),
          loading: () => const Text('Album'),
          error: (_, __) => const Text('Album'),
        ),
      ),
      body: itemsAsync.when(
        data: (items) => deviceAssets.when(
          data: (assets) =>
              _buildBody(context, ref, items, assets, allowRemove: true),
          loading: () => const Center(child: CircularProgressIndicator()),
          // An asset-list failure must not render as "Album is empty".
          error: (_, __) => _buildAssetErrorBody(ref, items),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('$e')),
      ),
    );
  }

  /// When the device asset list fails to load but the album HAS items, show
  /// an honest error with a retry instead of the lying "empty" state.
  Widget _buildAssetErrorBody(WidgetRef ref, List<dynamic> items) {
    if (items.isEmpty) return _buildEmptyState();
    return ErrorState(
      error: 'Could not load the photos on this device.',
      onRetry: () => ref.invalidate(deviceAssetsProvider),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<dynamic> items,
    List<AssetEntity> allAssets, {
    bool allowRemove = true,
  }) {
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
          onLongPress: allowRemove
              ? () => _removeFromAlbum(context, ref, asset.id)
              : null,
        );
      },
    );
  }

  Widget _buildEmptyState() {
    if (isDeviceFolder) {
      return const EmptyState(
        icon: Symbols.folder,
        title: 'Folder is empty',
        message: 'No photos or videos found\nin this device folder.',
      );
    }
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
      await ref.read(albumActionsProvider).removeFromAlbum(albumId!, mediaId);
    }
  }
}
