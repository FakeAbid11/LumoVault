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

    test('resolve converges when timestamps are equal', () {
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

      // Equal timestamps must not OR-merge the flags: that made an un-favorite
      // or un-hide on one side impossible to ever win, and both devices would
      // disagree forever. One whole item wins, and the choice is independent
      // of which side holds it.
      final fromA = resolver.resolve(local: local, remote: remote)!;
      final fromB = resolver.resolve(local: remote, remote: local)!;

      expect(fromA, equals(fromB), reason: 'resolution must be order-independent');
      // The winner is one of the two versions, not a merge of both: the
      // resolved flags must match exactly one side's pair.
      final matchesLocal = fromA.isFavorite == local.isFavorite &&
          fromA.isHidden == local.isHidden;
      final matchesRemote = fromA.isFavorite == remote.isFavorite &&
          fromA.isHidden == remote.isHidden;
      expect(
        matchesLocal || matchesRemote,
        isTrue,
        reason: 'a whole item must win, not a field merge',
      );
      expect(
        matchesLocal && matchesRemote,
        isFalse,
        reason: 'the two versions differ, so the result cannot match both',
      );
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

    test('equal timestamps resolve to the same winner on both sides', () {
      final local = PartitionItem(
        localId: 'beta',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
        isFavorite: true,
        tags: const ['keep'],
      );
      final remote = PartitionItem(
        localId: 'beta',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
        isFavorite: false,
        tags: const [],
      );

      // Device A sees (local=beta, remote=beta); device B sees them swapped.
      // A field-merge used to OR the flags and union the tags, so neither
      // device could ever un-favorite or un-tag the item.
      final fromA = resolver.resolve(local: local, remote: remote)!;
      final fromB = resolver.resolve(local: remote, remote: local)!;

      // Both devices must settle on the same version — the whole point of a
      // content-based tiebreak is that argument order does not matter.
      expect(fromA, equals(fromB), reason: 'both devices must converge');
      expect(fromA.tags, fromB.tags);
      expect(fromA.isFavorite, fromB.isFavorite);
    });

    test('a deletion wins even when timestamps are equal', () {
      final live = PartitionItem(
        localId: 'gamma',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
      );
      final tombstone = live.copyWith(
        isDeleted: true,
        deletedAt: DateTime(2026, 1, 20),
      );

      final result = resolver.resolve(local: live, remote: tombstone)!;
      expect(result.isDeleted, isTrue, reason: 'deletion is sticky');
    });
  });
}
