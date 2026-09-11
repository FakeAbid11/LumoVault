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
  const StickyDateHeaderDelegate({
    required this.dateText,
    this.itemCount,
    this.textScale = 1.0,
  });

  final String dateText;
  final int? itemCount;

  /// Font scale from [MediaQuery.textScalerOf] at the call site. The pinned
  /// extent must grow with it, or the title clips inside the header at
  /// accessibility text sizes.
  final double textScale;

  @override
  double get minExtent => 16 + 24 * textScale;

  @override
  double get maxExtent => 16 + 24 * textScale;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final scheme = Theme.of(context).colorScheme;
    // Opaque surface: grid thumbnails scroll behind the pinned header and
    // must not show through it. A subtle shadow once content actually slides
    // under it — without the cue the overlap reads as a glitch rather than
    // an intentional pinned layer.
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: overlapsContent
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: DateHeader(dateText: dateText, itemCount: itemCount),
    );
  }

  @override
  bool shouldRebuild(covariant StickyDateHeaderDelegate old) =>
      old.dateText != dateText || old.itemCount != itemCount;
}
