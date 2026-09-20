/// TDLib-specific exception with error code and user-facing message.
class TdLibException implements Exception {
  const TdLibException({
    required this.message,
    required this.code,
    this.userFacingMessage,
  });

  /// Technical error message for logging.
  final String message;

  /// TDLib error code (e.g., 'PHONE_INVALID', 'CODE_INVALID').
  final String code;

  /// User-facing error message (PRD Section 14.3 format).
  /// Falls back to [message] if not provided.
  String get displayMessage => userFacingMessage ?? message;

  /// User-facing message field.
  final String? userFacingMessage;

  @override
  String toString() => 'TdLibException($code): $message';
}

/// Maps TDLib error codes to user-facing messages per PRD Section 14.3.
class TdLibErrorMapper {
  const TdLibErrorMapper._();

  /// Map a TDLib error code to a user-facing message.
  ///
  /// TDLib's semantic error identifier (e.g. "PHONE_NUMBER_INVALID") lives
  /// in the response's `message` field, not its `code` field (which is
  /// just an HTTP-style status like 400/401/429). Some identifiers also
  /// carry a dynamic suffix — flood waits arrive as e.g.
  /// "FLOOD_WAIT_30" — so this matches by prefix rather than equality.
  static String mapErrorToUserMessage(String code, {String? detail}) {
    if (code.startsWith('FLOOD_WAIT')) {
      final match = RegExp(r'FLOOD_WAIT_(\d+)').firstMatch(code);
      final waitSeconds = match?.group(1);
      final wait = waitSeconds != null
          ? '$waitSeconds seconds'
          : (detail ?? 'a few minutes');
      return 'Too many attempts. Please wait $wait before trying again.';
    }

    return switch (code) {
      'PHONE_INVALID' || 'PHONE_NUMBER_INVALID' =>
        'Invalid phone number. Please check and try again.',
      'PHONE_CODE_INVALID' ||
      'CODE_INVALID' => 'Invalid verification code. Please try again.',
      'PHONE_CODE_EXPIRED' =>
        'Verification code expired. Please request a new one.',
      'PASSWORD_HASH_INVALID' ||
      'PASSWORD_INVALID' => 'Incorrect password. Please try again.',
      'PASSWORD_TOO_SHORT' ||
      'PASSWORD_TOO_LONG' => 'Password does not meet Telegram requirements.',
      'NETWORK_ERROR' ||
      'TIMEOUT' => 'Network error. Check your connection and try again.',
      'AUTH_KEY_UNREGISTERED' ||
      'AUTH_KEY_INVALID' => 'Session expired. Please log in again.',
      'USER_DEACTIVATED' || 'USER_DEACTIVATED_BAN' =>
        'This account has been deactivated. Please contact Telegram support.',
      'CHANNEL_PRIVATE' || 'CHAT_ADMIN_REQUIRED' =>
        'Storage channel not accessible. Please contact support.',
      'STORAGE_FULL' || 'FILE_TOO_BIG' =>
        'Telegram storage is full. Upgrade to Telegram Premium or free '
            'up space.',
      'FILE_NOT_FOUND' => 'File no longer available. Skipping.',
      'API_ID_INVALID' =>
        'App is not configured with valid Telegram API credentials.',
      _ => 'Something went wrong. Please try again.',
    };
  }

  /// Create a [TdLibException] from a TDLib error response.
  ///
  /// `error['message']` (e.g. "PHONE_NUMBER_INVALID") carries TDLib's
  /// semantic error identifier and is used as [TdLibException.code] for
  /// exact/prefix matching elsewhere. `error['code']` is only TDLib's
  /// numeric HTTP-style status and is not useful for that purpose.
  static TdLibException fromResponse(Map<String, dynamic> error) {
    final numericStatus = error['code']?.toString() ?? 'UNKNOWN_ERROR';
    final message = error['message']?.toString() ?? 'Unknown error';
    final semanticCode = message.isNotEmpty ? message : numericStatus;

    return TdLibException(
      message: message,
      code: semanticCode,
      userFacingMessage: mapErrorToUserMessage(semanticCode, detail: message),
    );
  }
}
