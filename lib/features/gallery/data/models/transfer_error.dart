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
    // Flood waits arrive as a semantic code with a per-wait suffix, e.g.
    // "FLOOD_WAIT_30" — see TdLibException.fromResponse, which explains that
    // the semantic identifier lives in the response's message field, not its
    // numeric HTTP-style code. An exact match on 'FLOOD_WAIT' never fired, so
    // every flood wait fell through to 'unknown' with retryable: false and the
    // task was permanently failed on its FIRST rate limit.
    final isFloodWait = code.startsWith('FLOOD_WAIT');

    final category = switch (code) {
      'NETWORK_ERROR' ||
      'TIMEOUT' ||
      'DNS_ERROR' => TransferErrorCategory.network,
      'FILE_TOO_BIG' => TransferErrorCategory.fileTooLarge,
      'STORAGE_FULL' => TransferErrorCategory.storageFull,
      'AUTH_KEY_UNREGISTERED' ||
      'AUTH_KEY_INVALID' => TransferErrorCategory.authExpired,
      'FILE_NOT_FOUND' => TransferErrorCategory.fileNotFound,
      'PERMISSION_DENIED' => TransferErrorCategory.permissionDenied,
      _ =>
        isFloodWait
            ? TransferErrorCategory.floodWait
            : TransferErrorCategory.unknown,
    };

    // TDLib reports flood waits as "Too Many Requests: retry after N" —
    // extract N so the retry path waits exactly as long as Telegram demands
    // instead of burning the retry budget on premature attempts. The wait
    // seconds also ride on the code itself ("FLOOD_WAIT_30"), matching
    // TdLibErrorMapper's extraction, so try that first and fall back to the
    // message.
    int? retryAfter;
    if (category == TransferErrorCategory.floodWait) {
      final codeMatch = RegExp(r'FLOOD_WAIT_(\d+)').firstMatch(code);
      final messageMatch = RegExp(
        r'retry after (\d+)',
      ).firstMatch(message.toLowerCase());
      retryAfter =
          (codeMatch != null ? int.tryParse(codeMatch.group(1)!) : null) ??
          (messageMatch != null ? int.tryParse(messageMatch.group(1)!) : null);
    }

    return TransferError(
      category: category,
      message: message,
      detail: code,
      retryable:
          category == TransferErrorCategory.network ||
          category == TransferErrorCategory.floodWait,
      retryAfterSeconds: retryAfter,
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
