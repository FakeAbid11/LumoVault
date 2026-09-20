import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/logging/app_logger.dart';

void main() {
  group('AppLogger gate', () {
    final captured = <String?>[];
    late DebugPrintCallback original;

    setUp(() {
      captured.clear();
      original = debugPrint;
      // Point the sink at our capture list, then install the gate so it wraps
      // this sink. resetForTesting() in tearDown ensures a fresh wrap each run.
      debugPrint = (String? message, {int? wrapWidth}) => captured.add(message);
      AppLogger.install();
    });

    tearDown(() {
      AppLogger.resetForTesting();
      debugPrint = original;
    });

    test('suppresses tagged app logs when verbose disabled', () {
      AppLogger.verboseEnabled = false;
      debugPrint('[BackupEngine] scanning media');
      expect(captured, isEmpty);
    });

    test('forwards tagged app logs when verbose enabled', () {
      AppLogger.verboseEnabled = true;
      debugPrint('[BackupEngine] scanning media');
      expect(captured, contains('[BackupEngine] scanning media'));
    });

    test('always forwards untagged framework logs', () {
      AppLogger.verboseEnabled = false;
      debugPrint('plain framework message');
      expect(captured, contains('plain framework message'));
    });

    test('install is idempotent (does not double-wrap)', () {
      AppLogger.install();
      AppLogger.install();
      AppLogger.verboseEnabled = false;
      debugPrint('[Tag] should be dropped exactly once');
      expect(captured, isEmpty);
    });
  });
}
