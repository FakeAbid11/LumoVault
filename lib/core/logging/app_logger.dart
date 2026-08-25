import 'package:flutter/foundation.dart';

/// Process-wide gate for LumoVault's verbose/operational logging.
///
/// The app emits its diagnostic logs through [debugPrint] with a `[Tag]`
/// prefix (e.g. `[BackupEngine] ...`, `[Settings] ...`). By default those
/// tagged logs are suppressed so a release build's logcat stays quiet; the
/// Developer > Debug Mode toggle flips [verboseEnabled] to let them through.
///
/// [install] wraps the current [debugPrint] sink exactly once. Untagged
/// output (framework messages, anything not starting with `[`) is always
/// forwarded, so this only ever hides LumoVault's own verbose logs — never
/// framework diagnostics.
class AppLogger {
  AppLogger._();

  /// When false (the default), tagged app logs are dropped. Kept in sync with
  /// [AppSettings.debugMode] by the settings layer, on both the UI isolate and
  /// the background backup isolate.
  static bool verboseEnabled = false;

  static DebugPrintCallback? _original;

  /// Install the gate over [debugPrint]. Idempotent — safe to call from both
  /// [main] and the background isolate entrypoint.
  static void install() {
    if (_original != null) return;
    final original = debugPrint;
    _original = original;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (!verboseEnabled && _isAppLog(message)) return;
      original(message, wrapWidth: wrapWidth);
    };
  }

  /// LumoVault logs follow the `[Tag] message` convention.
  static bool _isAppLog(String? message) =>
      message != null && message.startsWith('[');

  /// Restore the original [debugPrint] sink and clear the installed gate, so a
  /// subsequent [install] re-wraps freshly. Test-only.
  @visibleForTesting
  static void resetForTesting() {
    final original = _original;
    if (original != null) {
      debugPrint = original;
      _original = null;
    }
    verboseEnabled = false;
  }
}
