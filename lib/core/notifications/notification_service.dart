import 'package:flutter/foundation.dart';

import '../../features/settings/data/models/app_settings.dart';
import 'notification_backend.dart';

/// Types of notifications the app can display.
enum NotificationType {
  backupProgress,
  backupCompleted,
  backupFailed,
  restoreCompleted,
  storageWarning,
  faceScan,
}

/// Android notification channel definition for a [NotificationType].
@immutable
class NotificationChannelSpec {
  const NotificationChannelSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.priority,
    required this.notificationId,
  });

  final String id;
  final String name;
  final String description;
  final NotificationPriority priority;

  /// Stable id, so re-posting replaces the previous notification of this kind
  /// instead of stacking duplicates.
  final int notificationId;
}

/// Manages local notifications for backup/restore operations.
///
/// Uses Android notification channels for categorization.
/// Respects user notification preferences from [AppSettings].
class NotificationService {
  NotificationService({NotificationBackend? backend})
    : _backend = backend ?? PluginNotificationBackend();

  /// Progress notification id. Shared with the foreground service so the
  /// ongoing backup shows as one notification, not two.
  static const int backupProgressNotificationId = 1001;

  /// Face-scan progress notification id. Kept separate from the backup id so
  /// a running backup and a running face scan never replace each other.
  static const int faceScanNotificationId = 1006;

  static const Map<NotificationType, NotificationChannelSpec> channels =
      <NotificationType, NotificationChannelSpec>{
        NotificationType.backupProgress: NotificationChannelSpec(
          id: 'backup_progress',
          name: 'Backup progress',
          description: 'Ongoing progress of a running backup.',
          priority: NotificationPriority.low,
          notificationId: backupProgressNotificationId,
        ),
        NotificationType.backupCompleted: NotificationChannelSpec(
          id: 'backup_completed',
          name: 'Backup completed',
          description: 'Summary shown when a backup finishes.',
          priority: NotificationPriority.normal,
          notificationId: 1002,
        ),
        NotificationType.backupFailed: NotificationChannelSpec(
          id: 'backup_failed',
          name: 'Backup failed',
          description: 'Alerts when a backup could not complete.',
          priority: NotificationPriority.high,
          notificationId: 1003,
        ),
        NotificationType.restoreCompleted: NotificationChannelSpec(
          id: 'restore_completed',
          name: 'Restore completed',
          description: 'Summary shown when a restore finishes.',
          priority: NotificationPriority.normal,
          notificationId: 1004,
        ),
        NotificationType.storageWarning: NotificationChannelSpec(
          id: 'storage_warning',
          name: 'Storage warnings',
          description: 'Warnings about low device or cloud storage.',
          priority: NotificationPriority.high,
          notificationId: 1005,
        ),
        NotificationType.faceScan: NotificationChannelSpec(
          id: 'face_scan',
          name: 'People grouping',
          description: 'Progress and results of on-device face scanning.',
          priority: NotificationPriority.low,
          notificationId: faceScanNotificationId,
        ),
      };

  final NotificationBackend _backend;

  bool _initialized = false;
  AppSettings? _settings;

  /// Whether the platform plugin is ready.
  bool get isInitialized => _initialized;

  /// Initialize the plugin and create every notification channel.
  Future<void> initialize() async {
    if (_initialized) return;

    if (!await _backend.initialize()) {
      debugPrint('[NotificationService] Backend unavailable, staying inert');
      return;
    }

    for (final spec in channels.values) {
      await _backend.createChannel(
        id: spec.id,
        name: spec.name,
        description: spec.description,
        priority: spec.priority,
      );
    }

    _initialized = true;
    debugPrint('[NotificationService] Initialized ${channels.length} channels');
  }

  /// Ask the user to allow notifications (Android 13+).
  Future<bool> requestPermission() async {
    if (!_initialized) return false;
    return _backend.requestPermission();
  }

  /// Supply the current settings so each post can honour the user's toggles.
  // ignore: use_setters_to_change_properties
  void updateSettings(AppSettings settings) {
    _settings = settings;
  }

  /// Show (or update) the ongoing backup progress notification.
  Future<void> showBackupProgress({
    required int current,
    required int total,
    required String fileName,
  }) async {
    final spec = channels[NotificationType.backupProgress]!;
    if (!_canPost(NotificationType.backupProgress)) return;

    final percent = total > 0 ? (current / total * 100).round() : 0;

    await _backend.show(
      NotificationRequest(
        id: spec.notificationId,
        channelId: spec.id,
        channelName: spec.name,
        title: 'Backing up — $percent%',
        body: total > 0 ? '$current of $total · $fileName' : fileName,
        priority: spec.priority,
        ongoing: true,
        showProgress: true,
        progress: current,
        maxProgress: total,
        indeterminate: total <= 0,
      ),
    );
  }

  /// Show a backup completed notification.
  Future<void> showBackupCompleted({
    required int totalFiles,
    required int totalBytes,
  }) async {
    // The ongoing progress notification is stale the moment the run ends.
    await cancel(backupProgressNotificationId);

    final spec = channels[NotificationType.backupCompleted]!;
    if (!_canPost(NotificationType.backupCompleted)) return;

    await _backend.show(
      NotificationRequest(
        id: spec.notificationId,
        channelId: spec.id,
        channelName: spec.name,
        title: 'Backup complete',
        body:
            '$totalFiles ${totalFiles == 1 ? 'item' : 'items'} · '
            '${_formatBytes(totalBytes)}',
        priority: spec.priority,
      ),
    );
  }

  /// Show a backup failed notification.
  Future<void> showBackupFailed({
    required String reason,
    required int failedCount,
  }) async {
    await cancel(backupProgressNotificationId);

    final spec = channels[NotificationType.backupFailed]!;
    if (!_canPost(NotificationType.backupFailed)) return;

    await _backend.show(
      NotificationRequest(
        id: spec.notificationId,
        channelId: spec.id,
        channelName: spec.name,
        title: failedCount > 0
            ? 'Backup failed — $failedCount ${failedCount == 1 ? 'item' : 'items'}'
            : 'Backup failed',
        body: reason,
        priority: spec.priority,
      ),
    );
  }

  /// Show a restore completed notification.
  Future<void> showRestoreCompleted({required int totalFiles}) async {
    final spec = channels[NotificationType.restoreCompleted]!;
    if (!_canPost(NotificationType.restoreCompleted)) return;

    await _backend.show(
      NotificationRequest(
        id: spec.notificationId,
        channelId: spec.id,
        channelName: spec.name,
        title: 'Restore complete',
        body: '$totalFiles ${totalFiles == 1 ? 'item' : 'items'} restored',
        priority: spec.priority,
      ),
    );
  }

  /// Show a storage warning notification.
  Future<void> showStorageWarning({required String reason}) async {
    final spec = channels[NotificationType.storageWarning]!;
    if (!_canPost(NotificationType.storageWarning)) return;

    await _backend.show(
      NotificationRequest(
        id: spec.notificationId,
        channelId: spec.id,
        channelName: spec.name,
        title: 'Storage warning',
        body: reason,
        priority: spec.priority,
      ),
    );
  }

  /// Post (or update) an ongoing progress notification identified by its
  /// stable id, resolving the channel from [channels].
  ///
  /// Generic counterpart to [showBackupProgress] so [ForegroundServiceManager]
  /// can drive both the backup and the face-scan notification identities with
  /// the same facade.
  Future<void> showProgressNotification({
    required int notificationId,
    required String title,
    required String body,
    required int current,
    required int total,
  }) async {
    MapEntry<NotificationType, NotificationChannelSpec>? entry;
    for (final e in channels.entries) {
      if (e.value.notificationId == notificationId) {
        entry = e;
        break;
      }
    }
    if (entry == null) return;
    if (!_canPost(entry.key)) return;

    final spec = entry.value;
    await _backend.show(
      NotificationRequest(
        id: spec.notificationId,
        channelId: spec.id,
        channelName: spec.name,
        title: title,
        body: body,
        priority: spec.priority,
        ongoing: true,
        showProgress: true,
        progress: current,
        maxProgress: total,
        indeterminate: total <= 0,
      ),
    );
  }

  /// Show (or update) the ongoing face-scan progress notification.
  Future<void> showFaceScanProgress({
    required int current,
    required int total,
  }) async {
    final spec = channels[NotificationType.faceScan]!;
    if (!_canPost(NotificationType.faceScan)) return;

    final percent = total > 0 ? (current / total * 100).round() : 0;

    await _backend.show(
      NotificationRequest(
        id: spec.notificationId,
        channelId: spec.id,
        channelName: spec.name,
        title: total > 0 ? 'Scanning faces — $percent%' : 'Scanning faces',
        body: total > 0 ? '$current of $total photos' : 'Preparing…',
        priority: spec.priority,
        ongoing: true,
        showProgress: true,
        progress: current,
        maxProgress: total,
        indeterminate: total <= 0,
      ),
    );
  }

  /// Replace the ongoing face-scan notification with its summary.
  Future<void> showFaceScanCompleted({
    required int photosScanned,
    required int facesFound,
  }) async {
    // The ongoing progress notification is stale the moment the scan ends.
    await cancel(faceScanNotificationId);

    final spec = channels[NotificationType.faceScan]!;
    if (!_canPost(NotificationType.faceScan)) return;

    await _backend.show(
      NotificationRequest(
        id: spec.notificationId,
        channelId: spec.id,
        channelName: spec.name,
        title: 'People grouping finished',
        body: facesFound > 0
            ? '$facesFound new ${facesFound == 1 ? 'face' : 'faces'} in '
                  '$photosScanned ${photosScanned == 1 ? 'photo' : 'photos'}'
            : 'No new faces in $photosScanned '
                  '${photosScanned == 1 ? 'photo' : 'photos'}',
        priority: spec.priority,
      ),
    );
  }

  /// Cancel all notifications.
  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _backend.cancelAll();
  }

  /// Cancel a specific notification by ID.
  Future<void> cancel(int id) async {
    if (!_initialized) return;
    await _backend.cancel(id);
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
      NotificationType.faceScan => settings.faceScanNotification,
    };
  }

  /// A post is allowed only once the plugin is live and the user hasn't
  /// switched this category off. Without settings, nothing is suppressed.
  bool _canPost(NotificationType type) {
    if (!_initialized) return false;
    final settings = _settings;
    return settings == null || isTypeEnabled(settings, type);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
  }
}
