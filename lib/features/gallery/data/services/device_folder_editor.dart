import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

/// Thin, injectable wrapper around [PhotoManager.editor] for device-folder
/// management (trash / move / copy). The plugin isn't unit-testable, so the
/// UI depends on this class rather than the static editor.
class DeviceFolderEditor {
  const DeviceFolderEditor();

  /// Moves [assets] to the system trash (Android shows its own consent
  /// dialog). Returns the ids that were actually trashed — empty when the
  /// user cancels.
  Future<List<String>> trashAssets(List<AssetEntity> assets) =>
      PhotoManager.editor.android.moveToTrash(assets);

  /// Moves [assets] to the folder identified by [targetPathId] (Android 11+
  /// shows one `createWriteRequest` consent for the batch; partial moves are
  /// possible — the call returns true if at least one file moved).
  Future<bool> moveAssets(
    List<AssetEntity> assets, {
    required String targetPathId,
  }) async {
    final target = await _findPath(targetPathId);
    if (target == null) return false;
    // moveAssetsToPath wants the exact RELATIVE_PATH; resolve it from the
    // path entity (the bucket display name is not a valid target).
    final targetRelativePath = await target.relativePathAsync;
    return PhotoManager.editor.android.moveAssetsToPath(
      entities: assets,
      targetPath: targetRelativePath ?? target.name,
    );
  }

  /// Copies [asset] into the folder identified by [targetPathId], returning
  /// the new (app-owned) copy. Returns null when the target folder no longer
  /// exists.
  Future<AssetEntity?> copyAsset(AssetEntity asset, String targetPathId) async {
    final target = await _findPath(targetPathId);
    if (target == null) return null;
    return PhotoManager.editor.copyAssetToPath(
      asset: asset,
      pathEntity: target,
    );
  }

  /// Path ids are only stable within a session — resolve by re-listing and
  /// matching rather than constructing an [AssetPathEntity] from a stale id.
  Future<AssetPathEntity?> _findPath(String pathId) async {
    final paths = await PhotoManager.getAssetPathList(type: RequestType.common);
    return paths.where((p) => p.id == pathId).firstOrNull;
  }
}

/// Provides the device-folder editor.
final deviceFolderEditorProvider = Provider<DeviceFolderEditor>(
  (ref) => const DeviceFolderEditor(),
);
