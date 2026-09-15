import 'package:flutter/material.dart';

/// Shows a Material date range picker and returns the selected range.
///
/// Returns `null` if the user cancels, or a `(DateTime, DateTime)` pair
/// representing the selected start and end dates (inclusive — end date
/// is extended to end-of-day so a single-day range works).
Future<(DateTime, DateTime)?> showLumoDateRangePicker(
  BuildContext context, {
  DateTime? initialStart,
  DateTime? initialEnd,
}) async {
  final now = DateTime.now();
  final picked = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: DateTime(now.year + 1),
    initialDateRange: initialStart != null && initialEnd != null
        ? DateTimeRange(start: initialStart, end: initialEnd)
        : null,
    helpText: 'SELECT DATE RANGE',
    cancelText: 'Clear',
    confirmText: 'Apply',
  );
  if (picked == null) return null;
  // Extend end date to end-of-day so items captured on that day are included.
  final end = DateTime(
    picked.end.year,
    picked.end.month,
    picked.end.day,
    23,
    59,
    59,
    999,
  );
  return (picked.start, end);
}
