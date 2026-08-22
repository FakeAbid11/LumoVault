import 'package:lumovault/features/gallery/data/models/media_item.dart';

/// A group of photos/videos from a specific anniversary date.
///
/// For example, [yearsAgo] == 1 means "on this day 1 year ago" and [items]
/// contains every photo/video taken on that calendar date.
class MemoryGroup {
  const MemoryGroup({
    required this.yearsAgo,
    required this.items,
    required this.anniversaryDate,
  });

  /// How many years ago this memory is from.
  final int yearsAgo;

  /// Photos/videos taken on this anniversary date.
  final List<MediaItem> items;

  /// The exact calendar date this memory refers to.
  final DateTime anniversaryDate;

  /// Human-readable label such as "1 year ago" or "3 years ago".
  String get label => yearsAgo == 1 ? '1 year ago' : '$yearsAgo years ago';

  /// Whether this group has enough items for a multi-photo preview collage.
  bool get hasCollage => items.length >= 3;
}
