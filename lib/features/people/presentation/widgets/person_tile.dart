import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/daos/face_dao.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../providers/people_providers.dart';

class PersonTile extends ConsumerWidget {
  const PersonTile({
    required this.personWithCount,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    super.key,
  });

  final PersonWithCount personWithCount;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = personWithCount.person;
    final photoCount = personWithCount.photoCount;
    final thumbnailAsync = ref.watch(personThumbnailProvider(person.id));

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        children: [
          // Circular face thumbnail
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                  child: ClipOval(
                    child: thumbnailAsync.when(
                      data: (path) => _buildThumbnail(context, path),
                      loading: () => const ShimmerPlaceholder(
                        width: double.infinity,
                        height: double.infinity,
                        borderRadius: 100,
                      ),
                      error: (_, __) => _buildPlaceholder(context),
                    ),
                  ),
                ),
                // Selection checkmark overlay
                if (selected)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.check,
                        size: 16,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Name
          Text(
            person.name ?? 'Person',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          // Photo count
          Text(
            '$photoCount ${photoCount == 1 ? 'photo' : 'photos'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context, String? thumbnailPath) {
    if (thumbnailPath == null || !File(thumbnailPath).existsSync()) {
      return _buildPlaceholder(context);
    }

    return Image.file(
      File(thumbnailPath),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Center(
        child: Icon(
          Icons.person,
          size: 40,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
