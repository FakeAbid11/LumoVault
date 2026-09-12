import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/album_providers.dart';
import '../../../gallery/data/services/device_folder_editor.dart';
import '../../../../core/di/channel_scan_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../gallery/data/models/device_folder.dart';
import '../../../gallery/data/models/media_item.dart';
import '../../../gallery/presentation/widgets/asset_tile.dart';
import '../../../gallery/presentation/widgets/media_tile.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import 'package:material_symbols_icons/symbols.dart';

class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({
    this.albumId,
    this.folderPathId,
    this.folderName,
    super.key,
  });

  final int? albumId;

  /// photo_manager path id when this screen shows a device folder.
  final String? folderPathId;

  /// Display name for a device folder (the path id is the stable key).
  final String? folderName;

  bool get isDeviceFolder => folderPathId != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceAssets = ref.watch(deviceAssetsProvider);

    if (isDeviceFolder) {
      return _buildDeviceFolder(context, ref);
    }
    return _buildCustomAlbum(context, ref, deviceAssets);
  }

  Widget _buildDeviceFolder(BuildContext context, WidgetRef ref) {
    // Device-backed listing: every folder on the phone opens here, even ones
    // no backup scan has ever covered.
    final assetsAsync = ref.watch(deviceFolderAssetsProvider(folderPathId!));

    return Scaffold(
      appBar: AppBar(
        title: Text(folderName?.isNotEmpty == true ? folderName! : 'Folder'),
      ),
      body: assetsAsync.when(
        data: (assets) => assets.isEmpty
            ? _buildEmptyState()
            : GridView.builder(
                padding: const EdgeInsets.all(2),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: galleryCrossAxisCount(
                    ref.watch(settingsGridSizeProvider),
                    ref.watch(settingsCompactModeProvider),
                  ),
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: assets.length,
                itemBuilder: (context, index) {
                  final asset = assets[index];
                  return AssetTile(
                    asset: asset,
                    // allowDeviceDelete: true in the viewer route — photos in
                    // device folders are fully manageable (trash/move/copy
                    // via the long-press menu).
                    onTap: () => context.push(
                      '/gallery/media/${asset.id}',
                      extra: (
                        assets: assets,
                        initialIndex: index,
                        allowDeviceDelete: true,
                      ),
                    ),
                    onLongPress: () =>
                        _showDeviceAssetActions(context, ref, asset),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => ErrorState(
          error: e.toString(),
          onRetry: () =>
              ref.invalidate(deviceFolderAssetsProvider(folderPathId!)),
        ),
      ),
    );
  }

  /// Per-photo management for device folders: trash, move to another folder,
  /// copy into this one. Operations run through [DeviceFolderEditor] and
  /// refresh the grid + counts via provider invalidation.
  Future<void> _showDeviceAssetActions(
    BuildContext context,
    WidgetRef ref,
    AssetEntity asset,
  ) async {
    final pathId = folderPathId!;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.delete),
              title: const Text('Move to trash'),
              onTap: () => Navigator.pop(context, 'trash'),
            ),
            ListTile(
              leading: const Icon(Symbols.drive_file_move),
              title: const Text('Move to folder…'),
              onTap: () => Navigator.pop(context, 'move'),
            ),
            ListTile(
              leading: const Icon(Symbols.content_copy),
              title: const Text('Copy into this folder…'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    final editor = ref.read(deviceFolderEditorProvider);
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case 'trash':
        final trashed = await editor.trashAssets([asset]);
        if (trashed.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Canceled — nothing deleted')),
          );
          return;
        }
        ref.invalidate(deviceFolderAssetsProvider(pathId));
        ref.invalidate(deviceAssetsProvider);
        messenger.showSnackBar(const SnackBar(content: Text('Moved to trash')));
      case 'move':
        final destination = await _pickDestinationFolder(context, ref, pathId);
        if (destination == null || !context.mounted) return;
        final moved = await editor.moveAssets([
          asset,
        ], targetPathId: destination.id!);
        ref.invalidate(deviceFolderAssetsProvider(pathId));
        ref.invalidate(deviceFolderAssetsProvider(destination.id!));
        ref.invalidate(deviceFoldersProvider);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              moved
                  ? 'Moved to ${destination.name}'
                  : 'Could not move — try again or use your gallery app',
            ),
          ),
        );
      case 'copy':
        final copy = await editor.copyAsset(asset, pathId);
        ref.invalidate(deviceFolderAssetsProvider(pathId));
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              copy == null ? 'Could not copy' : 'Copied into this folder',
            ),
          ),
        );
    }
  }

  /// Pick a destination device folder for a move/copy, excluding the current
  /// one. Returns null when canceled.
  Future<DeviceFolder?> _pickDestinationFolder(
    BuildContext context,
    WidgetRef ref,
    String currentPathId,
  ) async {
    final folders = await ref.read(deviceFoldersProvider.future);
    if (!context.mounted) return null;
    return showModalBottomSheet<DeviceFolder>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final folder in folders)
              if (folder.id != currentPathId)
                ListTile(
                  leading: const Icon(Symbols.folder),
                  title: Text(folder.name),
                  subtitle: Text('${folder.totalItems} items'),
                  onTap: () => Navigator.pop(context, folder),
                ),
          ],
        ),
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
    // Split into locally-resolvable members (AssetTile) and cloud-only
    // members (MediaTile + on-demand thumbnail) so nothing the user added
    // silently disappears from the grid.
    final resolved = <dynamic>[];
    final assets = <AssetEntity>[];
    final cloudOnly = <dynamic>[];
    for (final item in items) {
      final asset = byId[item.localId];
      if (asset == null) {
        cloudOnly.add(item);
        continue;
      }
      resolved.add(item);
      assets.add(asset);
    }

    if (resolved.isEmpty && cloudOnly.isEmpty) return _buildEmptyState();

    return Column(
      children: [
        if (allowRemove) ...[
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Long-press a photo to remove it from this album.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: galleryCrossAxisCount(
                ref.watch(settingsGridSizeProvider),
                ref.watch(settingsCompactModeProvider),
              ),
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: resolved.length + cloudOnly.length,
            itemBuilder: (context, index) {
              if (index >= resolved.length) {
                // Cloud-only member: no local asset, so render via MediaTile
                // (on-demand Telegram thumbnail) and open in the Telegram
                // viewer.
                final cloudIndex = index - resolved.length;
                final item = cloudOnly[cloudIndex] as MediaItem;
                return MediaTile(
                  mediaItem: item,
                  telegramThumbnailFetcher: ref
                      .watch(telegramThumbnailFetcherProvider)
                      .fetch,
                  onTap: () => context.push(
                    '/gallery/telegram-media/${item.localId}',
                    extra: (
                      items: cloudOnly.cast<MediaItem>().toList(),
                      initialIndex: cloudIndex,
                    ),
                  ),
                );
              }
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
          ),
        ),
      ],
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
