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

  /// When timestamps are equal, use field-level priority.
  ///
  /// User-facing boolean flags use the "most restrictive"/"sticky" value
  /// (OR-ed), so a favorite/hidden/archived/trashed set on either side wins.
  /// A deletion tombstone is likewise sticky: if either side deleted the item,
  /// the resolved item stays deleted, keeping the two devices converged on the
  /// removal instead of resurrecting it. Free-form fields prefer the local
  /// value, falling back to remote when local is null.
  PartitionItem _resolveByFieldPriority(
    PartitionItem local,
    PartitionItem remote,
  ) {
    return local.copyWith(
      isFavorite: local.isFavorite || remote.isFavorite,
      isHidden: local.isHidden || remote.isHidden,
      isArchived: local.isArchived || remote.isArchived,
      isTrashed: local.isTrashed || remote.isTrashed,
      isDeleted: local.isDeleted || remote.isDeleted,
      deletedAt: local.deletedAt ?? remote.deletedAt,
      description: local.description ?? remote.description,
      albumName: local.albumName ?? remote.albumName,
      deviceFolder: local.deviceFolder ?? remote.deviceFolder,
      fileName: local.fileName ?? remote.fileName,
      tags: {...local.tags, ...remote.tags}.toList(),
    );
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
