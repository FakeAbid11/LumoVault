import '../../../gallery/data/models/transfer_error.dart';

/// Restore phase enumeration per PRD Section 10.
enum RestorePhase {
  /// Detecting whether a backup exists in the Telegram channel.
  detecting,

  /// Downloading the manifest from the pinned message.
  manifestDownload,

  /// Downloading partitioned metadata files referenced by the manifest.
  metadataDownload,

  /// Rebuilding the local database from downloaded metadata.
  databaseRebuild,

  /// Downloading thumbnails for fast gallery display.
  thumbnailDownload,

  /// Downloading full-resolution originals (background).
  originalDownload,

  /// Restore completed successfully.
  completed,

  /// Restore failed with an unrecoverable error.
  failed,

  /// Restore was cancelled by the user.
  cancelled,

  /// Restore is paused by the user.
  paused,
}

/// Overall restore state tracking per PRD Section 10.3.
class RestoreProgress {
  const RestoreProgress({
    this.phase = RestorePhase.detecting,
    this.overallProgress = 0.0,
    this.totalItems = 0,
    this.completedItems = 0,
    this.failedItems = 0,
    this.skippedItems = 0,
    this.currentFileName,
    this.currentPhaseDescription,
    this.totalBytes,
    this.downloadedBytes,
    this.startedAt,
    this.estimatedCompletion,
    this.error,
    this.isPaused = false,
    this.manifestInfo,
  });
  final RestorePhase phase;
  final double overallProgress;
  final int totalItems;
  final int completedItems;
  final int failedItems;
  final int skippedItems;
  final String? currentFileName;
  final String? currentPhaseDescription;
  final int? totalBytes;
  final int? downloadedBytes;
  final DateTime? startedAt;
  final DateTime? estimatedCompletion;
  final RestoreError? error;
  final bool isPaused;
  final ManifestInfo? manifestInfo;

  RestoreProgress copyWith({
    RestorePhase? phase,
    double? overallProgress,
    int? totalItems,
    int? completedItems,
    int? failedItems,
    int? skippedItems,
    String? currentFileName,
    String? currentPhaseDescription,
    int? totalBytes,
    int? downloadedBytes,
    DateTime? startedAt,
    DateTime? estimatedCompletion,
    RestoreError? error,
    bool? isPaused,
    ManifestInfo? manifestInfo,
    bool clearError = false,
    bool clearFileName = false,
    bool clearEstimatedCompletion = false,
  }) {
    return RestoreProgress(
      phase: phase ?? this.phase,
      overallProgress: overallProgress ?? this.overallProgress,
      totalItems: totalItems ?? this.totalItems,
      completedItems: completedItems ?? this.completedItems,
      failedItems: failedItems ?? this.failedItems,
      skippedItems: skippedItems ?? this.skippedItems,
      currentFileName: clearFileName
          ? null
          : (currentFileName ?? this.currentFileName),
      currentPhaseDescription:
          currentPhaseDescription ?? this.currentPhaseDescription,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      startedAt: startedAt ?? this.startedAt,
      estimatedCompletion: clearEstimatedCompletion
          ? null
          : (estimatedCompletion ?? this.estimatedCompletion),
      error: clearError ? null : (error ?? this.error),
      isPaused: isPaused ?? this.isPaused,
      manifestInfo: manifestInfo ?? this.manifestInfo,
    );
  }

  bool get isComplete => phase == RestorePhase.completed;
  bool get isFailed => phase == RestorePhase.failed;
  bool get isCancelled => phase == RestorePhase.cancelled;
  bool get isActive =>
      phase != RestorePhase.completed &&
      phase != RestorePhase.failed &&
      phase != RestorePhase.cancelled;

  double get progressPercent => (overallProgress * 100).clamp(0.0, 100.0);

  String get progressDisplay {
    if (totalItems == 0) return 'Starting...';
    return '$completedItems of $totalItems';
  }

  String get bytesDisplay {
    if (totalBytes == null || downloadedBytes == null) return '';
    final totalMB = (totalBytes! / (1024 * 1024)).toStringAsFixed(1);
    final downloadedMB = (downloadedBytes! / (1024 * 1024)).toStringAsFixed(1);
    return '$downloadedMB MB of $totalMB MB';
  }

  String get speedDisplay {
    if (estimatedCompletion == null || startedAt == null) return '';
    final elapsed = DateTime.now().difference(startedAt!);
    if (elapsed.inSeconds < 1) return '';
    final remaining = estimatedCompletion!.difference(DateTime.now());
    if (remaining.isNegative) return 'Almost done...';
    if (remaining.inMinutes < 1) return '${remaining.inSeconds}s remaining';
    if (remaining.inHours < 1) return '${remaining.inMinutes}m remaining';
    return '${remaining.inHours}h ${remaining.inMinutes % 60}m remaining';
  }

  String get phaseDescription {
    switch (phase) {
      case RestorePhase.detecting:
        return 'Checking for existing backup...';
      case RestorePhase.manifestDownload:
        return 'Reading your library structure...';
      case RestorePhase.metadataDownload:
        return 'Downloading metadata...';
      case RestorePhase.databaseRebuild:
        return 'Rebuilding your library...';
      case RestorePhase.thumbnailDownload:
        return 'Loading thumbnails...';
      case RestorePhase.originalDownload:
        return 'Downloading full-resolution files...';
      case RestorePhase.completed:
        return 'Restore complete!';
      case RestorePhase.failed:
        return error?.displayMessage ?? 'Restore failed';
      case RestorePhase.cancelled:
        return 'Restore cancelled';
      case RestorePhase.paused:
        return 'Restore paused';
    }
  }

  @override
  String toString() =>
      'RestoreProgress(phase: $phase, progress: $progressPercent%, '
      'items: $completedItems/$totalItems, failed: $failedItems, '
      'skipped: $skippedItems)';
}

/// Information about the manifest being restored.
class ManifestInfo {
  const ManifestInfo({
    required this.totalMedia,
    required this.totalSizeBytes,
    required this.created,
    required this.lastSync,
    required this.chunkCount,
    required this.deviceHash,
  });
  final int totalMedia;
  final int totalSizeBytes;
  final DateTime created;
  final DateTime lastSync;
  final int chunkCount;
  final String deviceHash;

  String get totalSizeDisplay {
    final gb = totalSizeBytes / (1024 * 1024 * 1024);
    if (gb >= 1.0) return '${gb.toStringAsFixed(1)} GB';
    final mb = totalSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  String get dateRangeDisplay {
    return 'Since ${created.month}/${created.day}/${created.year}';
  }

  @override
  String toString() =>
      'ManifestInfo(media: $totalMedia, size: $totalSizeDisplay, '
      'chunks: $chunkCount, device: $deviceHash)';
}

/// Typed error for restore failures per PRD Section 14.
class RestoreError {
  const RestoreError({
    required this.category,
    required this.message,
    this.detail,
    this.retryable = false,
    this.retryAfterSeconds,
    required this.occurredAt,
  });

  factory RestoreError.fromTransferError(TransferError error) {
    return RestoreError(
      category: _mapTransferCategory(error.category),
      message: error.displayMessage,
      detail: error.detail,
      retryable: error.retryable,
      retryAfterSeconds: error.retryAfterSeconds,
      occurredAt: error.occurredAt,
    );
  }

  factory RestoreError.network({
    required String message,
    String? detail,
    bool retryable = true,
  }) {
    return RestoreError(
      category: RestoreErrorCategory.network,
      message: message,
      detail: detail,
      retryable: retryable,
      occurredAt: DateTime.now(),
    );
  }

  factory RestoreError.channelNotFound() {
    return RestoreError(
      category: RestoreErrorCategory.channelNotFound,
      message: 'No backup found',
      detail:
          'No LumoVault backup was found in your Telegram account. '
          'Would you like to start fresh?',
      retryable: false,
      occurredAt: DateTime.now(),
    );
  }

  factory RestoreError.manifestCorrupted() {
    return RestoreError(
      category: RestoreErrorCategory.manifestCorrupted,
      message: 'Backup data is corrupted',
      detail:
          'The backup manifest could not be read. '
          'The data may have been modified or corrupted.',
      retryable: false,
      occurredAt: DateTime.now(),
    );
  }

  factory RestoreError.storageFull() {
    return RestoreError(
      category: RestoreErrorCategory.storageFull,
      message: 'Not enough storage space',
      detail: 'Free up space on your device and try again.',
      retryable: false,
      occurredAt: DateTime.now(),
    );
  }

  factory RestoreError.authExpired() {
    return RestoreError(
      category: RestoreErrorCategory.authExpired,
      message: 'Session expired',
      detail: 'Please log in again to continue the restore.',
      retryable: false,
      occurredAt: DateTime.now(),
    );
  }

  factory RestoreError.cancelled() {
    return RestoreError(
      category: RestoreErrorCategory.cancelled,
      message: 'Restore cancelled',
      retryable: false,
      occurredAt: DateTime.now(),
    );
  }
  final RestoreErrorCategory category;
  final String message;
  final String? detail;
  final bool retryable;
  final int? retryAfterSeconds;
  final DateTime occurredAt;

  String get displayMessage {
    switch (category) {
      case RestoreErrorCategory.network:
        return 'Waiting for internet connection...';
      case RestoreErrorCategory.channelNotFound:
        return 'No backup found';
      case RestoreErrorCategory.manifestCorrupted:
        return 'Backup data is corrupted';
      case RestoreErrorCategory.storageFull:
        return 'Not enough storage space';
      case RestoreErrorCategory.authExpired:
        return 'Session expired. Please log in again.';
      case RestoreErrorCategory.fileNotFound:
        return 'Some files could not be downloaded. Skipping.';
      case RestoreErrorCategory.permissionDenied:
        return 'Storage permission required. Grant in Settings.';
      case RestoreErrorCategory.cancelled:
        return 'Restore cancelled';
      case RestoreErrorCategory.unknown:
        return 'An unexpected error occurred';
    }
  }

  static RestoreErrorCategory _mapTransferCategory(
    TransferErrorCategory category,
  ) {
    switch (category) {
      case TransferErrorCategory.network:
        return RestoreErrorCategory.network;
      case TransferErrorCategory.fileNotFound:
        return RestoreErrorCategory.fileNotFound;
      case TransferErrorCategory.permissionDenied:
        return RestoreErrorCategory.permissionDenied;
      case TransferErrorCategory.storageFull:
        return RestoreErrorCategory.storageFull;
      case TransferErrorCategory.authExpired:
        return RestoreErrorCategory.authExpired;
      default:
        return RestoreErrorCategory.unknown;
    }
  }

  @override
  String toString() =>
      'RestoreError(category: $category, message: $message, retryable: $retryable)';
}

/// Error categories for restore operations per PRD Section 14.1.
enum RestoreErrorCategory {
  network,
  channelNotFound,
  manifestCorrupted,
  storageFull,
  authExpired,
  fileNotFound,
  permissionDenied,
  cancelled,
  unknown,
}
