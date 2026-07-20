enum TransferErrorCategory {
  network,
  fileTooLarge,
  floodWait,
  authExpired,
  storageFull,
  fileNotFound,
  permissionDenied,
  unknown,
}

class TransferError {
  const TransferError({
    required this.category,
    required this.message,
    this.detail,
    this.retryable = false,
    this.retryAfterSeconds,
    required this.occurredAt,
  });

  factory TransferError.fromTdLibError(String code, String message) {
    final category = switch (code) {
      'NETWORK_ERROR' ||
      'TIMEOUT' ||
      'DNS_ERROR' => TransferErrorCategory.network,
      'FILE_TOO_BIG' || 'STORAGE_FULL' => TransferErrorCategory.storageFull,
      'FLOOD_WAIT' => TransferErrorCategory.floodWait,
      'AUTH_KEY_UNREGISTERED' ||
      'AUTH_KEY_INVALID' => TransferErrorCategory.authExpired,
      'FILE_NOT_FOUND' => TransferErrorCategory.fileNotFound,
      'PERMISSION_DENIED' => TransferErrorCategory.permissionDenied,
      _ => TransferErrorCategory.unknown,
    };

    return TransferError(
      category: category,
      message: message,
      detail: code,
      retryable:
          category == TransferErrorCategory.network ||
          category == TransferErrorCategory.floodWait,
      occurredAt: DateTime.now(),
    );
  }
  final TransferErrorCategory category;
  final String message;
  final String? detail;
  final bool retryable;
  final int? retryAfterSeconds;
  final DateTime occurredAt;

  String get displayMessage {
    return switch (category) {
      TransferErrorCategory.network =>
        'Network error. Check your connection and try again.',
      TransferErrorCategory.fileTooLarge =>
        'File too large for Telegram (max 2GB). Consider compressing.',
      TransferErrorCategory.floodWait =>
        'Too many requests. Waiting ${retryAfterSeconds ?? 'a few minutes'}...',
      TransferErrorCategory.authExpired =>
        'Session expired. Please log in again.',
      TransferErrorCategory.storageFull =>
        'Telegram storage is full. Upgrade to Telegram Premium or free up space.',
      TransferErrorCategory.fileNotFound =>
        'File no longer available. Skipping.',
      TransferErrorCategory.permissionDenied =>
        'Storage permission required. Grant in Settings.',
      TransferErrorCategory.unknown => 'Upload failed. Tap to retry.',
    };
  }

  TransferError copyWith({
    TransferErrorCategory? category,
    String? message,
    String? detail,
    bool? retryable,
    int? retryAfterSeconds,
    DateTime? occurredAt,
  }) {
    return TransferError(
      category: category ?? this.category,
      message: message ?? this.message,
      detail: detail ?? this.detail,
      retryable: retryable ?? this.retryable,
      retryAfterSeconds: retryAfterSeconds ?? this.retryAfterSeconds,
      occurredAt: occurredAt ?? this.occurredAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransferError &&
          runtimeType == other.runtimeType &&
          category == other.category &&
          message == other.message;

  @override
  int get hashCode => category.hashCode ^ message.hashCode;
}
