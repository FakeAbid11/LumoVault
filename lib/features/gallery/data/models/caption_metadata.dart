import 'dart:convert';

class CaptionMetadata {
  const CaptionMetadata({
    required this.mediaItemId,
    required this.fileHash,
    required this.createdAt,
    required this.modifiedAt,
    required this.backedUpAt,
    this.mimeType,
    this.fileSize = 0,
    this.width = 0,
    this.height = 0,
    this.durationMs,
    this.isFavorite = false,
    this.isHidden = false,
    this.isArchived = false,
    this.albumName,
    this.deviceFolder,
    this.description,
    this.tags = const [],
    this.customFields,
  });

  /// Deserialize from a Telegram message caption string.
  factory CaptionMetadata.fromCaptionString(String caption) {
    try {
      final map = jsonDecode(caption) as Map<String, dynamic>;
      return CaptionMetadata(
        mediaItemId: map['mid'] as String? ?? '',
        fileHash: map['h'] as String? ?? '',
        createdAt:
            DateTime.tryParse(map['ct'] as String? ?? '') ?? DateTime.now(),
        modifiedAt:
            DateTime.tryParse(map['mod'] as String? ?? '') ?? DateTime.now(),
        backedUpAt:
            DateTime.tryParse(map['bu'] as String? ?? '') ?? DateTime.now(),
        mimeType: map['mime'] as String?,
        fileSize: (map['sz'] as num?)?.toInt() ?? 0,
        width: (map['w'] as num?)?.toInt() ?? 0,
        height: (map['ht'] as num?)?.toInt() ?? 0,
        durationMs: (map['d'] as num?)?.toInt(),
        isFavorite: map['fav'] as bool? ?? false,
        isHidden: map['hid'] as bool? ?? false,
        isArchived: map['arc'] as bool? ?? false,
        albumName: map['alb'] as String?,
        deviceFolder: map['fol'] as String?,
        description: map['desc'] as String?,
        tags: (map['tags'] as List<dynamic>?)?.cast<String>() ?? [],
        customFields: map['x'] as Map<String, dynamic>?,
      );
    } catch (e) {
      return CaptionMetadata(
        mediaItemId: '',
        fileHash: '',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        backedUpAt: DateTime.now(),
      );
    }
  }
  final String mediaItemId;
  final String fileHash;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final DateTime backedUpAt;
  final String? mimeType;
  final int fileSize;
  final int width;
  final int height;
  final int? durationMs;
  final bool isFavorite;
  final bool isHidden;
  final bool isArchived;
  final String? albumName;
  final String? deviceFolder;
  final String? description;
  final List<String> tags;
  final Map<String, dynamic>? customFields;

  /// Serialize to JSON for Telegram message caption.
  String toCaptionString() {
    final map = <String, dynamic>{
      'v': '1',
      'mid': mediaItemId,
      'h': fileHash,
      'ct': createdAt.toUtc().toIso8601String(),
      'mod': modifiedAt.toUtc().toIso8601String(),
      'bu': backedUpAt.toUtc().toIso8601String(),
    };
    if (mimeType != null) map['mime'] = mimeType;
    if (fileSize > 0) map['sz'] = fileSize;
    if (width > 0) map['w'] = width;
    if (height > 0) map['ht'] = height;
    if (durationMs != null) map['d'] = durationMs;
    if (isFavorite) map['fav'] = true;
    if (isHidden) map['hid'] = true;
    if (isArchived) map['arc'] = true;
    if (albumName != null) map['alb'] = albumName;
    if (deviceFolder != null) map['fol'] = deviceFolder;
    if (description != null) map['desc'] = description;
    if (tags.isNotEmpty) map['tags'] = tags;
    if (customFields != null && customFields!.isNotEmpty) {
      map['x'] = customFields;
    }
    return jsonEncode(map);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CaptionMetadata &&
          runtimeType == other.runtimeType &&
          mediaItemId == other.mediaItemId &&
          fileHash == other.fileHash;

  @override
  int get hashCode => mediaItemId.hashCode ^ fileHash.hashCode;
}
