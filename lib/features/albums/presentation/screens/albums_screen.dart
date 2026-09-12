import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/album_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../features/albums/data/models/album.dart';
import '../../../gallery/data/models/device_folder.dart';
import '../../../gallery/data/services/device_folder_editor.dart';
import '../../../../shared/widgets/empty_state.dart';
import 'package:material_symbols_icons/symbols.dart';

class AlbumsScreen extends ConsumerStatefulWidget {
  const AlbumsScreen({super.key});

  @override
  ConsumerState<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends ConsumerState<AlbumsScreen> {
  @override
  Widget build(BuildContext context) {
    final albumsAsync = ref.watch(albumsListProvider);
    final countsAsync = ref.watch(albumCountsProvider);
    // Device folders straight from the device (photo_manager), so every
    // folder with media appears — not just the ones a backup scan covered.
    final deviceFoldersAsync = ref.watch(deviceFoldersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Albums'),
        actions: [
          IconButton(
            icon: const Icon(Symbols.add),
            tooltip: 'Create album',
            onPressed: () => _showCreateDialog(context),
          ),
        ],
      ),
      body: deviceFoldersAsync.when(
        data: (deviceFolders) => albumsAsync.when(
          data: (albums) => countsAsync.when(
            data: (counts) =>
                _buildBody(context, deviceFolders, albums, counts),
            loading: () => _buildBody(context, deviceFolders, albums, const {}),
            error: (_, __) =>
                _buildBody(context, deviceFolders, albums, const {}),
          ),
          loading: () => _buildBody(context, deviceFolders, const [], const {}),
          error: (_, __) =>
              _buildBody(context, deviceFolders, const [], const {}),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('$e')),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<DeviceFolder> deviceFolders,
    List<Album> albums,
    Map<int, int> counts,
  ) {
    if (deviceFolders.isEmpty && albums.isEmpty) {
      return _buildEmptyState(context);
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: deviceFolders.length + albums.length,
      itemBuilder: (context, index) {
        if (index < deviceFolders.length) {
          final folder = deviceFolders[index];
          return _AlbumCard(
            name: folder.name,
            itemCount: folder.totalItems,
            coverId: folder.coverId,
            isDeviceFolder: true,
            // Route by photo_manager path id (collision-free) with the
            // display name as a query param for the title.
            onTap: () => context.push(
              '/albums/folder/${folder.id}'
              '?name=${Uri.encodeComponent(folder.name)}',
            ),
            // Device folders mirror the phone's filesystem — per-folder
            // management is limited to trashing all its photos.
            onMore: () => _showDeviceFolderMenu(context, folder),
          );
        }
        final album = albums[index - deviceFolders.length];
        final count = counts[album.id] ?? 0;
        return _AlbumCard(
          name: album.name,
          itemCount: count,
          coverId: album.coverId,
          isDeviceFolder: false,
          onTap: () => context.push('/albums/${album.id}'),
          // Long-press kept for muscle memory; the ⋯ button makes
          // rename/delete discoverable.
          onLongPress: () => _showAlbumMenu(context, album),
          onMore: () => _showAlbumMenu(context, album),
        );
      },
    );
  }

  /// Device-folder management: "Delete folder" trashes every photo in it
  /// (double-confirmed); the folder then disappears on the next listing.
  Future<void> _showDeviceFolderMenu(
    BuildContext context,
    DeviceFolder folder,
  ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.folder),
              title: Text(folder.name),
              subtitle: Text('${folder.totalItems} items'),
            ),
            ListTile(
              leading: const Icon(Symbols.delete, color: Colors.red),
              title: const Text(
                'Delete folder',
                style: TextStyle(color: Colors.red),
              ),
              subtitle: const Text(
                'Moves ALL photos in this folder to the trash. '
                'Cannot be undone here.',
              ),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !context.mounted) return;
    // Strong second confirmation — this is a mass delete.
    final reallyDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete everything?'),
        content: Text(
          'All ${folder.totalItems} photos in "${folder.name}" will be moved '
          'to the trash. This can\'t be undone here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (reallyDelete != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Trashing ${folder.totalItems} photos from "${folder.name}"…',
        ),
        duration: const Duration(seconds: 3),
      ),
    );

    final assets = await ref.read(
      deviceFolderAssetsProvider(folder.id!).future,
    );
    final trashed = await ref
        .read(deviceFolderEditorProvider)
        .trashAssets(assets.whereType<AssetEntity>().toList());

    ref.invalidate(deviceFoldersProvider);
    ref.invalidate(deviceFolderAssetsProvider(folder.id!));
    ref.invalidate(deviceAssetsProvider);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Trashed ${trashed.length} of ${folder.totalItems} photos',
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return const EmptyState(
      icon: Symbols.photo_library,
      title: 'No albums yet',
      message: 'Create an album to organize\nyour photos and videos.',
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Album'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Album name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      await ref.read(albumActionsProvider).createAlbum(result);
    }
  }

  void _showAlbumMenu(BuildContext context, Album album) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.edit),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(context, album);
              },
            ),
            ListTile(
              leading: const Icon(Symbols.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, album);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, Album album) async {
    final controller = TextEditingController(text: album.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Album'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Album name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (result != null && mounted && album.id != null) {
      await ref.read(albumActionsProvider).renameAlbum(album.id!, result);
    }
  }

  Future<void> _confirmDelete(BuildContext context, Album album) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Album'),
        content: Text(
          'Delete "${album.name}"? Photos will not be deleted from your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted && album.id != null) {
      await ref.read(albumActionsProvider).deleteAlbum(album.id!);
    }
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.name,
    required this.itemCount,
    this.coverId,
    required this.isDeviceFolder,
    required this.onTap,
    this.onLongPress,
    this.onMore,
  });

  final String name;
  final int itemCount;
  final String? coverId;
  final bool isDeviceFolder;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Opens the management menu (rename/delete for custom albums, delete
  /// folder for device folders). Rendered as a ⋯ button on the cover when
  /// set — discoverable, unlike the long-press.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (coverId != null)
                    _CoverThumbnail(localId: coverId!)
                  else
                    Center(
                      child: Icon(
                        isDeviceFolder ? Symbols.folder : Symbols.photo_library,
                        size: 48,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  if (isDeviceFolder)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Symbols.folder,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  // Management menu — the discoverable way in (the
                  // long-press remains as a shortcut).
                  if (onMore != null)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Material(
                        color: colorScheme.surface.withValues(alpha: 0.85),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onMore,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Symbols.more_vert,
                              size: 18,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverThumbnail extends ConsumerWidget {
  const _CoverThumbnail({required this.localId});

  final String localId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetsAsync = ref.watch(deviceAssetsProvider);
    return assetsAsync.when(
      data: (assets) {
        final match = assets.where((a) => a.id == localId);
        if (match.isEmpty) return const SizedBox.shrink();
        return FutureBuilder<Uint8List?>(
          future: match.first.thumbnailDataWithSize(
            const ThumbnailSize(300, 300),
          ),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              return Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              );
            }
            return const Center(child: CircularProgressIndicator());
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
