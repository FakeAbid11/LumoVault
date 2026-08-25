import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/error_handling/global_error_handler.dart';
import 'package:lumovault/core/error_handling/crash_reporter.dart';

void main() {
  group('GlobalErrorHandler', () {
    test('initialize does not throw', () {
      const reporter = NullCrashReporter();
      // Should not throw on first call.
      GlobalErrorHandler.initialize(reporter: reporter);
    });

    test('initialize is idempotent', () {
      const reporter = NullCrashReporter();
      // Double init should not throw.
      GlobalErrorHandler.initialize(reporter: reporter);
      GlobalErrorHandler.initialize(reporter: reporter);
    });
  });
}
