/// Telegram-specific constants.
///
/// API credentials (`apiId`/`apiHash`) live in [TdLibConfig].
/// Channel name/description live in [TdLibConfig] as well — those are the
/// single source of truth (see [TdLibConfig.storageChannelName]).
/// This class only holds constants that have no home elsewhere.
abstract final class TelegramConstants {
  /// Caption prefix for metadata stored in Telegram message captions.
  static const String captionPrefix = '[LV:v1]';
}
