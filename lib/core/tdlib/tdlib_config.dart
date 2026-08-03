/// TDLib configuration constants.
///
/// API credentials are registered on my.telegram.org under the LumoVault
/// developer account. They are the single source of truth for `apiId`/
/// `apiHash` and are injected at build time via `--dart-define` (see
/// `.env.example`) so nothing sensitive is committed to source control.
class TdLibConfig {
  const TdLibConfig._();

  /// Telegram API ID, injected at build time.
  ///
  /// Pass with `--dart-define=LUMOVAULT_TELEGRAM_API_ID=<id>`.
  /// Defaults to 0 (invalid) so a missing value fails fast rather than
  /// silently shipping a placeholder.
  static const int apiId = int.fromEnvironment(
    'LUMOVAULT_TELEGRAM_API_ID',
    defaultValue: 0,
  );

  /// Telegram API hash, injected at build time.
  ///
  /// Pass with `--dart-define=LUMOVAULT_TELEGRAM_API_HASH=<hash>`.
  static const String apiHash = String.fromEnvironment(
    'LUMOVAULT_TELEGRAM_API_HASH',
  );

  /// Whether the required Telegram credentials have been provided.
  static bool get hasCredentials => apiId != 0 && apiHash.isNotEmpty;

  /// Name of the private storage channel created by LumoVault.
  static const String storageChannelName = 'LumoVault Backup';

  /// Description for the storage channel.
  static const String storageChannelDescription =
      'LumoVault encrypted backup storage — managed by LumoVault app';

  /// Maximum file size for Telegram uploads (2GB).
  static const int maxFileSizeBytes = 2 * 1024 * 1024 * 1024;

  /// Database encryption key length in bytes.
  static const int databaseKeyLength = 32;
}
