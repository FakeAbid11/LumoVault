import 'dart:collection';

import '../models/metadata_models.dart';

/// Service for managing partitioned metadata files per PRD Section 6.
///
/// Metadata is partitioned by date (YYYY/MM) for efficient incremental sync.
/// Only changed partitions are re-uploaded, not the entire metadata set.
class PartitionService {
  final Map<String, MetadataPartition> _partitions = {};

  UnmodifiableMapView<String, MetadataPartition> get partitions =>
      UnmodifiableMapView(_partitions);

  int get partitionCount => _partitions.length;

  /// Get a partition by key.
  MetadataPartition? getPartition(String key) {
    return _partitions[key];
  }

  /// Get all partitions.
  List<MetadataPartition> getAllPartitions() {
    return _partitions.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  /// Upsert an item into the appropriate partition.
  ///
  /// Creates the partition if it doesn't exist. Updates the partition's
  /// lastModified timestamp.
  void upsertItem(PartitionItem item) {
    final key = MetadataPartition.partitionKeyFromDate(item.createdAt);
    final now = DateTime.now().toUtc();

    if (_partitions.containsKey(key)) {
      final existing = _partitions[key]!;
      final itemIndex = existing.items.indexWhere(
        (i) => i.localId == item.localId,
      );

      List<PartitionItem> updatedItems;
      if (itemIndex >= 0) {
        updatedItems = List<PartitionItem>.from(existing.items);
        updatedItems[itemIndex] = item;
      } else {
        updatedItems = [...existing.items, item];
      }

      _partitions[key] = existing.copyWith(
        items: updatedItems,
        lastModified: now,
      );
    } else {
      final startDate = MetadataPartition.dateFromPartitionKey(key);
      final endDate = DateTime(startDate.year, startDate.month + 1);

      _partitions[key] = MetadataPartition(
        id: key,
        periodStart: startDate,
        periodEnd: endDate,
        items: [item],
        lastModified: now,
      );
    }
  }

  /// Remove an item from its partition.
  ///
  /// If the partition becomes empty, it is removed.
  void removeItem(String localId) {
    final key = _findPartitionKeyForItem(localId);
    if (key == null) return;

    final existing = _partitions[key]!;
    final updatedItems = existing.items
        .where((i) => i.localId != localId)
        .toList();

    if (updatedItems.isEmpty) {
      _partitions.remove(key);
    } else {
      _partitions[key] = existing.copyWith(
        items: updatedItems,
        lastModified: DateTime.now().toUtc(),
      );
    }
  }

  /// Find which partition key contains an item.
  String? _findPartitionKeyForItem(String localId) {
    for (final entry in _partitions.entries) {
      if (entry.value.items.any((i) => i.localId == localId)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Get partition IDs where the local hash differs from the manifest hash.
  List<String> getDirtyPartitionIds({Map<String, String>? manifestHashes}) {
    if (manifestHashes == null) {
      return _partitions.keys.toList();
    }

    final dirty = <String>[];
    for (final entry in _partitions.entries) {
      final localHash = entry.value.computeHash();
      final remoteHash = manifestHashes[entry.key];
      if (localHash != remoteHash) {
        dirty.add(entry.key);
      }
    }
    return dirty;
  }

  /// Serialize a partition to JSON string for upload.
  String? serializePartition(String partitionId) {
    final partition = _partitions[partitionId];
    if (partition == null) return null;
    return partition.toJsonString();
  }

  /// Deserialize and store a partition from JSON string.
  void deserializePartition(String jsonString) {
    final partition = MetadataPartition.fromJsonString(jsonString);
    if (partition != null) {
      _partitions[partition.id] = partition;
    }
  }

  /// Get diff between two sets of partitions.
  ///
  /// Returns partition IDs that have been added, updated, or removed.
  PartitionDiff diff({
    required Map<String, MetadataPartition> remotePartitions,
  }) {
    final added = <String>[];
    final updated = <String>[];
    final removed = <String>[];

    // Check for added or updated partitions.
    for (final entry in _partitions.entries) {
      final remote = remotePartitions[entry.key];
      if (remote == null) {
        added.add(entry.key);
      } else {
        final localHash = entry.value.computeHash();
        final remoteHash = remote.computeHash();
        if (localHash != remoteHash) {
          updated.add(entry.key);
        }
      }
    }

    // Check for removed partitions.
    for (final key in remotePartitions.keys) {
      if (!_partitions.containsKey(key)) {
        removed.add(key);
      }
    }

    return PartitionDiff(added: added, updated: updated, removed: removed);
  }

  /// Clear all partitions.
  void clear() {
    _partitions.clear();
  }

  void dispose() {
    _partitions.clear();
  }
}

/// Result of comparing two partition sets.
class PartitionDiff {
  const PartitionDiff({
    required this.added,
    required this.updated,
    required this.removed,
  });
  final List<String> added;
  final List<String> updated;
  final List<String> removed;

  bool get hasChanges =>
      added.isNotEmpty || updated.isNotEmpty || removed.isNotEmpty;

  int get totalChanges => added.length + updated.length + removed.length;

  @override
  String toString() =>
      'PartitionDiff(added: ${added.length}, updated: ${updated.length}, '
      'removed: ${removed.length})';
}
