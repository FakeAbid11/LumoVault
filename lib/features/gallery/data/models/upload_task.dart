import 'transfer_error.dart';

enum UploadStatus { queued, uploading, paused, completed, failed }

class UploadTask {
  const UploadTask({
    required this.id,
    required this.mediaItemId,
    required this.localFilePath,
    required this.fileName,
    required this.fileSize,
    required this.fileHash,
    this.telegramFileId,
    this.telegramMessageId,
    this.status = UploadStatus.queued,
    this.progress = 0.0,
    this.error,
    this.retryCount = 0,
    required this.createdAt,
    this.mediaCreatedAt,
    this.mediaModifiedAt,
    this.startedAt,
    this.completedAt,
    this.failedAt,
    this.pausedAt,
    this.lastActivityAt,
    this.priority = 0,
  });
  final String id;
  final String mediaItemId;
  final String localFilePath;
  final String fileName;
  final int fileSize;
  final String fileHash;
  final String? telegramFileId;
  final String? telegramMessageId;
  final UploadStatus status;
  final double progress;
  final TransferError? error;
  final int retryCount;

  /// When this upload task was created — a queue-lifecycle timestamp.
  final DateTime createdAt;

  /// When the underlying media was captured, carried over from the source
  /// [MediaItem]. Distinct from [createdAt]: this is what the user thinks of
  /// as the photo's date, and it is what must be written into the backup
  /// caption so a restore reproduces the original timeline.
  final DateTime? mediaCreatedAt;

  /// When the underlying media file was last modified on the device.
  final DateTime? mediaModifiedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? failedAt;
  final DateTime? pausedAt;
  final DateTime? lastActivityAt;
  final int priority;

  bool get isTerminal =>
      status == UploadStatus.completed || status == UploadStatus.failed;

  /// Maximum upload attempts before a task is permanently failed.
  static const int maxAttempts = 3;

  bool get canRetry =>
      status == UploadStatus.failed && retryCount < maxAttempts;

  UploadTask copyWith({
    String? id,
    String? mediaItemId,
    String? localFilePath,
    String? fileName,
    int? fileSize,
    String? fileHash,
    String? telegramFileId,
    String? telegramMessageId,
    UploadStatus? status,
    double? progress,
    TransferError? Function()? clearError,
    TransferError? error,
    int? retryCount,
    DateTime? createdAt,
    DateTime? mediaCreatedAt,
    DateTime? mediaModifiedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? failedAt,
    DateTime? pausedAt,
    DateTime? lastActivityAt,
    int? priority,
  }) {
    return UploadTask(
      id: id ?? this.id,
      mediaItemId: mediaItemId ?? this.mediaItemId,
      localFilePath: localFilePath ?? this.localFilePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      fileHash: fileHash ?? this.fileHash,
      telegramFileId: telegramFileId ?? this.telegramFileId,
      telegramMessageId: telegramMessageId ?? this.telegramMessageId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: clearError != null ? null : (error ?? this.error),
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      mediaCreatedAt: mediaCreatedAt ?? this.mediaCreatedAt,
      mediaModifiedAt: mediaModifiedAt ?? this.mediaModifiedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      failedAt: failedAt ?? this.failedAt,
      pausedAt: pausedAt ?? this.pausedAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      priority: priority ?? this.priority,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UploadTask &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          mediaItemId == other.mediaItemId &&
          status == other.status;

  @override
  int get hashCode => id.hashCode ^ mediaItemId.hashCode ^ status.hashCode;
}
