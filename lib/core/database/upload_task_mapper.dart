import 'package:drift/drift.dart';

import '../../features/gallery/data/models/transfer_error.dart';
import '../../features/gallery/data/models/upload_task.dart';
import 'app_database.dart';

/// Maps between the persisted [UploadTaskRow] (drift) and the [UploadTask]
/// domain model.
///
/// The domain model's [TransferError] is flattened into a set of `error*`
/// columns on write and reconstructed losslessly on read.
extension UploadTaskRowMapper on UploadTaskRow {
  UploadTask toDomain() => UploadTask(
    id: id,
    mediaItemId: mediaItemId,
    localFilePath: localFilePath,
    fileName: fileName,
    fileSize: fileSize,
    fileHash: fileHash,
    telegramFileId: telegramFileId,
    telegramMessageId: telegramMessageId,
    status: UploadStatus.values[status],
    progress: progress,
    error: _errorFromColumns(this),
    retryCount: retryCount,
    createdAt: createdAt,
    startedAt: startedAt,
    completedAt: completedAt,
    failedAt: failedAt,
    pausedAt: pausedAt,
    lastActivityAt: lastActivityAt,
    priority: priority,
  );
}

extension UploadTaskToCompanion on UploadTask {
  UploadTasksCompanion toCompanion() => UploadTasksCompanion(
    id: Value(id),
    mediaItemId: Value(mediaItemId),
    localFilePath: Value(localFilePath),
    fileName: Value(fileName),
    fileSize: Value(fileSize),
    fileHash: Value(fileHash),
    telegramFileId: Value(telegramFileId),
    telegramMessageId: Value(telegramMessageId),
    status: Value(status.index),
    progress: Value(progress),
    errorCategory: Value(error?.category.name),
    errorMessage: Value(error?.message),
    errorDetail: Value(error?.detail),
    errorRetryable: Value(error?.retryable ?? false),
    errorRetryAfterSeconds: Value(error?.retryAfterSeconds),
    errorOccurredAt: Value(error?.occurredAt),
    retryCount: Value(retryCount),
    createdAt: Value(createdAt),
    startedAt: Value(startedAt),
    completedAt: Value(completedAt),
    failedAt: Value(failedAt),
    pausedAt: Value(pausedAt),
    lastActivityAt: Value(lastActivityAt),
    priority: Value(priority),
  );
}

/// Rebuilds a [TransferError] from the flattened `error*` columns, or returns
/// null when no error was recorded.
TransferError? _errorFromColumns(UploadTaskRow row) {
  if (row.errorCategory == null &&
      row.errorMessage == null &&
      row.errorOccurredAt == null) {
    return null;
  }
  final category = TransferErrorCategory.values.firstWhere(
    (c) => c.name == row.errorCategory,
    orElse: () => TransferErrorCategory.unknown,
  );
  return TransferError(
    category: category,
    message: row.errorMessage ?? '',
    detail: row.errorDetail,
    retryable: row.errorRetryable,
    retryAfterSeconds: row.errorRetryAfterSeconds,
    occurredAt: row.errorOccurredAt ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}
