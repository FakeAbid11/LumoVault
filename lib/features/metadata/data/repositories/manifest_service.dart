import 'dart:async';
import 'dart:collection';

import '../models/metadata_models.dart';
import 'manifest_persistence.dart';

/// Service for generating, updating, and managing the manifest per PRD Section 6.4.
///
/// The manifest is stored as the pinned message in the private Telegram channel.
/// It provides a global view of all backed-up media and pointers to partitions.
class ManifestService {
  ManifestService({
    this.store,
    this.persistDebounce = const Duration(milliseconds: 300),
  });

  /// Optional persistence for the current manifest.
  ///
  /// When null the manifest is memory-only, which keeps plain `flutter test`
  /// runs (no plugin registrant) working — the provider-wired instance passes
  /// a file store so the baseline survives restarts.
  final ManifestStore? store;

  /// Coalescing window for [store] writes.
  final Duration persistDebounce;

  Manifest? _currentManifest;
  final Map<String, String> _partitionHashes = {};
  Timer? _persistTimer;

  Manifest? getCurrentManifest() => _currentManifest;

  /// Set the current manifest (e.g., after fetching from Telegram).
  void setManifest(Manifest manifest) {
    _currentManifest = manifest;
    for (final chunk in manifest.chunks) {
      _partitionHashes[chunk.id] = chunk.hash;
    }
    _persist();
  }

  /// Get the stored hash for a partition.
  String? getPartitionHash(String partitionId) {
    return _partitionHashes[partitionId];
  }

  /// Generate a new manifest from current local metadata state.
  ///
  /// Per PRD Section 6.4, the manifest contains:
  /// - app: "lumovault"
  /// - schema_version: 1
  /// - created: ISO8601 timestamp
  /// - device_hash: SHA-256 of device ID
  /// - total_media: count of all media items
  /// - total_size_bytes: sum of file sizes
  /// - last_sync: ISO8601 timestamp
  /// - chunks: list of partition metadata (id, count, hash)
  ///
  /// This describes *current* local state. It deliberately does NOT advance
  /// [partitionHashes]: the baseline for the dirty check may only move after
  /// a successful upload ([recordSyncedPartitions]) or when a remote manifest
  /// is loaded ([setManifest]). Advancing it here (as an earlier version did)
  /// made every partition look clean the moment a change was flushed — so
  /// [SyncService.syncToTelegram] found nothing dirty and partition files
  /// were never re-uploaded.
  Future<Manifest> generateManifest({
    required List<PartitionItem> localMetadata,
    required String deviceHash,
  }) async {
    final now = DateTime.now().toUtc();

    final totalMedia = localMetadata.length;
    final totalSizeBytes = localMetadata.fold<int>(
      0,
      (sum, item) => sum + item.fileSize,
    );

    final chunks = _computeChunks(localMetadata);

    final manifest = Manifest(
      created: _currentManifest?.created ?? now,
      deviceHash: deviceHash,
      totalMedia: totalMedia,
      totalSizeBytes: totalSizeBytes,
      lastSync: now,
      chunks: chunks,
    );

    _currentManifest = manifest;
    _persist();
    return manifest;
  }

  /// Compute chunk entries from metadata items.
  ///
  /// Items are grouped by partition key (YYYY/MM). Each partition
  /// becomes a chunk in the manifest.
  List<ManifestChunk> _computeChunks(List<PartitionItem> items) {
    final Map<String, List<PartitionItem>> partitions = {};

    for (final item in items) {
      final key = MetadataPartition.partitionKeyFromDate(item.createdAt);
      partitions.putIfAbsent(key, () => []).add(item);
    }

    final chunks = <ManifestChunk>[];
    for (final entry in partitions.entries) {
      final hash = _computePartitionHash(entry.value);
      chunks.add(
        ManifestChunk(id: entry.key, count: entry.value.length, hash: hash),
      );
      // Deliberately does NOT touch _partitionHashes: the baseline may only
      // advance via recordSyncedPartitions (after a successful upload) or
      // setManifest (when a remote manifest is loaded). See generateManifest.
    }

    chunks.sort((a, b) => a.id.compareTo(b.id));
    return chunks;
  }

  /// Compute a deterministic hash for a list of items.
  ///
  /// Delegates to [MetadataPartition.hashItems] so a chunk hash written into
  /// the manifest is byte-identical to what [MetadataPartition.computeHash]
  /// produces for the same items. These used to be two separate
  /// implementations that disagreed: this one sorted the per-item records and
  /// delimited fields with control characters, the partition's did neither.
  /// Comparing a partition hash against a manifest chunk hash therefore
  /// reported a difference for every partition, every time.
  String _computePartitionHash(List<PartitionItem> items) {
    return MetadataPartition.hashItems(items);
  }

  /// Hashes for every partition recorded in the current manifest.
  ///
  /// This is the baseline that [PartitionService.getDirtyPartitionIds]
  /// compares local partitions against. Empty before a manifest has been
  /// loaded or generated, which correctly reads as "nothing is known to be
  /// synced yet" and marks everything dirty.
  Map<String, String> get partitionHashes =>
      UnmodifiableMapView(_partitionHashes);

  /// Recompute the manifest's chunks from the live partition set and record
  /// their hashes as the new last-synced baseline.
  ///
  /// Call this after partitions have been uploaded and before the manifest
  /// itself is serialized, so the manifest that goes to Telegram describes
  /// what was actually just uploaded. Without it the stored hashes never
  /// advance, every partition stays dirty, and "incremental" sync re-uploads
  /// the entire metadata set on every run.
  void recordSyncedPartitions({
    required Iterable<MetadataPartition> partitions,
    required DateTime syncTime,
  }) {
    final chunks =
        partitions
            .map(
              (partition) => ManifestChunk(
                id: partition.id,
                count: partition.items.length,
                hash: partition.computeHash(),
              ),
            )
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));

    updateAfterSync(updatedChunks: chunks, syncTime: syncTime);
  }

  /// Check if a partition has changed since last sync.
  bool hasPartitionChanged(String partitionId, String currentHash) {
    final previousHash = _partitionHashes[partitionId];
    if (previousHash == null) return true;
    return previousHash != currentHash;
  }

  /// Update the manifest after a successful sync.
  ///
  /// The uploaded chunks are *merged* into the existing chunk set rather than
  /// replacing it: an incremental sync only uploads the dirty partitions, so
  /// a wholesale replacement would drop every unchanged partition from the
  /// manifest sent to Telegram and shrink [Manifest.totalMedia] to just the
  /// recently-changed items.
  void updateAfterSync({
    required List<ManifestChunk> updatedChunks,
    required DateTime syncTime,
  }) {
    if (_currentManifest == null) return;

    final chunksById = {for (final c in _currentManifest!.chunks) c.id: c};
    for (final chunk in updatedChunks) {
      chunksById[chunk.id] = chunk;
    }
    final merged = chunksById.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    _currentManifest = _currentManifest!.copyWith(
      lastSync: syncTime,
      chunks: merged,
      totalMedia: merged.fold<int>(0, (sum, c) => sum + c.count),
    );

    for (final chunk in updatedChunks) {
      _partitionHashes[chunk.id] = chunk.hash;
    }
    _persist();
  }

  /// Serialize the current manifest to JSON string.
  String? toJsonString() {
    return _currentManifest?.toJsonString();
  }

  /// Parse manifest from JSON string.
  Manifest? parseManifest(String jsonString) {
    return Manifest.fromJsonString(jsonString);
  }

  /// Persist the current manifest now (skipping any pending debounce).
  Future<void> saveNow() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    final store = this.store;
    final manifest = _currentManifest;
    if (store == null || manifest == null) return;
    await store.save(manifest);
  }

  /// Schedule a coalesced persist of the current manifest.
  void _persist() {
    final store = this.store;
    if (store == null) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(persistDebounce, () {
      _persistTimer = null;
      unawaited(saveNow());
    });
  }

  void dispose() {
    _persistTimer?.cancel();
    _persistTimer = null;
    _currentManifest = null;
    _partitionHashes.clear();
  }
}
