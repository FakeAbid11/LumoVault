import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/metadata/data/models/metadata_models.dart';
import 'package:lumovault/features/metadata/data/repositories/conflict_resolver.dart';

void main() {
  group('ConflictResolver', () {
    late ConflictResolver resolver;

    setUp(() {
      resolver = ConflictResolver();
    });

    test('resolve returns null for identical items', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
      );

      final result = resolver.resolve(local: item, remote: item);
      expect(result, isNull);
    });

    test('resolve returns local when local is newer', () {
      final local = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 20),
      );
      final remote = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
      );

      final result = resolver.resolve(local: local, remote: remote);
      expect(result, equals(local));
    });

    test('resolve returns remote when remote is newer', () {
      final local = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
      );
      final remote = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 20),
      );

      final result = resolver.resolve(local: local, remote: remote);
      expect(result, equals(remote));
    });

    test('resolve uses field priority when timestamps equal', () {
      final local = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
        isFavorite: false,
        isHidden: true,
      );
      final remote = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
        isFavorite: true,
        isHidden: false,
      );

      final result = resolver.resolve(local: local, remote: remote);
      expect(result, isNotNull);
      expect(result!.isFavorite, isTrue);
      expect(result.isHidden, isTrue);
    });

    test('areIdentical returns true for identical items', () {
      final a = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
        isFavorite: true,
      );
      final b = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
        isFavorite: true,
      );

      expect(resolver.areIdentical(a, b), isTrue);
    });

    test('areIdentical returns false for different items', () {
      final a = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
        isFavorite: true,
      );
      final b = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
        isFavorite: false,
      );

      expect(resolver.areIdentical(a, b), isFalse);
    });

    test('resolve returns remote tombstone when the deletion is newer', () {
      final local = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
      );
      final remote = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 20),
        isDeleted: true,
        deletedAt: DateTime(2026, 1, 20),
      );

      final result = resolver.resolve(local: local, remote: remote);
      expect(result, isNotNull);
      expect(result!.isDeleted, isTrue);
      expect(result.deletedAt, isNotNull);
    });

    test('resolve keeps a deletion sticky when timestamps are equal', () {
      final local = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
        isDeleted: true,
        deletedAt: DateTime(2026, 1, 15),
      );
      final remote = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
      );

      final result = resolver.resolve(local: local, remote: remote);
      expect(result, isNotNull);
      // Either side deleting keeps the resolved item deleted — the two devices
      // converge on the removal instead of one resurrecting it.
      expect(result!.isDeleted, isTrue);
    });

    test('resolve returns null for two identical tombstones', () {
      final tombstone = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 20),
        isDeleted: true,
        deletedAt: DateTime(2026, 1, 20),
      );

      final result = resolver.resolve(local: tombstone, remote: tombstone);
      expect(result, isNull);
    });

    test('resolveBatch resolves multiple conflicts', () {
      final local1 = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 20),
      );
      final remote1 = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
      );

      final local2 = PartitionItem(
        localId: '456',
        fileHash: 'def',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 10),
      );
      final remote2 = PartitionItem(
        localId: '456',
        fileHash: 'def',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
      );

      final resolved = resolver.resolveBatch(
        localItems: [local1, local2],
        remoteItems: [remote1, remote2],
      );

      expect(resolved.length, 2);
      expect(resolved[0].strategy, 'local_wins');
      expect(resolved[1].strategy, 'remote_wins');
    });

    test('hash divergence keeps the loser telegram pointer, not orphaned', () {
      // Same item, edited & re-uploaded on the remote: different bytes, newer.
      final local = PartitionItem(
        localId: '123',
        fileHash: 'old',
        telegramMessageId: '100',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
      );
      final remote = PartitionItem(
        localId: '123',
        fileHash: 'new',
        telegramMessageId: '200',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 20),
      );

      final result = resolver.resolve(local: local, remote: remote)!;

      // Remote wins on recency...
      expect(result.fileHash, 'new');
      expect(result.telegramMessageId, '200');
      // ...but the local file's backup is retained, not dropped.
      expect(result.supersededMessageIds, contains('100'));
    });

    test('field-priority merge is labelled merged, not remote_wins', () {
      final local = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
        isFavorite: true,
      );
      final remote = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
        isHidden: true,
      );

      final resolved = resolver.resolveBatch(
        localItems: [local],
        remoteItems: [remote],
      );

      expect(resolved.single.strategy, 'merged');
    });
  });
}
