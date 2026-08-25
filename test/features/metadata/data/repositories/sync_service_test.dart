import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/metadata/data/models/metadata_models.dart';
import 'package:lumovault/features/metadata/data/repositories/sync_log_persistence.dart';
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

    test('pending changes drain after the debounce elapses', () async {
      final batches = <List<SyncChange>>[];
      service.setChangeFlushHandler((changes) async => batches.add(changes));

      service.enqueueChange(mediaItemId: '123', operation: 'update');
      service.enqueueChange(mediaItemId: '456', operation: 'create');
      expect(service.pendingCount, 2);

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(service.pendingCount, 0);
      expect(batches, hasLength(1));
      expect(batches.single.map((c) => c.mediaItemId), ['123', '456']);
      expect(service.syncLog, hasLength(2));
      expect(service.lastError, isNull);
    });

    test('repeated changes to one item coalesce to the newest', () async {
      final batches = <List<SyncChange>>[];
      service.setChangeFlushHandler((changes) async => batches.add(changes));

      service.enqueueChange(mediaItemId: '123', operation: 'create');
      service.enqueueChange(mediaItemId: '123', operation: 'update');
      service.enqueueChange(mediaItemId: '123', operation: 'trash');

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(batches.single, hasLength(1));
      expect(batches.single.single.operation, 'trash');
      expect(service.pendingCount, 0);
    });

    test('a failing flush re-queues the batch and records the error', () async {
      service.setChangeFlushHandler((changes) async {
        throw StateError('offline');
      });

      service.enqueueChange(mediaItemId: '123', operation: 'update');
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(service.pendingCount, 1);
      expect(service.lastError, contains('offline'));
      // The handler keeps failing, so every logged attempt is a flush_failed.
      expect(service.syncLog, isNotEmpty);
      expect(
        service.syncLog.every((e) => e.operation == 'flush_failed'),
        isTrue,
      );
      expect(service.syncLog.every((e) => !e.success), isTrue);
    });

    test('a failed flush self-retries without a new change enqueued', () async {
      var attempts = 0;
      final delivered = <List<SyncChange>>[];
      service.setChangeFlushHandler((changes) async {
        attempts++;
        if (attempts == 1) throw StateError('transient');
        delivered.add(changes);
      });

      service.enqueueChange(mediaItemId: '123', operation: 'update');

      // First attempt fails at ~100ms; the self-retry timer (backoff == the
      // 100ms debounce after one failure) fires the second attempt without any
      // further enqueueChange. Wait long enough for both.
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(attempts, greaterThanOrEqualTo(2));
      expect(delivered, hasLength(1));
      expect(delivered.single.single.mediaItemId, '123');
      expect(service.pendingCount, 0);
    });

    test('draining without a handler still clears the queue', () async {
      service.enqueueChange(mediaItemId: '123', operation: 'update');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(service.pendingCount, 0);
      expect(service.syncLog, hasLength(1));
    });
  });

  group('SyncService log persistence', () {
    test('initialize restores entries from the store', () async {
      final store = _FakeSyncLogStore()
        ..entries = [
          SyncLogEntity(
            mediaItemId: '123',
            operation: 'update',
            timestamp: DateTime.utc(2026, 1, 1),
          ),
        ];
      final service = SyncService(logStore: store);
      addTearDown(service.dispose);

      await service.initialize();

      expect(service.syncLog, hasLength(1));
      expect(service.syncLog.single.mediaItemId, '123');
    });

    test('a drained batch is written back to the store', () async {
      final store = _FakeSyncLogStore();
      final service = SyncService(
        debounceDuration: const Duration(milliseconds: 100),
        logStore: store,
      );
      addTearDown(service.dispose);

      await service.initialize();
      service.enqueueChange(mediaItemId: '123', operation: 'update');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(store.entries, hasLength(1));
      expect(store.entries.single.mediaItemId, '123');
    });

    test('clearLog empties memory and the store', () async {
      final store = _FakeSyncLogStore()
        ..entries = [
          SyncLogEntity(
            mediaItemId: '123',
            operation: 'update',
            timestamp: DateTime.utc(2026, 1, 1),
          ),
        ];
      final service = SyncService(logStore: store);
      addTearDown(service.dispose);

      await service.initialize();
      await service.clearLog();

      expect(service.syncLog, isEmpty);
      expect(store.entries, isEmpty);
      expect(store.cleared, isTrue);
    });
  });
}

class _FakeSyncLogStore implements SyncLogStore {
  List<SyncLogEntity> entries = [];
  bool cleared = false;

  @override
  Future<List<SyncLogEntity>> load() async => entries;

  @override
  Future<void> save(List<SyncLogEntity> newEntries) async {
    entries = List.of(newEntries);
  }

  @override
  Future<void> clear() async {
    entries = [];
    cleared = true;
  }
}
