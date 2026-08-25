import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/metadata/data/models/metadata_models.dart';
import 'package:lumovault/features/metadata/data/repositories/partition_service.dart';

void main() {
  group('PartitionService', () {
    late PartitionService service;

    setUp(() {
      service = PartitionService();
    });

    tearDown(() {
      service.dispose();
    });

    test('getPartition returns null for unknown key', () {
      expect(service.getPartition('2026/01'), isNull);
    });

    test('upsertItem creates new partition', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
      );

      service.upsertItem(item);

      expect(service.partitionCount, 1);
      final partition = service.getPartition('2026/01');
      expect(partition, isNotNull);
      expect(partition!.items.length, 1);
    });

    test('upsertItem adds to existing partition', () {
      final item1 = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
      );
      final item2 = PartitionItem(
        localId: '456',
        fileHash: 'def',
        createdAt: DateTime(2026, 1, 20),
        modifiedAt: DateTime(2026, 1, 20),
      );

      service.upsertItem(item1);
      service.upsertItem(item2);

      expect(service.partitionCount, 1);
      final partition = service.getPartition('2026/01');
      expect(partition!.items.length, 2);
    });

    test('upsertItem updates existing item', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        isFavorite: false,
      );

      service.upsertItem(item);

      final updatedItem = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        isFavorite: true,
      );

      service.upsertItem(updatedItem);

      expect(service.partitionCount, 1);
      final partition = service.getPartition('2026/01');
      expect(partition!.items.length, 1);
      expect(partition.items[0].isFavorite, isTrue);
    });

    test('removeItem removes item from partition', () {
      final item1 = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
      );
      final item2 = PartitionItem(
        localId: '456',
        fileHash: 'def',
        createdAt: DateTime(2026, 1, 20),
        modifiedAt: DateTime(2026, 1, 20),
      );

      service.upsertItem(item1);
      service.upsertItem(item2);
      service.removeItem('123');

      final partition = service.getPartition('2026/01');
      expect(partition!.items.length, 1);
      expect(partition.items[0].localId, '456');
    });

    test('removeItem deletes empty partition', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
      );

      service.upsertItem(item);
      expect(service.partitionCount, 1);

      service.removeItem('123');
      expect(service.partitionCount, 0);
    });

    test('getDirtyPartitionIds returns all when no manifest hashes', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
      );

      service.upsertItem(item);

      final dirty = service.getDirtyPartitionIds();
      expect(dirty.length, 1);
      expect(dirty.contains('2026/01'), isTrue);
    });

    test('getDirtyPartitionIds detects changed partitions', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
      );

      service.upsertItem(item);

      final currentHash = service.getPartition('2026/01')!.computeHash();
      final manifestHashes = {'2026/01': currentHash};

      final dirty = service.getDirtyPartitionIds(
        manifestHashes: manifestHashes,
      );
      expect(dirty, isEmpty);
    });

    test('diff detects added partitions', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
      );

      service.upsertItem(item);

      final diff = service.diff(remotePartitions: {});
      expect(diff.added.length, 1);
      expect(diff.hasChanges, isTrue);
    });

    test('diff detects removed partitions', () {
      final remotePartitions = {
        '2026/01': MetadataPartition(
          id: '2026/01',
          periodStart: DateTime(2026, 1),
          periodEnd: DateTime(2026, 2),
          lastModified: DateTime(2026, 1, 15),
        ),
      };

      final diff = service.diff(remotePartitions: remotePartitions);
      expect(diff.removed.length, 1);
      expect(diff.hasChanges, isTrue);
    });

    test('serializePartition returns JSON string', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
      );

      service.upsertItem(item);

      final json = service.serializePartition('2026/01');
      expect(json, isNotNull);
      expect(json, contains('2026/01'));
    });

    test('deserializePartition stores partition', () {
      final partition = MetadataPartition(
        id: '2026/01',
        periodStart: DateTime(2026, 1),
        periodEnd: DateTime(2026, 2),
        items: [
          PartitionItem(
            localId: '123',
            fileHash: 'abc',
            createdAt: DateTime(2026, 1, 15),
            modifiedAt: DateTime(2026, 1, 15),
          ),
        ],
        lastModified: DateTime(2026, 1, 15),
      );

      service.deserializePartition(partition.toJsonString());

      expect(service.partitionCount, 1);
      expect(service.getPartition('2026/01')!.items.length, 1);
    });

    test('clear removes all partitions', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
      );

      service.upsertItem(item);
      expect(service.partitionCount, 1);

      service.clear();
      expect(service.partitionCount, 0);
    });

    test('getAllPartitions returns sorted list', () {
      final item1 = PartitionItem(
        localId: '1',
        fileHash: 'a',
        createdAt: DateTime(2026, 2, 1),
        modifiedAt: DateTime(2026, 2, 1),
      );
      final item2 = PartitionItem(
        localId: '2',
        fileHash: 'b',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 1),
      );

      service.upsertItem(item1);
      service.upsertItem(item2);

      final all = service.getAllPartitions();
      expect(all.length, 2);
      expect(all[0].id, '2026/01');
      expect(all[1].id, '2026/02');
    });
  });
}
