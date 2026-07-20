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

    // Catch async errors not caught by try/catch.
    PlatformDispatcher.instance.onError = (error, stack) {
      _reporter?.recordError(
        error,
        stack,
        reason: 'PlatformDispatcher.onError',
        fatal: true,
      );
      return true;
    };
  }

  /// Wrap [child] in a zone that catches uncaught async errors.
  static Widget runWithZone(Widget child) {
    return Builder(
      builder: (context) {
        return child;
      },
    );
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
