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
      return _resolveByTimestamp(local, remote);
    }

    return _resolveByTimestamp(local, remote);
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
  /// User-facing fields (favorite, hidden, archived) use the
  /// "most restrictive" value. File metadata uses the local value.
  PartitionItem _resolveByFieldPriority(
    PartitionItem local,
    PartitionItem remote,
  ) {
    return local.copyWith(
      isFavorite: local.isFavorite || remote.isFavorite,
      isHidden: local.isHidden || remote.isHidden,
      isArchived: local.isArchived || remote.isArchived,
      isTrashed: local.isTrashed || remote.isTrashed,
      description: local.description ?? remote.description,
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
            strategy: identical(result, local) ? 'local_wins' : 'remote_wins',
          ),
        );
      }
    }

    return resolved;
  }

  /// Check if two items are identical (no conflict).
  bool areIdentical(PartitionItem a, PartitionItem b) {
    return a == b &&
        a.modifiedAt == b.modifiedAt &&
        a.isFavorite == b.isFavorite &&
        a.isHidden == b.isHidden &&
        a.isArchived == b.isArchived &&
        a.isTrashed == b.isTrashed &&
        a.status == b.status;
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
