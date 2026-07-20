import 'package:flutter/foundation.dart';

import '../../features/settings/data/models/app_settings.dart';

/// Types of notifications the app can display.
enum NotificationType {
  backupProgress,
  backupCompleted,
  backupFailed,
  restoreCompleted,
  storageWarning,
}

/// Manages local notifications for backup/restore operations.
///
/// Uses Android notification channels for categorization.
/// Respects user notification preferences from [AppSettings].
class NotificationService {
  NotificationService();

  bool _initialized = false;

  /// Initialize notification channels (Android).
  Future<void> initialize() async {
    if (_initialized) return;

    // In production, create notification channels:
    // - "backup_progress" (low priority, ongoing)
    // - "backup_completed" (default priority)
    // - "backup_failed" (high priority)
    // - "restore_completed" (default priority)
    // - "storage_warning" (high priority)
    _initialized = true;
    debugPrint('[NotificationService] Initialized');
  }

  /// Show a backup progress notification.
  Future<void> showBackupProgress({
    required int current,
    required int total,
    required String fileName,
  }) async {
    if (!_initialized) return;
    final progress = total > 0 ? (current / total * 100).round() : 0;

    debugPrint(
      '[NotificationService] Backup progress: $progress% ($current/$total) - $fileName',
    );

    // In production:
    // - Update ongoing notification with progress bar
    // - Show current file name
    // - Use notification ID 1001 (same as foreground service)
  }

  /// Show a backup completed notification.
  Future<void> showBackupCompleted({
    required int totalFiles,
    required int totalBytes,
  }) async {
    if (!_initialized) return;

    final sizeMB = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
    debugPrint(
      '[NotificationService] Backup completed: $totalFiles files, ${sizeMB}MB',
    );

    // In production:
    // - Show summary notification
    // - Include file count and total size
    // - Auto-dismiss after 5 seconds
  }

  /// Show a backup failed notification.
  Future<void> showBackupFailed({
    required String reason,
    required int failedCount,
  }) async {
    if (!_initialized) return;

    debugPrint(
      '[NotificationService] Backup failed: $reason ($failedCount files)',
    );

    // In production:
    // - Show high-priority notification
    // - Include retry action
    // - Show failure reason
  }

  /// Show a restore completed notification.
  Future<void> showRestoreCompleted({required int totalFiles}) async {
    if (!_initialized) return;

    debugPrint('[NotificationService] Restore completed: $totalFiles files');

    // In production:
    // - Show summary notification
    // - Include file count
  }

  /// Show a storage warning notification.
  Future<void> showStorageWarning({required String reason}) async {
    if (!_initialized) return;

    debugPrint('[NotificationService] Storage warning: $reason');

    // In production:
    // - Show high-priority notification
    // - Include action to manage storage
  }

  /// Cancel all notifications.
  Future<void> cancelAll() async {
    if (!_initialized) return;
    debugPrint('[NotificationService] Cancelled all notifications');
  }

  /// Cancel a specific notification by ID.
  Future<void> cancel(int id) async {
    if (!_initialized) return;
    debugPrint('[NotificationService] Cancelled notification $id');
  }

  /// Check if a notification type is enabled in settings.
  bool isTypeEnabled(AppSettings settings, NotificationType type) {
    return switch (type) {
      NotificationType.backupProgress => settings.backupProgressNotification,
      NotificationType.backupCompleted => settings.backupCompletedNotification,
      NotificationType.backupFailed => settings.backupFailedNotification,
      NotificationType.restoreCompleted =>
        settings.restoreCompletedNotification,
      NotificationType.storageWarning => settings.storageWarningNotification,
    };
  }
}
