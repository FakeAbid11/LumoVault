import 'package:flutter/foundation.dart';

import '../../../gallery/data/models/media_item.dart';
import '../../../gallery/data/repositories/gallery_repository.dart';
import '../models/metadata_models.dart';
import 'metadata_repository.dart';

/// Integration service connecting GalleryRepository with MetadataRepository.
///
/// Hooks metadata writes into GalleryRepository state changes without
/// creating a circular dependency. All metadata operations are
/// fire-and-forget from the user's perspective.
class MetadataIntegration {
  MetadataIntegration({required this.metadataRepository});

  final MetadataRepository metadataRepository;

  /// Wire up the GalleryRepository to trigger metadata updates.
  ///
  /// Call this once during app initialization.
  void connectGalleryRepository(GalleryRepository galleryRepository) {
    galleryRepository.setMetadataChangeCallback(_onMetadataChange);
  }

  /// Handle metadata changes from GalleryRepository.
  void _onMetadataChange({
    required String localId,
    required String operation,
    MediaItem? item,
  }) {
    switch (operation) {
      case 'scan_discover':
        _handleNewScanItem(item);
        break;
      case 'scan_update':
      case 'favorite_toggle':
      case 'hidden_toggle':
      case 'archive_toggle':
      case 'backup_exclusion_toggle':
        _handleStateChange(localId, operation, item);
        break;
      case 'trash':
        _handleTrash(localId, item);
        break;
      case 'restore':
        _handleRestore(localId, item);
        break;
      case 'scan_delete':
      case 'delete':
        _handleDeletion(localId, operation);
        break;
      // Emitted by GalleryRepository.markUploaded once a transfer completes.
      // The item carries the Telegram message/file IDs the upload produced,
      // which is exactly what recordUploadComplete needs — without them the
      // partition files and manifest would never learn where the media lives
      // on Telegram.
      case 'uploaded':
        if (item?.telegramMessageId != null && item?.telegramFileId != null) {
          recordUploadComplete(
            localId: localId,
            telegramMessageId: item!.telegramMessageId!,
            telegramFileId: item.telegramFileId!,
          );
        }
        break;
      default:
        debugPrint('[MetadataIntegration] Unknown operation: $operation');
    }
  }

  /// Handle newly discovered media item from scan.
  void _handleNewScanItem(MediaItem? item) {
    if (item == null) return;
    metadataRepository.recordNewItem(item);
  }

  /// Handle removal of an item (scan detected the file is gone, or the user
  /// permanently deleted it). Both emit with a null item, so the localId is
  /// all there is to work with.
  void _handleDeletion(String localId, String operation) {
    metadataRepository.recordDeletion(localId: localId, operation: operation);
  }

  /// Handle state changes (favorite, hidden, archived).
  void _handleStateChange(String localId, String operation, MediaItem? item) {
    if (item == null) return;

    final partitionItem = PartitionItem.fromMediaItem(item);
    metadataRepository.recordStateChange(
      localId: localId,
      operation: operation,
      updatedItem: partitionItem,
    );
  }

  /// Handle trash operation.
  void _handleTrash(String localId, MediaItem? item) {
    metadataRepository.recordStateChange(
      localId: localId,
      operation: 'trash',
      updatedItem: item != null ? PartitionItem.fromMediaItem(item) : null,
    );
  }

  /// Handle restore from trash.
  void _handleRestore(String localId, MediaItem? item) {
    if (item == null) return;

    final partitionItem = PartitionItem.fromMediaItem(item);
    metadataRepository.recordStateChange(
      localId: localId,
      operation: 'restore',
      updatedItem: partitionItem,
    );
  }

  /// Record upload completion (called when the gallery reports an upload).
  ///
  /// BackupEngine uploads through GalleryRepository.markUploaded, which emits
  /// the 'uploaded' change with the item carrying its Telegram message/file
  /// IDs; [MetadataIntegration] forwards them here so the metadata layer stays
  /// in sync with where the media actually lives on Telegram.
  void recordUploadComplete({
    required String localId,
    required String telegramMessageId,
    required String telegramFileId,
  }) {
    metadataRepository.recordUploadComplete(
      localId: localId,
      telegramMessageId: telegramMessageId,
      telegramFileId: telegramFileId,
    );
  }
}
