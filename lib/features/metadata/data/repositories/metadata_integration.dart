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
        _handleNewScanItem(item!);
        break;
      case 'favorite_toggle':
      case 'hidden_toggle':
      case 'archive_toggle':
        _handleStateChange(localId, operation, item);
        break;
      case 'trash':
        _handleTrash(localId, item);
        break;
      case 'restore':
        _handleRestore(localId, item);
        break;
      case 'upload_complete':
        break;
      default:
        debugPrint('[MetadataIntegration] Unknown operation: $operation');
    }
  }

  /// Handle newly discovered media item from scan.
  void _handleNewScanItem(MediaItem item) {
    metadataRepository.recordNewItem(item);
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

  /// Record upload completion (called by BackupEngine).
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
