import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/metadata/data/repositories/sync_service.dart';

void main() {
  group('SyncService', () {
    late SyncService service;

    setUp(() {
      service = SyncService(
        debounceDuration: const Duration(milliseconds: 100),
      );
    });

    tearDown(() {
      service.dispose();
    });

    test('syncInProgress returns false initially', () {
      expect(service.syncInProgress, isFalse);
    });

    test('lastSyncTime returns null initially', () {
      expect(service.lastSyncTime, isNull);
    });

    test('pendingCount returns 0 initially', () {
      expect(service.pendingCount, 0);
    });

    test('lastError returns null initially', () {
      expect(service.lastError, isNull);
    });

    test('enqueueChange increments pending count', () {
      service.enqueueChange(mediaItemId: '123', operation: 'update');

      expect(service.pendingCount, 1);
    });

    test('getSyncStatus returns correct status', () {
      final status = service.getSyncStatus();

      expect(status.syncInProgress, isFalse);
      expect(status.pendingChangesCount, 0);
      expect(status.syncError, isNull);
    });

    test('getRecentLog returns empty initially', () {
      final log = service.getRecentLog();
      expect(log, isEmpty);
    });

    test('clearLog clears the log', () {
      service.clearLog();
      expect(service.syncLog, isEmpty);
    });
  });
}
