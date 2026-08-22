/// Format a byte count as a human-readable string.
///
/// Shared by the storage screens and diagnostics so every size display in
/// the app uses identical formatting: B, KB, MB, or GB with one decimal.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// Format a [DateTime] as a human-readable date key for grouping.
///
/// Returns 'Today', 'Yesterday', or 'M/D/YYYY'.
String formatDateKey(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final itemDate = DateTime(date.year, date.month, date.day);

  if (itemDate == today) return 'Today';
  if (itemDate == today.subtract(const Duration(days: 1))) {
    return 'Yesterday';
  }
  return '${date.month}/${date.day}/${date.year}';
}
