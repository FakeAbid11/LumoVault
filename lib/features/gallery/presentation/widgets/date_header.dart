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

/// Styled date header for [SliverPersistentHeader], used UNPINNED on the
/// Local and Cloud grids. It was pinned briefly (Google-Photos style), but
/// with sections of 1-3 items a pinned header spends most of its scroll
/// life covering the few tiles it labels — headers stacking over photos read
/// as a rendering bug, so headers now scroll with their section. The
/// textScale-aware extent is kept: it prevents title clipping at
/// accessibility font sizes either way.
class DateHeaderDelegate extends SliverPersistentHeaderDelegate {
  const DateHeaderDelegate({
    required this.dateText,
    this.itemCount,
    this.textScale = 1.0,
  });

  final String dateText;
  final int? itemCount;

  /// Font scale from [MediaQuery.textScalerOf] at the call site. The header
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
    // Opaque surface so thumbnails scrolling behind the (unpinned) header
    // during fast flings never show through it.
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: DateHeader(dateText: dateText, itemCount: itemCount),
    );
  }

  @override
  bool shouldRebuild(covariant DateHeaderDelegate old) =>
      old.dateText != dateText || old.itemCount != itemCount;
}
