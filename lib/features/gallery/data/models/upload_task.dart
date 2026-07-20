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
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? failedAt;
  final DateTime? pausedAt;
  final DateTime? lastActivityAt;
  final int priority;

  bool get isTerminal =>
      status == UploadStatus.completed || status == UploadStatus.failed;

  bool get canRetry => status == UploadStatus.failed && retryCount < 3;

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
