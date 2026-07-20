import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/metadata/data/models/metadata_partition.dart';

void main() {
  group('PartitionItem', () {
    test('fromMediaItem creates correct partition item', () {
      final item = MediaItem(
        localId: '123',
        fileHash: 'abc123',
        filePath: '/path/file.jpg',
        fileName: 'file.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024,
        width: 1920,
        height: 1080,
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        scannedAt: DateTime(2026, 1, 15),
        isFavorite: true,
        albumName: 'Camera',
      );

      final partitionItem = PartitionItem.fromMediaItem(item);

      expect(partitionItem.localId, '123');
      expect(partitionItem.fileHash, 'abc123');
      expect(partitionItem.isFavorite, isTrue);
      expect(partitionItem.albumName, 'Camera');
    });

    test('toJson produces correct JSON', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc123',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        fileSize: 1024,
        isFavorite: true,
      );

      final json = item.toJson();

      expect(json['lid'], '123');
      expect(json['h'], 'abc123');
      expect(json['sz'], 1024);
      expect(json['fav'], true);
    });

    test('fromJson parses correct JSON', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc123',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        fileSize: 1024,
        isFavorite: true,
      );

      final json = item.toJson();
      final parsed = PartitionItem.fromJson(json);

      expect(parsed.localId, '123');
      expect(parsed.fileHash, 'abc123');
      expect(parsed.fileSize, 1024);
      expect(parsed.isFavorite, isTrue);
    });

    test('equality based on localId and fileHash', () {
      final a = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 1),
      );
      final b = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 1),
      );
      final c = PartitionItem(
        localId: '456',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 1),
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('MetadataPartition', () {
    test('partitionKeyFromDate generates correct key', () {
      expect(
        MetadataPartition.partitionKeyFromDate(DateTime(2026, 1, 15)),
        '2026/01',
      );
      expect(
        MetadataPartition.partitionKeyFromDate(DateTime(2026, 12, 25)),
        '2026/12',
      );
    });

    test('dateFromPartitionKey parses correct date', () {
      final date = MetadataPartition.dateFromPartitionKey('2026/01');
      expect(date.year, 2026);
      expect(date.month, 1);
    });

    test('computeHash produces deterministic hash', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 1),
      );

      final partition = MetadataPartition(
        id: '2026/01',
        periodStart: DateTime(2026, 1),
        periodEnd: DateTime(2026, 2),
        items: [item],
        lastModified: DateTime(2026, 1, 15),
      );

      final hash1 = partition.computeHash();
      final hash2 = partition.computeHash();

      expect(hash1, equals(hash2));
    });

    test('hasChanged detects changes', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 1),
      );

      final partition = MetadataPartition(
        id: '2026/01',
        periodStart: DateTime(2026, 1),
        periodEnd: DateTime(2026, 2),
        items: [item],
        lastModified: DateTime(2026, 1, 15),
      );

      final hash = partition.computeHash();
      expect(partition.hasChanged(hash), isFalse);
      expect(partition.hasChanged('different_hash'), isTrue);
    });

    test('toJsonString produces valid JSON', () {
      final partition = MetadataPartition(
        id: '2026/01',
        periodStart: DateTime(2026, 1),
        periodEnd: DateTime(2026, 2),
        items: [
          PartitionItem(
            localId: '123',
            fileHash: 'abc',
            createdAt: DateTime(2026, 1, 1),
            modifiedAt: DateTime(2026, 1, 1),
          ),
        ],
        lastModified: DateTime(2026, 1, 15),
      );

      final json = partition.toJsonString();
      expect(json, isNotEmpty);
      expect(json, contains('"id":"2026/01"'));
    });

    test('fromJsonString parses valid JSON', () {
      final original = MetadataPartition(
        id: '2026/01',
        periodStart: DateTime(2026, 1),
        periodEnd: DateTime(2026, 2),
        items: [
          PartitionItem(
            localId: '123',
            fileHash: 'abc',
            createdAt: DateTime(2026, 1, 1),
            modifiedAt: DateTime(2026, 1, 1),
          ),
        ],
        lastModified: DateTime(2026, 1, 15),
      );

      final json = original.toJsonString();
      final parsed = MetadataPartition.fromJsonString(json);

      expect(parsed, isNotNull);
      expect(parsed!.id, '2026/01');
      expect(parsed.items.length, 1);
    });

    test('fromJsonString returns null for invalid JSON', () {
      final parsed = MetadataPartition.fromJsonString('invalid');
      expect(parsed, isNull);
    });

    test('equality based on id', () {
      final a = MetadataPartition(
        id: '2026/01',
        periodStart: DateTime(2026, 1),
        periodEnd: DateTime(2026, 2),
        lastModified: DateTime(2026, 1, 15),
      );
      final b = MetadataPartition(
        id: '2026/01',
        periodStart: DateTime(2026, 1),
        periodEnd: DateTime(2026, 2),
        lastModified: DateTime(2026, 1, 15),
      );
      final c = MetadataPartition(
        id: '2026/02',
        periodStart: DateTime(2026, 2),
        periodEnd: DateTime(2026, 3),
        lastModified: DateTime(2026, 1, 15),
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('copyWith creates updated copy', () {
      final original = MetadataPartition(
        id: '2026/01',
        periodStart: DateTime(2026, 1),
        periodEnd: DateTime(2026, 2),
        items: const [],
        lastModified: DateTime(2026, 1, 15),
      );

      final updated = original.copyWith(
        items: [
          PartitionItem(
            localId: '123',
            fileHash: 'abc',
            createdAt: DateTime(2026, 1, 1),
            modifiedAt: DateTime(2026, 1, 1),
          ),
        ],
      );

      expect(updated.items.length, 1);
      expect(original.items.length, 0);
    });
  });
}
