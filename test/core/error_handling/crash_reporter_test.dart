import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/error_handling/crash_reporter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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

  group('PII scrubbing', () {
    // LumoVault is a private photo vault: TDLib-derived errors carry channel
    // titles, message ids and real file names from the user's library. These
    // must not leave the device when a DSN is configured.
    test('redacts an absolute media path', () {
      final scrubbed = scrubSentryPii(
        'Could not read /storage/emulated/0/DCIM/Camera/IMG_20260115_143052.jpg',
      );

      expect(scrubbed, isNot(contains('IMG_20260115_143052')));
      expect(scrubbed, isNot(contains('/storage/emulated')));
    });

    test('redacts a bare media file name', () {
      final scrubbed = scrubSentryPii("Upload failed for 'party 2026 (1).mp4'");

      expect(scrubbed, isNot(contains('party 2026')));
      expect(scrubbed, contains('[media-file]'));
    });

    test('redacts a channel title from a storage-setup error', () {
      final scrubbed = scrubSentryPii(
        'Could not set up Telegram storage: Abid Family Photos',
      );

      expect(scrubbed, isNot(contains('Abid Family Photos')));
      expect(scrubbed, contains('[redacted]'));
    });

    test('redacts telegram pointers and numeric chat ids', () {
      expect(
        scrubSentryPii('no access to telegram://987654321'),
        'no access to telegram://[id]',
      );
      expect(
        scrubSentryPii('failed for chat id: 424242'),
        'failed for [chat-id]',
      );
    });

    test('leaves ordinary diagnostic text intact', () {
      const plain = 'Timeout after 30 seconds while retrying';
      expect(scrubSentryPii(plain), plain);
    });

    test('scrubSentryMap redacts nested string values', () {
      final scrubbed = scrubSentryMap({
        'pointer': 'telegram://987654321',
        'detail': {'file': '/data/user/0/com.lumovault.app/cache/a.jpg'},
        'count': 3,
      });

      expect(scrubbed['pointer'], 'telegram://[id]');
      expect((scrubbed['detail'] as Map)['file'], isNot(contains('a.jpg')));
      expect((scrubbed['detail'] as Map)['file'], contains('[path]'));
      expect(scrubbed['count'], 3);
    });

    test('scrubSentryEvent redacts message and exception payloads', () {
      final event = SentryEvent(
        message: const SentryMessage('failed reading IMG_0001.jpg'),
        exceptions: [
          SentryException(
            type: 'TdLibException',
            value: 'Chat not found: Secret Group',
            stackTrace: SentryStackTrace(
              frames: [
                SentryStackFrame(
                  fileName: '/data/user/0/app/DCIM/IMG_0001.jpg',
                  function: '_uploadTask',
                ),
              ],
            ),
          ),
        ],
      );

      final scrubbed = scrubSentryEvent(event, Hint());

      expect(scrubbed, isNotNull);
      expect(scrubbed!.message!.formatted, isNot(contains('IMG_0001')));
      final exception = scrubbed.exceptions!.first;
      expect(exception.value, isNot(contains('Secret Group')));
      final frame = exception.stackTrace!.frames.first;
      expect(frame.fileName, isNot(contains('IMG_0001')));
      // Non-PII frame data survives so the report stays diagnosable.
      expect(frame.function, '_uploadTask');
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
