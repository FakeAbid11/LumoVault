import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Abstract crash reporter interface.
///
/// Implementations can send errors to Sentry, Firebase Crashlytics,
/// or any other crash reporting service. The default [NullCrashReporter]
/// simply logs to console in debug mode.
abstract class CrashReporter {
  /// Initialize the underlying reporting SDK (e.g. connect to Sentry).
  ///
  /// Idempotent and non-throwing — safe to call once at startup, and safe
  /// to skip entirely in unit tests.
  Future<void> initialize();

  /// Record a non-fatal error.
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, dynamic>? extra,
  });

  /// Record a custom event/message.
  Future<void> log(String message, {Map<String, dynamic>? extra});

  /// Set the user identifier (for crash grouping).
  void setUser(String? userId);

  /// Flush any pending reports.
  Future<void> flush();
}

/// No-op crash reporter for development and when no reporter is configured.
class NullCrashReporter implements CrashReporter {
  const NullCrashReporter();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, dynamic>? extra,
  }) async {
    if (kDebugMode) {
      debugPrint('[CrashReporter] ${fatal ? "FATAL" : "ERROR"}: $reason');
      debugPrint('$error');
      if (stack != null) {
        debugPrint('$stack');
      }
    }
  }

  @override
  Future<void> log(String message, {Map<String, dynamic>? extra}) async {
    if (kDebugMode) {
      debugPrint('[CrashReporter] LOG: $message');
    }
  }

  @override
  void setUser(String? userId) {
    if (kDebugMode) {
      debugPrint('[CrashReporter] setUser: $userId');
    }
  }

  @override
  Future<void> flush() async {}
}

/// Console-based crash reporter that logs in all modes (debug and release).
///
/// Used as a fallback when a real crash reporting service (e.g. Sentry)
/// is not yet integrated. Provides basic visibility into production crashes.
class ConsoleCrashReporter implements CrashReporter {
  const ConsoleCrashReporter();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, dynamic>? extra,
  }) async {
    debugPrint('[CrashReporter] ${fatal ? "FATAL" : "ERROR"}: $reason');
    debugPrint('$error');
    if (stack != null) {
      debugPrint('$stack');
    }
  }

  @override
  Future<void> log(String message, {Map<String, dynamic>? extra}) async {
    debugPrint('[CrashReporter] LOG: $message');
  }

  @override
  void setUser(String? userId) {
    debugPrint('[CrashReporter] setUser: $userId');
  }

  @override
  Future<void> flush() async {}
}

/// Sentry-backed crash reporter.
///
/// The Sentry SDK is initialized lazily on the first [initialize] or
/// [recordError] call, so constructing the reporter is cheap and safe in
/// tests. All SDK calls are guarded: a crash reporter must never throw —
/// telemetry failures are logged to the console and swallowed so they
/// cannot mask the app error being reported.
class SentryCrashReporter implements CrashReporter {
  SentryCrashReporter({required this.dsn});

  /// Sentry DSN, typically injected at build time via `--dart-define`.
  final String dsn;

  Future<void>? _initFuture;

  @override
  Future<void> initialize() => _ensureInitialized();

  Future<void> _ensureInitialized() {
    return _initFuture ??=
        SentryFlutter.init((options) {
          options.dsn = dsn;
          options.environment = kReleaseMode ? 'production' : 'development';
        }).catchError((Object error, StackTrace stackTrace) {
          debugPrint('[CrashReporter] Sentry initialization failed: $error');
        });
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, dynamic>? extra,
  }) async {
    await _ensureInitialized();
    try {
      await Sentry.captureException(
        error,
        stackTrace: stack,
        withScope: (scope) {
          scope.setTag('reason', reason ?? (fatal ? 'fatal' : 'error'));
          if (extra != null) {
            scope.setContexts('lumo_vault', extra);
          }
        },
      );
    } catch (e) {
      debugPrint('[CrashReporter] recordError failed: $e');
    }
  }

  @override
  Future<void> log(String message, {Map<String, dynamic>? extra}) async {
    await _ensureInitialized();
    try {
      await Sentry.captureMessage(message, level: SentryLevel.info);
    } catch (e) {
      debugPrint('[CrashReporter] log failed: $e');
    }
  }

  @override
  void setUser(String? userId) {
    if (userId == null) {
      Sentry.configureScope((scope) => scope.setUser(null));
    } else {
      Sentry.configureScope((scope) => scope.setUser(SentryUser(id: userId)));
    }
  }

  @override
  Future<void> flush() async {
    await _ensureInitialized();
    await Sentry.close();
  }
}

/// Factory for creating the appropriate crash reporter.
///
/// When a [sentryDsn] is provided, returns a [SentryCrashReporter] whose SDK
/// initializes on first use (or eagerly via [CrashReporter.initialize]).
/// Without a DSN, returns [NullCrashReporter] which only logs in debug mode.
class CrashReporterFactory {
  const CrashReporterFactory._();

  /// Create a crash reporter based on the environment.
  static CrashReporter create({String? sentryDsn}) {
    if (sentryDsn != null && sentryDsn.isNotEmpty) {
      return SentryCrashReporter(dsn: sentryDsn);
    }
    return const NullCrashReporter();
  }
}
