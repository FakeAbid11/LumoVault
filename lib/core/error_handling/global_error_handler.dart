import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'error_boundary.dart';
import 'crash_reporter.dart';

/// Sets up global error handling for the app.
///
/// Catches Flutter framework errors, Dart errors, and zone errors.
/// Delegates to [CrashReporter] for telemetry and shows the
/// [ErrorBoundary] widget for visual error display.
class GlobalErrorHandler {
  GlobalErrorHandler._();

  static bool _initialized = false;
  static CrashReporter? _reporter;

  /// Reset initialization state. Only for use in tests.
  @visibleForTesting
  static void reset() {
    _initialized = false;
    _reporter = null;
  }

  /// Initialize global error handling.
  ///
  /// Call once in `main()` before `runApp()`.
  static void initialize({CrashReporter? reporter}) {
    if (_initialized) return;
    _initialized = true;
    _reporter = reporter;

    // Catch Flutter framework errors.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _reporter?.recordError(
        details.exception,
        details.stack,
        reason: 'FlutterError.onError',
        fatal: false,
      );
    };

    // Catch async errors not caught by try/catch. Record them, then return
    // false so the error is rethrown and the process terminates — the
    // OS-level crash handler (e.g. the Sentry native integration) gets a
    // chance to capture it too, instead of the error being silently swallowed.
    PlatformDispatcher.instance.onError = (error, stack) {
      _reporter?.recordError(
        error,
        stack,
        reason: 'PlatformDispatcher.onError',
        fatal: true,
      );
      return false;
    };
  }

  /// Run [app] inside an error-catching zone.
  static void runAppWithZone(Widget app) {
    runZonedGuarded<Future<void>>(
      () async {
        initialize();
        runApp(app);
      },
      (error, stackTrace) {
        _reporter?.recordError(
          error,
          stackTrace,
          reason: 'Uncaught async error',
          fatal: true,
        );
      },
    );
  }
}
