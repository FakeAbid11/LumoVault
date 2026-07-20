import 'package:drift/drift.dart';

import '../../features/gallery/data/models/media_item.dart';
import 'app_database.dart';

/// Maps between the persisted [MediaItemRow] (drift) and the [MediaItem]
/// domain model.
///
/// These helpers exist so the follow-up step (rewiring [GalleryRepository]
/// onto the database) has a single, tested translation point rather than
/// scattering column-to-field logic across the repository.
extension MediaItemRowMapper on MediaItemRow {
  MediaItem toDomain() => MediaItem(
    id: id,
    localId: localId,
    fileHash: fileHash,
    telegramMessageId: telegramMessageId,
    telegramFileId: telegramFileId,
    filePath: filePath,
    fileName: fileName,
    mimeType: mimeType,
    fileSize: fileSize,
    width: width,
    height: height,
    durationMs: durationMs,
    createdAt: createdAt,
    modifiedAt: modifiedAt,
    scannedAt: scannedAt,
    uploadedAt: uploadedAt,
    backedUpAt: backedUpAt,
    status: MediaStatus.values[status],
    errorMessage: errorMessage,
    isFavorite: isFavorite,
    isHidden: isHidden,
    isArchived: isArchived,
    isTrashed: isTrashed,
    trashedAt: trashedAt,
    isExcluded: isExcluded,
    albumName: albumName,
    deviceFolder: deviceFolder,
    description: description,
    tags: tags,
    thumbnailPath: thumbnailPath,
  );
}

extension MediaItemToCompanion on MediaItem {
  /// Builds a drift companion for inserts/updates.
  ///
  /// When [id] is null (a freshly scanned item) the primary key is left absent
  /// so the database assigns one; otherwise it is included for upserts.
  MediaItemsCompanion toCompanion() => MediaItemsCompanion(
    id: id == null ? const Value.absent() : Value(id!),
    localId: Value(localId),
    fileHash: Value(fileHash),
    telegramMessageId: Value(telegramMessageId),
    telegramFileId: Value(telegramFileId),
    filePath: Value(filePath),
    fileName: Value(fileName),
    mimeType: Value(mimeType),
    fileSize: Value(fileSize),
    width: Value(width),
    height: Value(height),
    durationMs: Value(durationMs),
    createdAt: Value(createdAt),
    modifiedAt: Value(modifiedAt),
    scannedAt: Value(scannedAt),
    uploadedAt: Value(uploadedAt),
    backedUpAt: Value(backedUpAt),
    status: Value(status.index),
    errorMessage: Value(errorMessage),
    isFavorite: Value(isFavorite),
    isHidden: Value(isHidden),
    isArchived: Value(isArchived),
    isTrashed: Value(isTrashed),
    trashedAt: Value(trashedAt),
    isExcluded: Value(isExcluded),
    albumName: Value(albumName),
    deviceFolder: Value(deviceFolder),
    description: Value(description),
    tags: Value(tags),
    thumbnailPath: Value(thumbnailPath),
  );
}
