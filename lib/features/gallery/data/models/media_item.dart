enum MediaStatus { pending, uploading, uploaded, failed, excluded }

enum MediaType { image, video, unknown }

class MediaItem {
  const MediaItem({
    this.id,
    required this.localId,
    required this.fileHash,
    this.telegramMessageId,
    this.telegramFileId,
    required this.filePath,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.width,
    required this.height,
    this.durationMs,
    required this.createdAt,
    required this.modifiedAt,
    required this.scannedAt,
    this.uploadedAt,
    this.backedUpAt,
    this.status = MediaStatus.pending,
    this.errorMessage,
    this.isFavorite = false,
    this.isHidden = false,
    this.isArchived = false,
    this.isTrashed = false,
    this.trashedAt,
    this.isExcluded = false,
    this.albumName,
    this.deviceFolder,
    this.description,
    this.tags = const [],
    this.thumbnailPath,
  });
  final int? id;
  final String localId;
  final String fileHash;
  final String? telegramMessageId;
  final String? telegramFileId;
  final String filePath;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final int width;
  final int height;
  final int? durationMs;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final DateTime scannedAt;
  final DateTime? uploadedAt;
  final DateTime? backedUpAt;
  final MediaStatus status;
  final String? errorMessage;
  final bool isFavorite;
  final bool isHidden;
  final bool isArchived;
  final bool isTrashed;
  final DateTime? trashedAt;
  final bool isExcluded;
  final String? albumName;
  final String? deviceFolder;
  final String? description;
  final List<String> tags;
  final String? thumbnailPath;

  MediaType get mediaType {
    if (mimeType.startsWith('image/')) return MediaType.image;
    if (mimeType.startsWith('video/')) return MediaType.video;
    return MediaType.unknown;
  }

  bool get isVideo => mediaType == MediaType.video;

  MediaItem copyWith({
    int? id,
    String? localId,
    String? fileHash,
    String? telegramMessageId,
    String? telegramFileId,
    String? filePath,
    String? fileName,
    String? mimeType,
    int? fileSize,
    int? width,
    int? height,
    int? durationMs,
    DateTime? createdAt,
    DateTime? modifiedAt,
    DateTime? scannedAt,
    DateTime? uploadedAt,
    DateTime? backedUpAt,
    MediaStatus? status,
    String? errorMessage,
    bool? isFavorite,
    bool? isHidden,
    bool? isArchived,
    bool? isTrashed,
    DateTime? trashedAt,
    bool clearTrashedAt = false,
    bool? isExcluded,
    String? albumName,
    String? deviceFolder,
    String? description,
    List<String>? tags,
    String? thumbnailPath,
  }) {
    return MediaItem(
      id: id ?? this.id,
      localId: localId ?? this.localId,
      fileHash: fileHash ?? this.fileHash,
      telegramMessageId: telegramMessageId ?? this.telegramMessageId,
      telegramFileId: telegramFileId ?? this.telegramFileId,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      scannedAt: scannedAt ?? this.scannedAt,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      backedUpAt: backedUpAt ?? this.backedUpAt,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      isFavorite: isFavorite ?? this.isFavorite,
      isHidden: isHidden ?? this.isHidden,
      isArchived: isArchived ?? this.isArchived,
      isTrashed: isTrashed ?? this.isTrashed,
      trashedAt: clearTrashedAt ? null : (trashedAt ?? this.trashedAt),
      isExcluded: isExcluded ?? this.isExcluded,
      albumName: albumName ?? this.albumName,
      deviceFolder: deviceFolder ?? this.deviceFolder,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaItem &&
          runtimeType == other.runtimeType &&
          localId == other.localId &&
          fileHash == other.fileHash;

  @override
  int get hashCode => localId.hashCode ^ fileHash.hashCode;
}
