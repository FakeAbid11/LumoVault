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

/// Format a duration in seconds as "M:SS".
String formatDurationSeconds(int seconds) {
  final minutes = (seconds / 60).floor();
  final remaining = seconds % 60;
  return '$minutes:${remaining.toString().padLeft(2, '0')}';
}

/// Format a duration in milliseconds as "M:SS".
String formatDurationMs(int? durationMs) {
  if (durationMs == null) return '0:00';
  final seconds = (durationMs / 1000).floor();
  return formatDurationSeconds(seconds);
}
