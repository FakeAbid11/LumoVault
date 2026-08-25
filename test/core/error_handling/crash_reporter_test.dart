import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/error_handling/crash_reporter.dart';

void main() {
  group('NullCrashReporter', () {
    const reporter = NullCrashReporter();

    test('initialize does not throw', () async {
      await reporter.initialize();
    });

    test('recordError does not throw', () async {
      await reporter.recordError(
        Exception('test'),
        StackTrace.current,
        reason: 'test reason',
        fatal: false,
      );
    });

    test('recordError with fatal flag does not throw', () async {
      await reporter.recordError(
        Exception('fatal'),
        StackTrace.current,
        reason: 'fatal error',
        fatal: true,
      );
    });

    test('log does not throw', () async {
      await reporter.log('test message');
    });

    test('log with extra data does not throw', () async {
      await reporter.log('test', extra: {'key': 'value'});
    });

    test('setUser does not throw', () {
      reporter.setUser('user123');
      reporter.setUser(null);
    });

    test('flush does not throw', () async {
      await reporter.flush();
    });
  });

  group('ConsoleCrashReporter', () {
    const reporter = ConsoleCrashReporter();

    test('initialize does not throw', () async {
      await reporter.initialize();
    });

    test('recordError does not throw', () async {
      await reporter.recordError(
        Exception('test'),
        StackTrace.current,
        reason: 'test reason',
        fatal: true,
      );
    });
  });

  group('CrashReporterFactory', () {
    test('creates NullCrashReporter when no DSN provided', () {
      final reporter = CrashReporterFactory.create();
      expect(reporter, isA<NullCrashReporter>());
    });

    test('creates NullCrashReporter with empty DSN', () {
      final reporter = CrashReporterFactory.create(sentryDsn: '');
      expect(reporter, isA<NullCrashReporter>());
    });

    test('creates SentryCrashReporter with a valid DSN', () {
      final reporter = CrashReporterFactory.create(
        sentryDsn: 'https://key@sentry.io/project',
      );
      expect(reporter, isA<SentryCrashReporter>());
      expect(
        (reporter as SentryCrashReporter).dsn,
        'https://key@sentry.io/project',
      );
    });
  });
}
