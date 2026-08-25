import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

/// Saves photos and videos to the device gallery with full metadata.
///
/// Uses [PhotoManager.editor] to create new assets in the gallery,
/// preserving creation timestamps, GPS coordinates, and file data.
class GallerySaveService {
  /// Save an image file to the device gallery.
  ///
  /// Returns the saved [AssetEntity] on success, or `null` on failure.
  Future<AssetEntity?> saveImage({
    required File file,
    DateTime? createdAt,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;

      final filename =
          'lumo_${DateTime.now().millisecondsSinceEpoch}${_extension(file.path)}';

      return await PhotoManager.editor.saveImage(
        bytes,
        filename: filename,
        relativePath: 'Pictures/LumoVault',
        latitude: latitude,
        longitude: longitude,
        creationDate: createdAt,
      );
    } catch (e) {
      debugPrint('[GallerySaveService] Failed to save image: $e');
      return null;
    }
  }

  /// Save a video file to the device gallery.
  ///
  /// Returns the saved [AssetEntity] on success, or `null` on failure.
  Future<AssetEntity?> saveVideo({
    required File file,
    DateTime? createdAt,
    double? latitude,
    double? longitude,
  }) async {
    try {
      return await PhotoManager.editor.saveVideo(
        file,
        relativePath: 'Pictures/LumoVault',
        latitude: latitude,
        longitude: longitude,
        creationDate: createdAt,
      );
    } catch (e) {
      debugPrint('[GallerySaveService] Failed to save video: $e');
      return null;
    }
  }

  String _extension(String path) {
    final dotIndex = path.lastIndexOf('.');
    return dotIndex >= 0 ? path.substring(dotIndex) : '.jpg';
  }
}
