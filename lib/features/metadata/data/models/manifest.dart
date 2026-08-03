import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Manifest entry per PRD Section 6.4.
///
/// Each chunk represents a partition of metadata (e.g., a month of media).
/// The hash is computed from all item hashes in the partition to detect changes.
class ManifestChunk {
  const ManifestChunk({
    required this.id,
    required this.count,
    required this.hash,
  });

  factory ManifestChunk.fromJson(Map<String, dynamic> json) {
    return ManifestChunk(
      id: json['id'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      hash: json['hash'] as String? ?? '',
    );
  }
  final String id;
  final int count;
  final String hash;

  ManifestChunk copyWith({String? id, int? count, String? hash}) {
    return ManifestChunk(
      id: id ?? this.id,
      count: count ?? this.count,
      hash: hash ?? this.hash,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'count': count, 'hash': hash};
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManifestChunk &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          count == other.count &&
          hash == other.hash;

  @override
  int get hashCode => id.hashCode ^ count.hashCode ^ hash.hashCode;

  @override
  String toString() => 'ManifestChunk(id: $id, count: $count, hash: $hash)';
}

/// Manifest per PRD Section 6.4.
///
/// Stored as the pinned message in the private Telegram channel.
/// Contains app identity, schema version, device info, summary counts,
/// and pointers to partitioned metadata files.
///
/// Schema:
/// ```json
/// {
///   "app": "lumovault",
///   "schema_version": 1,
///   "created": "2026-07-14T00:00:00Z",
///   "device_hash": "sha256_of_device_id",
///   "total_media": 15234,
///   "total_size_bytes": 107374182400,
///   "last_sync": "2026-07-14T12:00:00Z",
///   "chunks": [...]
/// }
/// ```
class Manifest {
  const Manifest({
    this.app = appName,
    this.schemaVersion = currentSchemaVersion,
    required this.created,
    required this.deviceHash,
    this.totalMedia = 0,
    this.totalSizeBytes = 0,
    required this.lastSync,
    this.chunks = const [],
  });

  /// Create a fresh manifest for a new device.
  factory Manifest.create({required String deviceHash}) {
    final now = DateTime.now().toUtc();
    return Manifest(created: now, deviceHash: deviceHash, lastSync: now);
  }
  final String app;
  final int schemaVersion;
  final DateTime created;
  final String deviceHash;
  final int totalMedia;
  final int totalSizeBytes;
  final DateTime lastSync;
  final List<ManifestChunk> chunks;

  static const int currentSchemaVersion = 1;
  static const String appName = 'lumovault';

  /// Compute a deterministic device hash from device info.
  static String computeDeviceHash(String deviceId) {
    final bytes = utf8.encode(deviceId);
    return sha256.convert(bytes).toString();
  }

  /// Serialize to JSON for Telegram channel description / pinned message.
  String toJsonString() {
    final map = {
      'app': app,
      'schema_version': schemaVersion,
      'created': created.toUtc().toIso8601String(),
      'device_hash': deviceHash,
      'total_media': totalMedia,
      'total_size_bytes': totalSizeBytes,
      'last_sync': lastSync.toUtc().toIso8601String(),
      'chunks': chunks.map((c) => c.toJson()).toList(),
    };
    return jsonEncode(map);
  }

  /// Deserialize from JSON string.
  static Manifest? fromJsonString(String jsonString) {
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      return Manifest(
        app: map['app'] as String? ?? appName,
        schemaVersion: map['schema_version'] as int? ?? 1,
        created:
            DateTime.tryParse(map['created'] as String? ?? '') ??
            DateTime.now().toUtc(),
        deviceHash: map['device_hash'] as String? ?? '',
        totalMedia: map['total_media'] as int? ?? 0,
        totalSizeBytes: map['total_size_bytes'] as int? ?? 0,
        lastSync:
            DateTime.tryParse(map['last_sync'] as String? ?? '') ??
            DateTime.now().toUtc(),
        chunks:
            (map['chunks'] as List<dynamic>?)
                ?.map((c) => ManifestChunk.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
      );
    } catch (e) {
      return null;
    }
  }

  /// Create a copy with updated fields.
  Manifest copyWith({
    String? app,
    int? schemaVersion,
    DateTime? created,
    String? deviceHash,
    int? totalMedia,
    int? totalSizeBytes,
    DateTime? lastSync,
    List<ManifestChunk>? chunks,
  }) {
    return Manifest(
      app: app ?? this.app,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      created: created ?? this.created,
      deviceHash: deviceHash ?? this.deviceHash,
      totalMedia: totalMedia ?? this.totalMedia,
      totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
      lastSync: lastSync ?? this.lastSync,
      chunks: chunks ?? this.chunks,
    );
  }

  /// Check if this manifest is compatible with the given schema version.
  bool isCompatibleWith(int targetVersion) {
    return schemaVersion <= targetVersion;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Manifest &&
          runtimeType == other.runtimeType &&
          schemaVersion == other.schemaVersion &&
          deviceHash == other.deviceHash &&
          totalMedia == other.totalMedia &&
          totalSizeBytes == other.totalSizeBytes;

  @override
  int get hashCode =>
      schemaVersion.hashCode ^
      deviceHash.hashCode ^
      totalMedia.hashCode ^
      totalSizeBytes.hashCode;

  @override
  String toString() =>
      'Manifest(schema: $schemaVersion, device: $deviceHash, '
      'media: $totalMedia, size: $totalSizeBytes, chunks: ${chunks.length})';
}
