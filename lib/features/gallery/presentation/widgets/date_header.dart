import 'package:flutter/material.dart';

class DateHeader extends StatelessWidget {
  const DateHeader({super.key, required this.dateText, this.itemCount});
  final String dateText;
  final int? itemCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            dateText,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          if (itemCount != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$itemCount',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pinned [DateHeader] for [SliverPersistentHeader]: stays anchored at the
/// top of the viewport while its date section scrolls underneath, so the
/// section on screen is always labelled (Google Photos-style galleries).
class StickyDateHeaderDelegate extends SliverPersistentHeaderDelegate {
  const StickyDateHeaderDelegate({required this.dateText, this.itemCount});

  final String dateText;
  final int? itemCount;

  /// 8px top padding + 24px `titleMedium` line + 8px bottom padding.
  static const double _extent = 40;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Opaque surface: grid thumbnails scroll behind the pinned header and
    // must not show through it.
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: DateHeader(dateText: dateText, itemCount: itemCount),
    );
  }

  @override
  bool shouldRebuild(covariant StickyDateHeaderDelegate old) =>
      old.dateText != dateText || old.itemCount != itemCount;
}
