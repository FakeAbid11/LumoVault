import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lumovault/features/faces/data/repositories/face_repository.dart';

/// A card representing one face group (person) in the People grid.
///
/// Shows a circular thumbnail with the person's name and face count below.
class FaceGroupCard extends StatelessWidget {
  const FaceGroupCard({
    required this.group,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final FaceGroup group;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Circular face thumbnail.
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: colorScheme.primaryContainer,
                  backgroundImage:
                      group.thumbnailPath != null &&
                          File(group.thumbnailPath!).existsSync()
                      ? FileImage(File(group.thumbnailPath!))
                      : null,
                  child:
                      group.thumbnailPath == null ||
                          !File(group.thumbnailPath!).existsSync()
                      ? Icon(
                          Icons.person,
                          size: 48,
                          color: colorScheme.onPrimaryContainer,
                        )
                      : null,
                ),
              ),
              // Face count badge.
              if (group.itemCount > 1)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.surface, width: 2),
                    ),
                    child: Text(
                      '${group.itemCount}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Name or "Unknown".
          Text(
            group.displayName,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: group.isNamed ? FontWeight.w600 : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
