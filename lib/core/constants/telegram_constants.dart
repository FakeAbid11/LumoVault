/// Telegram-specific constants.
///
/// API credentials (`apiId`/`apiHash`) intentionally live only in
/// [TdLibConfig], which loads them at build time via `--dart-define`.
/// Do not add credential fields here — a single source of truth avoids
/// the conflicting/duplicate values this class previously held.
abstract final class TelegramConstants {
  /// Channel name for the private backup storage.
  static const String channelName = 'LumoVault Backup';

  /// Channel description (contains manifest placeholder).
  static const String channelDescription = 'LumoVault private backup storage';

  /// Caption prefix for metadata.
  static const String captionPrefix = '[LV:v1]';

  /// Maximum file size supported by TDLib (2GB).
  static const int maxFileSize = 2 * 1024 * 1024 * 1024;
}
