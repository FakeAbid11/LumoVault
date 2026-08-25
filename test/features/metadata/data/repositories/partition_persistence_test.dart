import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/metadata/data/models/metadata_models.dart';
import 'package:lumovault/features/metadata/data/repositories/partition_persistence.dart';
import 'package:lumovault/features/metadata/data/repositories/partition_service.dart';

class _FakePartitionStore implements PartitionStore {
  List<MetadataPartition> saved = [];
  int saveCount = 0;
  bool cleared = false;

  @override
  Future<List<MetadataPartition>> load() async => saved;

  @override
  Future<void> save(List<MetadataPartition> partitions) async {
    saved = List.of(partitions);
    saveCount++;
  }

  @override
  Future<void> clear() async {
    saved = [];
    cleared = true;
  }
}

PartitionItem _item(String localId) => PartitionItem(
  localId: localId,
  fileHash: 'hash-$localId',
  createdAt: DateTime(2026, 1, 15),
  modifiedAt: DateTime(2026, 1, 15),
);

void main() {
  group('PartitionService persistence', () {
    test('mutations are persisted after the debounce', () async {
      final store = _FakePartitionStore();
      final service = PartitionService(
        store: store,
        persistDebounce: const Duration(milliseconds: 50),
      );
      addTearDown(service.dispose);

      service.upsertItem(_item('1'));

      // Debounced: nothing on disk yet.
      expect(store.saveCount, 0);

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(store.saveCount, 1);
      expect(store.saved, hasLength(1));
      expect(store.saved.single.id, '2026/01');
      expect(store.saved.single.items.single.localId, '1');
    });

    test(
      'saveNow persists immediately without waiting for the debounce',
      () async {
        final store = _FakePartitionStore();
        final service = PartitionService(store: store);
        addTearDown(service.dispose);

        service.upsertItem(_item('1'));
        await service.saveNow();

        expect(store.saveCount, 1);
      },
    );

    test('a reloaded service hydrates from the store', () async {
      final store = _FakePartitionStore();
      final first = PartitionService(store: store);
      addTearDown(first.dispose);
      first.upsertItem(_item('1'));
      await first.saveNow();

      // Simulate an app restart: a brand new service sharing the same store
      // restores the partition set via the store's load output.
      final restarted = PartitionService(store: store);
      addTearDown(restarted.dispose);
      for (final partition in await store.load()) {
        restarted.deserializePartition(partition.toJsonString());
      }

      expect(restarted.partitionCount, 1);
      expect(restarted.getPartition('2026/01'), isNotNull);
      expect(restarted.getPartition('2026/01')!.items.single.localId, '1');
      expect(
        restarted.getPartition('2026/01')!.items.single.fileHash,
        'hash-1',
      );
    });

    test('removal and clear are persisted too', () async {
      final store = _FakePartitionStore();
      final service = PartitionService(
        store: store,
        persistDebounce: const Duration(milliseconds: 50),
      );
      addTearDown(service.dispose);

      service.upsertItem(_item('1'));
      await service.saveNow();

      service.removeItem('1');
      await service.saveNow();
      expect(store.saved, isEmpty);

      service.upsertItem(_item('2'));
      await service.saveNow();
      service.clear();
      await service.saveNow();
      expect(store.saved, isEmpty);
    });

    test('no store means no persistence and no timers', () async {
      final service = PartitionService();
      addTearDown(service.dispose);

      service.upsertItem(_item('1'));
      // Must not throw; the debounced save is a no-op when store is null.
      await service.saveNow();
      expect(service.partitionCount, 1);
    });
  });
}
