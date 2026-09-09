import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/album_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../features/albums/data/models/album.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Albums')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context),
        child: const Icon(Symbols.add),
      ),
      body: albumsAsync.when(
        data: (albums) => countsAsync.when(
          data: (counts) => _buildBody(context, albums, counts),
          loading: () => _buildBody(context, albums, const {}),
          error: (_, __) => _buildBody(context, albums, const {}),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('$e')),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<Album> albums,
    Map<int, int> counts,
  ) {
    if (albums.isEmpty) return _buildEmptyState(context);

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final count = counts[album.id] ?? 0;
        return _AlbumCard(
          album: album,
          itemCount: count,
          onTap: () => context.push('/albums/${album.id}'),
          onLongPress: () => _showAlbumMenu(context, album),
        );
      },
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
    required this.album,
    required this.itemCount,
    required this.onTap,
    required this.onLongPress,
  });

  final Album album;
  final int itemCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

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
              child: album.coverId != null
                  ? _CoverThumbnail(localId: album.coverId!)
                  : Center(
                      child: Icon(
                        Symbols.photo_library,
                        size: 48,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            album.name,
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
