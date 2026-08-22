import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/error_handling/crash_reporter.dart';
import 'package:lumovault/core/error_handling/global_error_handler.dart';

/// A [CrashReporter] that records all calls for verification.
class _RecordingCrashReporter implements CrashReporter {
  final List<_RecordedError> errors = [];

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, dynamic>? extra,
  }) async {
    errors.add(_RecordedError(error, stack, reason, fatal));
  }

  @override
  Future<void> log(String message, {Map<String, dynamic>? extra}) async {}

  @override
  Future<void> initialize() async {}

  @override
  void setUser(String? userId) {}

  @override
  Future<void> flush() async {}
}

class _RecordedError {
  _RecordedError(this.error, this.stack, this.reason, this.fatal);
  final Object error;
  final StackTrace? stack;
  final String? reason;
  final bool fatal;
}

void main() {
  setUp(() {
    GlobalErrorHandler.reset();
  });

  tearDown(() {
    GlobalErrorHandler.reset();
  });

  group('GlobalErrorHandler', () {
    test('initialize does not throw', () {
      const reporter = NullCrashReporter();
      GlobalErrorHandler.initialize(reporter: reporter);
    });

    test('initialize is idempotent', () {
      const reporter = NullCrashReporter();
      GlobalErrorHandler.initialize(reporter: reporter);
      GlobalErrorHandler.initialize(reporter: reporter);
    });

    test('FlutterError.onError forwards to reporter', () {
      final reporter = _RecordingCrashReporter();
      GlobalErrorHandler.initialize(reporter: reporter);

      final error = FlutterErrorDetails(
        exception: StateError('test flutter error'),
        stack: StackTrace.current,
        library: 'test',
      );
      // Call the handler that initialize installed directly.
      FlutterError.onError!(error);

      expect(reporter.errors, hasLength(1));
      expect(reporter.errors.first.error, isA<StateError>());
      expect(reporter.errors.first.reason, 'FlutterError.onError');
      expect(reporter.errors.first.fatal, isFalse);
    });

    test('PlatformDispatcher.onError forwards to reporter', () {
      final reporter = _RecordingCrashReporter();
      GlobalErrorHandler.initialize(reporter: reporter);

      final testError = Exception('platform error');
      final testStack = StackTrace.current;
      PlatformDispatcher.instance.onError!(testError, testStack);

      expect(reporter.errors, hasLength(1));
      expect(reporter.errors.first.error, testError);
      expect(reporter.errors.first.reason, 'PlatformDispatcher.onError');
      expect(reporter.errors.first.fatal, isTrue);
    });

    test('PlatformDispatcher.onError returns false (rethrows)', () {
      const reporter = NullCrashReporter();
      GlobalErrorHandler.initialize(reporter: reporter);

      final result = PlatformDispatcher.instance.onError!(
        Exception('test'),
        StackTrace.current,
      );
      expect(result, isFalse);
    });

    test('null reporter does not throw on FlutterError', () {
      GlobalErrorHandler.initialize(reporter: null);

      FlutterError.onError?.call(
        FlutterErrorDetails(
          exception: StateError('test'),
          stack: StackTrace.current,
        ),
      );
    });

    test('null reporter does not throw on PlatformDispatcher', () {
      GlobalErrorHandler.initialize(reporter: null);

      final result = PlatformDispatcher.instance.onError!(
        Exception('test'),
        StackTrace.current,
      );
      expect(result, isFalse);
    });
  });
}
