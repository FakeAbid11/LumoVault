import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../gallery/data/models/media_item.dart';

/// Metadata partition item representing a single media item's metadata
/// within a partition file.
class PartitionItem {
  const PartitionItem({
    required this.localId,
    required this.fileHash,
    this.telegramMessageId,
    this.telegramFileId,
    required this.createdAt,
    required this.modifiedAt,
    this.backedUpAt,
    this.mimeType,
    this.fileSize = 0,
    this.width = 0,
    this.height = 0,
    this.durationMs,
    this.isFavorite = false,
    this.isHidden = false,
    this.isArchived = false,
    this.isTrashed = false,
    this.trashedAt,
    this.albumName,
    this.deviceFolder,
    this.description,
    this.tags = const [],
    this.status = MediaStatus.pending,
    this.fileName,
  });

  /// Create from a MediaItem.
  factory PartitionItem.fromMediaItem(MediaItem item) {
    return PartitionItem(
      localId: item.localId,
      fileHash: item.fileHash,
      telegramMessageId: item.telegramMessageId,
      telegramFileId: item.telegramFileId,
      createdAt: item.createdAt,
      modifiedAt: item.modifiedAt,
      backedUpAt: item.backedUpAt,
      mimeType: item.mimeType,
      fileSize: item.fileSize,
      width: item.width,
      height: item.height,
      durationMs: item.durationMs,
      isFavorite: item.isFavorite,
      isHidden: item.isHidden,
      isArchived: item.isArchived,
      isTrashed: item.isTrashed,
      trashedAt: item.trashedAt,
      albumName: item.albumName,
      deviceFolder: item.deviceFolder,
      description: item.description,
      tags: item.tags,
      status: item.status,
      fileName: item.fileName,
    );
  }

  /// Deserialize from JSON.
  factory PartitionItem.fromJson(Map<String, dynamic> json) {
    return PartitionItem(
      localId: json['lid'] as String? ?? '',
      fileHash: json['h'] as String? ?? '',
      telegramMessageId: json['tmid'] as String?,
      telegramFileId: json['tfid'] as String?,
      createdAt:
          DateTime.tryParse(json['ct'] as String? ?? '') ??
          DateTime.now().toUtc(),
      modifiedAt:
          DateTime.tryParse(json['mod'] as String? ?? '') ??
          DateTime.now().toUtc(),
      backedUpAt: DateTime.tryParse(json['bu'] as String? ?? ''),
      mimeType: json['mime'] as String?,
      fileSize: (json['sz'] as num?)?.toInt() ?? 0,
      width: (json['w'] as num?)?.toInt() ?? 0,
      height: (json['ht'] as num?)?.toInt() ?? 0,
      durationMs: (json['d'] as num?)?.toInt(),
      isFavorite: json['fav'] as bool? ?? false,
      isHidden: json['hid'] as bool? ?? false,
      isArchived: json['arc'] as bool? ?? false,
      isTrashed: json['trash'] as bool? ?? false,
      trashedAt: DateTime.tryParse(json['trasht'] as String? ?? ''),
      albumName: json['alb'] as String?,
      deviceFolder: json['fol'] as String?,
      description: json['desc'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      status: MediaStatus.values[(json['st'] as int?) ?? 0],
      fileName: json['fn'] as String?,
    );
  }
  final String localId;
  final String fileHash;
  final String? telegramMessageId;
  final String? telegramFileId;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final DateTime? backedUpAt;
  final String? mimeType;
  final int fileSize;
  final int width;
  final int height;
  final int? durationMs;
  final bool isFavorite;
  final bool isHidden;
  final bool isArchived;
  final bool isTrashed;
  final DateTime? trashedAt;
  final String? albumName;
  final String? deviceFolder;
  final String? description;
  final List<String> tags;
  final MediaStatus status;
  final String? fileName;

  /// Create a copy with updated fields.
  PartitionItem copyWith({
    String? localId,
    String? fileHash,
    String? telegramMessageId,
    String? telegramFileId,
    DateTime? createdAt,
    DateTime? modifiedAt,
    DateTime? backedUpAt,
    String? mimeType,
    int? fileSize,
    int? width,
    int? height,
    int? durationMs,
    bool? isFavorite,
    bool? isHidden,
    bool? isArchived,
    bool? isTrashed,
    DateTime? trashedAt,
    String? albumName,
    String? deviceFolder,
    String? description,
    List<String>? tags,
    MediaStatus? status,
    String? fileName,
  }) {
    return PartitionItem(
      localId: localId ?? this.localId,
      fileHash: fileHash ?? this.fileHash,
      telegramMessageId: telegramMessageId ?? this.telegramMessageId,
      telegramFileId: telegramFileId ?? this.telegramFileId,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      backedUpAt: backedUpAt ?? this.backedUpAt,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      isFavorite: isFavorite ?? this.isFavorite,
      isHidden: isHidden ?? this.isHidden,
      isArchived: isArchived ?? this.isArchived,
      isTrashed: isTrashed ?? this.isTrashed,
      trashedAt: trashedAt ?? this.trashedAt,
      albumName: albumName ?? this.albumName,
      deviceFolder: deviceFolder ?? this.deviceFolder,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      status: status ?? this.status,
      fileName: fileName ?? this.fileName,
    );
  }

  /// Serialize to JSON.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'lid': localId,
      'h': fileHash,
      'ct': createdAt.toUtc().toIso8601String(),
      'mod': modifiedAt.toUtc().toIso8601String(),
    };
    if (fileName != null) map['fn'] = fileName;
    if (telegramMessageId != null) map['tmid'] = telegramMessageId;
    if (telegramFileId != null) map['tfid'] = telegramFileId;
    if (backedUpAt != null) map['bu'] = backedUpAt!.toUtc().toIso8601String();
    if (mimeType != null) map['mime'] = mimeType;
    if (fileSize > 0) map['sz'] = fileSize;
    if (width > 0) map['w'] = width;
    if (height > 0) map['ht'] = height;
    if (durationMs != null) map['d'] = durationMs;
    if (isFavorite) map['fav'] = true;
    if (isHidden) map['hid'] = true;
    if (isArchived) map['arc'] = true;
    if (isTrashed) map['trash'] = true;
    if (trashedAt != null) map['trasht'] = trashedAt!.toUtc().toIso8601String();
    if (albumName != null) map['alb'] = albumName;
    if (deviceFolder != null) map['fol'] = deviceFolder;
    if (description != null) map['desc'] = description;
    if (tags.isNotEmpty) map['tags'] = tags;
    map['st'] = status.index;
    return map;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PartitionItem &&
          runtimeType == other.runtimeType &&
          localId == other.localId &&
          fileHash == other.fileHash;

  @override
  int get hashCode => localId.hashCode ^ fileHash.hashCode;

  @override
  String toString() => 'PartitionItem(localId: $localId, fileHash: $fileHash)';
}

/// Metadata partition representing a time-bucketed group of media items.
///
/// Partitions are organized by year/month (YYYY/MM) for efficient
/// incremental sync. Only changed partitions need re-upload.
class MetadataPartition {
  const MetadataPartition({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    this.items = const [],
    required this.lastModified,
  });
  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<PartitionItem> items;
  final DateTime lastModified;

  /// Create partition key from a date (YYYY/MM format).
  static String partitionKeyFromDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}';
  }

  /// Parse partition key back to a DateTime (first day of month).
  static DateTime dateFromPartitionKey(String key) {
    final parts = key.split('/');
    final year = int.tryParse(parts[0]) ?? 2026;
    final month = int.tryParse(parts[1]) ?? 1;
    return DateTime(year, month);
  }

  /// Compute a deterministic hash of all items in this partition.
  /// Used to detect changes for incremental sync.
  String computeHash() {
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
    return sha256.convert(bytes).toString();
  }

  /// Check if this partition has changed since the given hash.
  bool hasChanged(String previousHash) {
    return computeHash() != previousHash;
  }

  /// Serialize to JSON for storage/upload.
  String toJsonString() {
    final map = {
      'id': id,
      'period_start': periodStart.toUtc().toIso8601String(),
      'period_end': periodEnd.toUtc().toIso8601String(),
      'last_modified': lastModified.toUtc().toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(),
    };
    return jsonEncode(map);
  }

  /// Deserialize from JSON string.
  static MetadataPartition? fromJsonString(String jsonString) {
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      return MetadataPartition(
        id: map['id'] as String? ?? '',
        periodStart:
            DateTime.tryParse(map['period_start'] as String? ?? '') ??
            DateTime.now().toUtc(),
        periodEnd:
            DateTime.tryParse(map['period_end'] as String? ?? '') ??
            DateTime.now().toUtc(),
        lastModified:
            DateTime.tryParse(map['last_modified'] as String? ?? '') ??
            DateTime.now().toUtc(),
        items:
            (map['items'] as List<dynamic>?)
                ?.map(
                  (item) =>
                      PartitionItem.fromJson(item as Map<String, dynamic>),
                )
                .toList() ??
            [],
      );
    } catch (e) {
      return null;
    }
  }

  /// Create a copy with updated fields.
  MetadataPartition copyWith({
    String? id,
    DateTime? periodStart,
    DateTime? periodEnd,
    List<PartitionItem>? items,
    DateTime? lastModified,
  }) {
    return MetadataPartition(
      id: id ?? this.id,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      items: items ?? this.items,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetadataPartition &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'MetadataPartition(id: $id, items: ${items.length}, '
      'modified: $lastModified)';
}
