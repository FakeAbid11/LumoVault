import 'dart:convert';

import '../models/metadata_models.dart';

/// Service for generating, updating, and managing the manifest per PRD Section 6.4.
///
/// The manifest is stored as the pinned message in the private Telegram channel.
/// It provides a global view of all backed-up media and pointers to partitions.
class ManifestService {
  Manifest? _currentManifest;
  final Map<String, String> _partitionHashes = {};

  Manifest? getCurrentManifest() => _currentManifest;

  /// Set the current manifest (e.g., after fetching from Telegram).
  void setManifest(Manifest manifest) {
    _currentManifest = manifest;
    for (final chunk in manifest.chunks) {
      _partitionHashes[chunk.id] = chunk.hash;
    }
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
      _partitionHashes[entry.key] = hash;
    }

    chunks.sort((a, b) => a.id.compareTo(b.id));
    return chunks;
  }

  /// Compute a deterministic hash for a list of items.
  String _computePartitionHash(List<PartitionItem> items) {
    final buffer = StringBuffer();
    for (final item in items) {
      buffer.write(item.fileHash);
      buffer.write(item.modifiedAt.toUtc().toIso8601String());
      buffer.write(item.isFavorite ? '1' : '0');
      buffer.write(item.isHidden ? '1' : '0');
      buffer.write(item.isArchived ? '1' : '0');
      buffer.write(item.isTrashed ? '1' : '0');
    }
    final bytes = utf8.encode(buffer.toString());
    // Use a simple hash for now; crypto package provides sha256.
    return bytes.hashCode.toRadixString(16);
  }

  /// Check if a partition has changed since last sync.
  bool hasPartitionChanged(String partitionId, String currentHash) {
    final previousHash = _partitionHashes[partitionId];
    if (previousHash == null) return true;
    return previousHash != currentHash;
  }

  /// Update the manifest after a successful sync.
  void updateAfterSync({
    required List<ManifestChunk> updatedChunks,
    required DateTime syncTime,
  }) {
    if (_currentManifest == null) return;

    _currentManifest = _currentManifest!.copyWith(
      lastSync: syncTime,
      chunks: updatedChunks,
      totalMedia: updatedChunks.fold<int>(0, (sum, c) => sum + c.count),
    );

    for (final chunk in updatedChunks) {
      _partitionHashes[chunk.id] = chunk.hash;
    }
  }

  /// Serialize the current manifest to JSON string.
  String? toJsonString() {
    return _currentManifest?.toJsonString();
  }

  /// Parse manifest from JSON string.
  Manifest? parseManifest(String jsonString) {
    return Manifest.fromJsonString(jsonString);
  }

  void dispose() {
    _currentManifest = null;
    _partitionHashes.clear();
  }
}
