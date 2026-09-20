import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Absolute paths — Android app storage, external storage, Windows.
final RegExp _absolutePathPattern = RegExp(
  r'(?:[A-Za-z]:\\|/(?:data|storage|sdcard|mnt|home|private|var)/)\S*',
);

/// Media file names, which in this app are real photo/video names from the
/// user's library.
final RegExp _mediaFileNamePattern = RegExp(
  r"""[\w .()#\-']+\.(?:jpe?g|png|heic|heif|webp|gif|bmp|dng|mp4|mov|m4v|3gp|mkv|avi)""",
  caseSensitive: false,
);

/// `telegram://<messageId>` pointers into the user's storage channel.
final RegExp _telegramPointerPattern = RegExp(r'telegram://\d+');

/// Numeric chat / channel / user ids embedded in error text.
final RegExp _chatIdPattern = RegExp(
  r'\b(?:chat|channel|user)[ _-]?id\b\s*[:=]\s*\d+',
  caseSensitive: false,
);

/// Channel TITLES leak through TDLib-derived messages, e.g.
/// `Could not set up Telegram storage: <what the channel is called>`. The
/// title is user-chosen and can be anything they'd never want shipped.
final RegExp _channelTitlePattern = RegExp(
  r'(storage|channel|chat)( not found)?\s*:\s*[^\n]+',
  caseSensitive: false,
);

/// Redacts values that would expose the contents of a private photo library.
///
/// A first pass, not a guarantee: it catches the shapes that are known to
/// appear in this app's error text (see the patterns above). Anything that
/// embeds PII in an unexpected form still gets through, so the DSN should be
/// treated as receiving potentially sensitive data.
@visibleForTesting
String scrubSentryPii(String input) {
  var out = input;
  out = out.replaceAll(_channelTitlePattern, r'$1$2: [redacted]');
  out = out.replaceAll(_absolutePathPattern, '[path]');
  out = out.replaceAll(_telegramPointerPattern, 'telegram://[id]');
  out = out.replaceAll(_chatIdPattern, '[chat-id]');
  out = out.replaceAll(_mediaFileNamePattern, '[media-file]');
  return out;
}

/// Recursively redacts string values in a context/extra map.
@visibleForTesting
Map<String, dynamic> scrubSentryMap(Map<String, dynamic> input) {
  return input.map((key, value) {
    if (value is String) {
      return MapEntry(key, scrubSentryPii(value));
    }
    if (value is Map<String, dynamic>) {
      return MapEntry(key, scrubSentryMap(value));
    }
    if (value is Map) {
      return MapEntry(key, scrubSentryMap(value.cast<String, dynamic>()));
    }
    return MapEntry(key, value);
  });
}

/// `beforeSend` hook: redacts PII from the parts of an event that can carry
/// library contents — the message, exception text, stack-frame file names,
/// breadcrumb text, and any context we attached.
@visibleForTesting
SentryEvent? scrubSentryEvent(SentryEvent event, Hint hint) {
  final message = event.message;
  if (message != null) {
    event = event.copyWith(
      message: message.copyWith(
        formatted: scrubSentryPii(message.formatted),
        template: message.template == null
            ? null
            : scrubSentryPii(message.template!),
      ),
    );
  }

  final exceptions = event.exceptions;
  if (exceptions != null && exceptions.isNotEmpty) {
    event = event.copyWith(
      exceptions: exceptions.map((exception) {
        final trace = exception.stackTrace;
        return exception.copyWith(
          value: exception.value == null
              ? null
              : scrubSentryPii(exception.value!),
          stackTrace: trace == null
              ? null
              : SentryStackTrace(
                  frames: trace.frames
                      .map(
                        (frame) => frame.copyWith(
                          fileName: frame.fileName == null
                              ? null
                              : scrubSentryPii(frame.fileName!),
                          absPath: frame.absPath == null
                              ? null
                              : scrubSentryPii(frame.absPath!),
                        ),
                      )
                      .toList(),
                ),
        );
      }).toList(),
    );
  }

  final breadcrumbs = event.breadcrumbs;
  if (breadcrumbs != null && breadcrumbs.isNotEmpty) {
    event = event.copyWith(
      breadcrumbs: breadcrumbs
          .map(
            (crumb) => crumb.message == null
                ? crumb
                : crumb.copyWith(message: scrubSentryPii(crumb.message!)),
          )
          .toList(),
    );
  }

  return event;
}

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
          // This app is a private photo vault. TDLib-derived errors carry
          // chat/channel titles, message ids, and real photo file names, and
          // the SDK would otherwise ship them off-device unfiltered.
          options.beforeSend = scrubSentryEvent;
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
            // Callers hand us free-form context; scrub it here rather than
            // relying on every call site to remember the DSN is a network
            // boundary. beforeSend cannot see scope contexts at this point.
            scope.setContexts('lumo_vault', scrubSentryMap(extra));
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
