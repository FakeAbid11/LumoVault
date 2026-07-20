import '../data/models/backup_settings.dart';
import '../../gallery/data/models/media_item.dart';

/// Environment state for constraint evaluation.
///
/// Abstracts platform-specific checks (connectivity, battery, charging)
/// so the scheduler can be tested without real platform access.
class BackupEnvironment {
  const BackupEnvironment({
    this.isWifiConnected = false,
    this.isCharging = false,
    this.batteryLevel = 100,
    this.isAutoBackupEnabled = true,
  });
  final bool isWifiConnected;
  final bool isCharging;
  final int batteryLevel;
  final bool isAutoBackupEnabled;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupEnvironment &&
          isWifiConnected == other.isWifiConnected &&
          isCharging == other.isCharging &&
          batteryLevel == other.batteryLevel;

  @override
  int get hashCode =>
      isWifiConnected.hashCode ^ isCharging.hashCode ^ batteryLevel.hashCode;
}

/// Backup scheduler evaluating constraints before allowing uploads.
///
/// Per PRD Section 9.5, all conditions must be true to proceed:
/// 1. Is Wi-Fi available? (if wifiOnly setting)
/// 2. Is device charging? (if chargingOnly setting)
/// 3. Is battery level > 20%?
/// 4. Is file size < maxFileSize?
/// 5. Is folder in includedFolders?
/// 6. Is file not in excludedFileHashes?
/// 7. Is app not in battery-optimized mode?
class BackupScheduler {
  const BackupScheduler._();

  static const int _minBatteryLevel = 20;

  /// Evaluate whether backup should proceed given current settings and environment.
  static SchedulerResult evaluate({
    required BackupSettings settings,
    required BackupEnvironment environment,
  }) {
    final reasons = <String>[];

    if (!settings.isAutoBackupEnabled) {
      return const SchedulerResult(
        canProceed: false,
        reason: 'Auto backup is disabled.',
      );
    }

    if (!environment.isAutoBackupEnabled) {
      return const SchedulerResult(
        canProceed: false,
        reason: 'Auto backup toggle is off.',
      );
    }

    if (settings.wifiOnly && !environment.isWifiConnected) {
      reasons.add('Waiting for Wi-Fi connection.');
    }

    if (settings.chargingOnly && !environment.isCharging) {
      reasons.add('Waiting for device to be charging.');
    }

    if (environment.batteryLevel < _minBatteryLevel) {
      reasons.add('Battery too low (${environment.batteryLevel}%).');
    }

    if (reasons.isNotEmpty) {
      return SchedulerResult(canProceed: false, reason: reasons.join(' '));
    }

    return const SchedulerResult(canProceed: true);
  }

  /// Evaluate whether a specific media item should be included for backup.
  static IncludeResult evaluateMediaItem({
    required MediaItem item,
    required BackupSettings settings,
  }) {
    if (item.isExcluded) {
      return const IncludeResult(
        included: false,
        reason: 'File is excluded by user.',
      );
    }

    if (item.isTrashed) {
      return const IncludeResult(included: false, reason: 'File is in trash.');
    }

    if (item.status == MediaStatus.uploaded) {
      return const IncludeResult(
        included: false,
        reason: 'File is already uploaded.',
      );
    }

    if (item.status == MediaStatus.excluded) {
      return const IncludeResult(
        included: false,
        reason: 'File status is excluded.',
      );
    }

    if (!settings.isFileSizeAllowed(item.fileSize)) {
      return IncludeResult(
        included: false,
        reason: 'File exceeds max size (${item.fileSize} bytes).',
      );
    }

    if (item.mediaType == MediaType.video && !settings.backupVideos) {
      return const IncludeResult(
        included: false,
        reason: 'Video backup is turned off.',
      );
    }

    if (item.mediaType == MediaType.image && !settings.backupPhotos) {
      return const IncludeResult(
        included: false,
        reason: 'Photo backup is turned off.',
      );
    }

    if (item.deviceFolder != null &&
        settings.isFolderExcluded(item.deviceFolder!)) {
      return IncludeResult(
        included: false,
        reason: 'Folder "${item.deviceFolder}" is excluded.',
      );
    }

    if (item.deviceFolder != null &&
        !settings.isFolderIncluded(item.deviceFolder!)) {
      return IncludeResult(
        included: false,
        reason: 'Folder "${item.deviceFolder}" is not in included list.',
      );
    }

    if (settings.isFileExcluded(item.fileHash)) {
      return const IncludeResult(
        included: false,
        reason: 'File hash is in exclusion list.',
      );
    }

    return const IncludeResult(included: true);
  }

  /// Filter a list of media items to only those that should be backed up.
  static List<MediaItem> filterItemsForBackup({
    required List<MediaItem> items,
    required BackupSettings settings,
  }) {
    return items.where((item) {
      final result = evaluateMediaItem(item: item, settings: settings);
      return result.included;
    }).toList();
  }

  /// Calculate exponential backoff delay for retries.
  ///
  /// Per PRD: transient errors retry with exponential backoff.
  /// Formula: baseDelay * 2^(attemptCount - 1), capped at 5 minutes.
  static Duration calculateBackoff(int attemptCount) {
    const baseDelay = Duration(seconds: 5);
    final multiplier = 1 << (attemptCount - 1).clamp(0, 7);
    final delay = baseDelay * multiplier;
    const maxDelay = Duration(minutes: 5);
    return delay > maxDelay ? maxDelay : delay;
  }
}

/// Result of evaluating whether backup should proceed.
class SchedulerResult {
  const SchedulerResult({required this.canProceed, this.reason});
  final bool canProceed;
  final String? reason;
}

/// Result of evaluating whether a media item should be included.
class IncludeResult {
  const IncludeResult({required this.included, this.reason});
  final bool included;
  final String? reason;
}
