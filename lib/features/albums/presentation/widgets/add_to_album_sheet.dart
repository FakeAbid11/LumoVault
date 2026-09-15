import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/album_providers.dart';
import '../../../../features/albums/data/models/album.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Bottom sheet for managing a photo's custom-album membership.
///
/// Tapping an album toggles membership (in = add, out = remove). When the
/// photo already belongs to an album, each membership row also offers a
/// "move" action: tapping it switches the sheet into move mode, where the
/// next album tapped receives the photo (removed from the source).
class AddToAlbumSheet extends ConsumerStatefulWidget {
  const AddToAlbumSheet({required this.mediaId, super.key});

  final String mediaId;

  @override
  ConsumerState<AddToAlbumSheet> createState() => _AddToAlbumSheetState();
}

class _AddToAlbumSheetState extends ConsumerState<AddToAlbumSheet> {
  /// Set while a move is in progress: the album the photo will be removed
  /// from. Tap targets become move destinations instead of toggles.
  int? _moveSourceAlbumId;
  String? _moveSourceAlbumName;

  @override
  Widget build(BuildContext context) {
    final albumsAsync = ref.watch(albumsListProvider);
    final countsAsync = ref.watch(albumCountsProvider);
    final mediaAlbumsAsync = ref.watch(mediaAlbumsProvider(widget.mediaId));

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _moveSourceAlbumId == null
                            ? 'Albums'
                            : 'Move out of "$_moveSourceAlbumName" — tap a destination',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_moveSourceAlbumId != null)
                      IconButton(
                        icon: const Icon(Symbols.close),
                        tooltip: 'Cancel move',
                        onPressed: () => setState(() {
                          _moveSourceAlbumId = null;
                          _moveSourceAlbumName = null;
                        }),
                      )
                    else
                      IconButton(
                        icon: const Icon(Symbols.add),
                        tooltip: 'New album',
                        onPressed: () => _showCreateDialog(context),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tap an album to add or remove this photo.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: mediaAlbumsAsync.when(
                  data: (albumIds) => albumsAsync.when(
                    data: (albums) => countsAsync.when(
                      data: (counts) => _buildList(
                        context,
                        scrollController,
                        albums,
                        counts,
                        albumIds,
                      ),
                      loading: () => _buildList(
                        context,
                        scrollController,
                        albumsAsync.value ?? [],
                        const {},
                        albumIds,
                      ),
                      error: (_, __) => _buildList(
                        context,
                        scrollController,
                        albumsAsync.value ?? [],
                        const {},
                        albumIds,
                      ),
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, s) => Center(child: Text('$e')),
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, s) => Center(child: Text('$e')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(
    BuildContext context,
    ScrollController scrollController,
    List<Album> albums,
    Map<int, int> counts,
    List<int> currentAlbumIds,
  ) {
    if (albums.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.photo_library,
              size: 48,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text('No albums yet', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text(
              'Tap + to create one',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      // The DraggableScrollableSheet's controller: dragging the list can
      // close the sheet, and no per-rebuild controller leaks.
      controller: scrollController,
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final count = counts[album.id] ?? 0;
        final isAdded = currentAlbumIds.contains(album.id);
        final isMoveSource = album.id == _moveSourceAlbumId;

        if (_moveSourceAlbumId != null) {
          // Move mode: the source is disabled, every other album is a
          // destination.
          return ListTile(
            enabled: !isMoveSource,
            leading: Icon(
              isMoveSource ? Symbols.check_circle : Symbols.drive_file_move,
              color: isMoveSource
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            title: Text(
              album.name,
              style: isMoveSource
                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                  : null,
            ),
            subtitle: Text('$count ${count == 1 ? 'item' : 'items'}'),
            onTap: isMoveSource ? null : () => _moveTo(context, album),
          );
        }

        return ListTile(
          leading: Icon(
            isAdded ? Symbols.check_circle : Symbols.radio_button_unchecked,
            color: isAdded ? Theme.of(context).colorScheme.primary : null,
          ),
          title: Text(album.name),
          subtitle: Text('$count ${count == 1 ? 'item' : 'items'}'),
          onTap: () => _toggleAlbum(context, album, isAdded),
          // Membership rows get an explicit move affordance — the only
          // visible "move" verb in the app.
          trailing: isAdded
              ? IconButton(
                  icon: const Icon(Symbols.drive_file_move),
                  tooltip: 'Move out of this album',
                  onPressed: () => setState(() {
                    _moveSourceAlbumId = album.id;
                    _moveSourceAlbumName = album.name;
                  }),
                )
              : null,
        );
      },
    );
  }

  Future<void> _toggleAlbum(
    BuildContext context,
    Album album,
    bool isCurrentlyIn,
  ) async {
    if (album.id == null) return;
    final actions = ref.read(albumActionsProvider);

    if (isCurrentlyIn) {
      await actions.removeFromAlbum(album.id!, widget.mediaId);
    } else {
      await actions.addToAlbum(album.id!, widget.mediaId);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCurrentlyIn
                ? 'Removed from ${album.name}'
                : 'Added to ${album.name}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _moveTo(BuildContext context, Album destination) async {
    if (_moveSourceAlbumId == null || destination.id == null) return;
    final actions = ref.read(albumActionsProvider);
    await actions.moveMedia(
      fromAlbumId: _moveSourceAlbumId!,
      toAlbumId: destination.id!,
      mediaId: widget.mediaId,
    );
    final fromName = _moveSourceAlbumName ?? 'album';

    if (mounted) {
      setState(() {
        _moveSourceAlbumId = null;
        _moveSourceAlbumName = null;
      });
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Moved from $fromName to ${destination.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
      final id = await ref.read(albumActionsProvider).createAlbum(result);
      await ref.read(albumActionsProvider).addToAlbum(id, widget.mediaId);
    }
  }
}
