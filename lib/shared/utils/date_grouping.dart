/// Shared date grouping utilities for photo grids.
///
/// Consolidates the identical `_groupByDate` and `_dateKey` logic that was
/// duplicated across [LocalScreen] and [TimelineScreen].
Map<String, List<T>> groupByDate<T>(
  List<T> items,
  DateTime Function(T) dateExtractor,
) {
  final grouped = <String, List<T>>{};
  for (final item in items) {
    final key = dateKey(dateExtractor(item));
    grouped.putIfAbsent(key, () => []).add(item);
  }
  return grouped;
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Returns a human-readable date label for grouping.
///
/// "Today", "Yesterday", or "1 May 2026".
String dateKey(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final itemDate = DateTime(date.year, date.month, date.day);

  if (itemDate == today) return 'Today';
  if (itemDate == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return '${date.day} ${_monthNames[date.month - 1]} ${date.year}';
}
