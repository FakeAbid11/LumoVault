import 'dart:async';

import 'package:flutter/foundation.dart';

/// Abstract crash reporter interface.
///
/// Implementations can send errors to Sentry, Firebase Crashlytics,
/// or any other crash reporting service. The default [NullCrashReporter]
/// simply logs to console in debug mode.
abstract class CrashReporter {
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

/// Sentry crash reporter stub.
///
/// To enable Sentry, add `sentry_flutter` to pubspec.yaml and
/// replace [NullCrashReporter] with [SentryCrashReporter] in main().
class SentryCrashReporter implements CrashReporter {
  SentryCrashReporter({required this._dsn});

  final String _dsn;
  final bool _initialized = false;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, dynamic>? extra,
  }) async {
    if (!_initialized) {
      debugPrint('[SentryCrashReporter] Not initialized — DSN: $_dsn');
      return;
    }

    // In production, use Sentry.captureException():
    // await Sentry.captureException(
    //   error,
    //   stackTrace: stack,
    //   hint: Hint.withMap({
    //     'reason': reason,
    //     'fatal': fatal,
    //     if (extra != null) ...extra,
    //   }),
    // );
    debugPrint('[SentryCrashReporter] Recorded: $error');
  }

  @override
  Future<void> log(String message, {Map<String, dynamic>? extra}) async {
    if (!_initialized) return;
    // Sentry.addBreadcrumb(Breadcrumb(message: message, data: extra));
    debugPrint('[SentryCrashReporter] Log: $message');
  }

  @override
  void setUser(String? userId) {
    // Sentry.configureScope((scope) {
    //   scope.setUser(userId != null ? User(id: userId) : null);
    // });
    debugPrint('[SentryCrashReporter] setUser: $userId');
  }

  @override
  Future<void> flush() async {
    // await Sentry.flush();
  }
}

/// Factory for creating the appropriate crash reporter.
class CrashReporterFactory {
  const CrashReporterFactory._();

  /// Create a crash reporter based on the environment.
  ///
  /// In debug mode, returns [NullCrashReporter].
  /// In release mode, returns [SentryCrashReporter] if [sentryDsn] is provided,
  /// otherwise returns [NullCrashReporter].
  static CrashReporter create({String? sentryDsn}) {
    if (kDebugMode) {
      return const NullCrashReporter();
    }

    if (sentryDsn != null && sentryDsn.isNotEmpty) {
      return SentryCrashReporter(dsn: sentryDsn);
    }

    return const NullCrashReporter();
  }
}
