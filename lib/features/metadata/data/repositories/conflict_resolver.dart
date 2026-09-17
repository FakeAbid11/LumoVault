import 'dart:convert';

import '../models/metadata_models.dart';

/// Conflict resolution strategy per PRD Section 6.5.
///
/// Rules:
/// - File hash comparison (SHA-256) for deduplication
/// - Last-write-wins for metadata changes
/// - No merge needed (append-only backup)
/// - Telegram is source of truth for file bytes
/// - Isar is source of truth for metadata
class ConflictResolver {
  /// Resolve a conflict between local and remote metadata.
  ///
  /// Per PRD: last-write-wins with timestamps.
  /// Returns the winning version, or null if they're identical.
  PartitionItem? resolve({
    required PartitionItem local,
    required PartitionItem remote,
  }) {
    if (areIdentical(local, remote)) return null;

    if (local.fileHash != remote.fileHash) {
      return _resolveHashDivergence(local, remote);
    }

    return _resolveByTimestamp(local, remote);
  }

  /// Resolve a conflict where the two sides reference *different file bytes*
  /// for the same item (edited and re-uploaded on one device, so the hash and
  /// telegram pointer changed).
  ///
  /// The newer-modified side wins the metadata (ties prefer local), but the
  /// loser's telegram message id is retained in the winner's
  /// [PartitionItem.supersededMessageIds] so its backed-up bytes stay
  /// referenced and recoverable rather than being orphaned in the channel —
  /// the previous code discarded the loser wholesale, silently dropping a
  /// backup.
  PartitionItem _resolveHashDivergence(
    PartitionItem local,
    PartitionItem remote,
  ) {
    final PartitionItem winner;
    final PartitionItem loser;
    if (remote.modifiedAt.isAfter(local.modifiedAt)) {
      winner = remote;
      loser = local;
    } else {
      winner = local;
      loser = remote;
    }

    final pointers = <String>{
      ...winner.supersededMessageIds,
      ...loser.supersededMessageIds,
    };
    final loserMid = loser.telegramMessageId;
    if (loserMid != null &&
        loserMid.isNotEmpty &&
        loserMid != winner.telegramMessageId) {
      pointers.add(loserMid);
    }

    return pointers.length == winner.supersededMessageIds.length
        ? winner
        : winner.copyWith(supersededMessageIds: pointers.toList());
  }

  /// Resolve by comparing modification timestamps.
  ///
  /// The item with the later modifiedAt timestamp wins.
  PartitionItem _resolveByTimestamp(PartitionItem local, PartitionItem remote) {
    if (local.modifiedAt.isAfter(remote.modifiedAt)) {
      return local;
    } else if (remote.modifiedAt.isAfter(local.modifiedAt)) {
      return remote;
    }

    return _resolveByFieldPriority(local, remote);
  }

  /// When timestamps are equal, resolve with a deterministic whole-item winner.
  ///
  /// Neither side "knows" more than the other when `modifiedAt` matches, so a
  /// field-by-field merge has no authority to arbitrate — and it used to be
  /// non-convergent: OR-ed booleans meant an un-favorite / un-archive /
  /// un-trash on one side could never win, and the tag union meant a tag
  /// deletion never propagated. Two devices that both ran this merge would
  /// disagree forever about the item's state.
  ///
  /// The tiebreak is therefore the canonical serialization of the two
  /// *versions* — a property of their content, not of which device happens to
  /// hold them. Picking "the first parameter" would mean every device chooses
  /// its own copy and the pair never converges; `localId` alone is no help
  /// when both sides share it. Both devices see the same two serializations,
  /// so both pick the same item and the pair converges in one round trip.
  ///
  /// One deliberate exception: a deletion tombstone is sticky. If either side
  /// deleted the item, the resolved item stays deleted, keeping two devices
  /// converged on the removal instead of resurrecting it.
  PartitionItem _resolveByFieldPriority(
    PartitionItem local,
    PartitionItem remote,
  ) {
    // Sticky deletion: keep the tombstone and the later known deletion time.
    if (local.isDeleted || remote.isDeleted) {
      final winner = local.isDeleted ? local : remote;
      final deletedAt = local.deletedAt ?? remote.deletedAt;
      if (deletedAt == null || winner.deletedAt == deletedAt) return winner;
      return winner.copyWith(deletedAt: deletedAt);
    }

    // Deterministic winner on version content — same choice on both devices.
    final a = jsonEncode(local.toJson());
    final b = jsonEncode(remote.toJson());
    return a.compareTo(b) <= 0 ? local : remote;
  }

  /// Resolve a batch of conflicts.
  ///
  /// Returns a list of resolved items (only those that changed).
  List<ResolvedConflict> resolveBatch({
    required List<PartitionItem> localItems,
    required List<PartitionItem> remoteItems,
  }) {
    final resolved = <ResolvedConflict>[];

    final remoteMap = {for (final item in remoteItems) item.localId: item};

    for (final local in localItems) {
      final remote = remoteMap[local.localId];
      if (remote == null) continue;

      final result = resolve(local: local, remote: remote);
      if (result != null) {
        resolved.add(
          ResolvedConflict(
            local: local,
            remote: remote,
            resolved: result,
            strategy: _strategyLabel(result, local, remote),
          ),
        );
      }
    }

    return resolved;
  }

  /// Label describing which side the resolved item came from.
  ///
  /// The old `identical(result, local)` check was always false — every
  /// resolution path returns a fresh object (`copyWith`) or the remote — so it
  /// mislabeled everything `remote_wins`. Instead compare the content that
  /// actually distinguishes the sides (file hash + modified time): matching
  /// only local is `local_wins`, only remote is `remote_wins`, and a
  /// field-priority merge that matches both is `merged`.
  String _strategyLabel(
    PartitionItem result,
    PartitionItem local,
    PartitionItem remote,
  ) {
    final matchesLocal =
        result.fileHash == local.fileHash &&
        result.modifiedAt == local.modifiedAt;
    final matchesRemote =
        result.fileHash == remote.fileHash &&
        result.modifiedAt == remote.modifiedAt;
    if (matchesLocal && !matchesRemote) return 'local_wins';
    if (matchesRemote && !matchesLocal) return 'remote_wins';
    return 'merged';
  }

  /// Check if two items are identical (no conflict).
  ///
  /// Compares the *content hash* rather than a hand-picked field list: two
  /// items are identical iff they would produce the same partition digest via
  /// [MetadataPartition.hashItems]. That covers every field participating in
  /// sync — flags, modifiedAt, the deletion tombstone (isDeleted/deletedAt),
  /// album, device folder, description, file name, and tags — so a genuine
  /// remote change to any of them is never mistaken for "no conflict" and
  /// dropped. localId must still match for the items to be the same item.
  bool areIdentical(PartitionItem a, PartitionItem b) {
    return a.localId == b.localId &&
        MetadataPartition.hashItems([a]) == MetadataPartition.hashItems([b]);
  }
}

/// Represents a resolved conflict between local and remote versions.
class ResolvedConflict {
  const ResolvedConflict({
    required this.local,
    required this.remote,
    required this.resolved,
    required this.strategy,
  });
  final PartitionItem local;
  final PartitionItem remote;
  final PartitionItem resolved;
  final String strategy;

  @override
  String toString() =>
      'ResolvedConflict(local: ${local.localId}, strategy: $strategy)';
}
