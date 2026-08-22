import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lumovault/features/faces/data/repositories/face_repository.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';

import 'package:lumovault/core/di/gallery_providers.dart';
import '../providers/face_providers.dart';

/// Detail screen showing all photos that contain faces from a specific group.
class FaceGroupDetailScreen extends ConsumerWidget {
  const FaceGroupDetailScreen({required this.groupId, super.key});

  final int groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facesAsync = ref.watch(groupFacesProvider(groupId));

    // Get group info from the list.
    final groupsAsync = ref.watch(faceGroupsProvider);
    final group = groupsAsync.whenOrNull(
      data: (groups) => groups.where((g) => g.id == groupId).firstOrNull,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(group?.displayName ?? 'Person'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Rename',
            onPressed: group != null
                ? () => _showRenameDialog(context, ref, group)
                : null,
          ),
        ],
      ),
      body: facesAsync.when(
        data: (faces) {
          if (faces.isEmpty) {
            return const Center(
              child: Text('No faces in this group'),
            );
          }

          // Collect unique media item IDs and show as a grid.
          final mediaIds = faces.map((f) => f.mediaItemId).toSet().toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Face count summary.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  '${faces.length} face${faces.length == 1 ? '' : 's'} '
                  'in ${mediaIds.length} photo${mediaIds.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),

              // Media grid.
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: mediaIds.length,
                  itemBuilder: (context, index) {
                    return _MediaThumbnail(mediaItemId: mediaIds[index]);
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    FaceGroup group,
  ) {
    final controller = TextEditingController(text: group.name ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename person'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter a name'),
          onSubmitted: (_) => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              final name = controller.text.trim();
              ref.read(faceRepositoryProvider).renameGroup(
                    groupId,
                    name.isEmpty ? null : name,
                  );
              ref.invalidate(faceGroupsProvider);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Loads a [MediaItem] by its localId and displays its thumbnail.
///
/// Uses the gallery repository's in-memory list to find the item and build
/// the correct asset path for thumbnail display.
class _MediaThumbnail extends ConsumerWidget {
  const _MediaThumbnail({required this.mediaItemId});

  final String mediaItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(mediaItemProvider(mediaItemId));

    return itemAsync.when(
      data: (item) {
        if (item == null) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image, size: 32),
          );
        }
        return _ThumbnailFromItem(item: item);
      },
      loading: () => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.error_outline, size: 32),
      ),
    );
  }
}

/// Displays a thumbnail for a [MediaItem], using its file path.
class _ThumbnailFromItem extends StatelessWidget {
  const _ThumbnailFromItem({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    // Use thumbnailPath if available, otherwise fall back to filePath.
    final imagePath = item.thumbnailPath ?? item.filePath;

    if (imagePath.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.photo, size: 32),
      );
    }

    return GestureDetector(
      onTap: () {
        // Navigate to the media viewer. We don't have the full asset list
        // here, so just open the single item in the timeline viewer.
        // This is a simplified path — a production build would pass the
        // full list for swipe navigation.
        context.push('/gallery/telegram-media/$mediaItemId',
            extra: (items: [item], initialIndex: 0));
      },
      child: Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.photo, size: 32),
        ),
      ),
    );
  }

  String get mediaItemId => item.localId;
}
