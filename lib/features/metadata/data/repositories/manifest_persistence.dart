import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/manifest.dart';

/// Storage contract for the current metadata manifest.
///
/// Kept as an interface so [ManifestService] can be constructed without any
/// platform plugins (unit tests, isolates) and still behave correctly — it
/// simply keeps the manifest in memory when no store is supplied.
abstract class ManifestStore {
  /// Load the previously persisted manifest, or null when none exists.
  Future<Manifest?> load();

  /// Replace the persisted manifest with [manifest].
  Future<void> save(Manifest manifest);

  /// Drop any persisted manifest.
  Future<void> clear();
}

/// JSON-file implementation of [ManifestStore].
///
/// The manifest lives at `<app_documents>/metadata_manifest.json`. This follows
/// the same approach as `FileSyncLogStore` (see the v1 -> v2 note in
/// `AppDatabase.migration`): small metadata state is persisted as JSON rather
/// than as drift tables. Persisting the manifest is what keeps the sync
/// baseline ([ManifestService.partitionHashes]) intact across restarts — without
/// it, every launch re-uploaded the user's entire metadata history.
class FileManifestStore implements ManifestStore {
  File? _file;

  Future<File> _resolveFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    return _file = File('${dir.path}/metadata_manifest.json');
  }

  @override
  Future<Manifest?> load() async {
    try {
      final file = await _resolveFile();
      if (!await file.exists()) return null;

      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) return null;
      if ((data['version'] as int? ?? 0) < 1) return null;

      final manifest = data['manifest'];
      if (manifest is! Map<String, dynamic>) return null;
      return Manifest.fromJsonString(jsonEncode(manifest));
    } catch (e) {
      debugPrint('[ManifestStore] Failed to load: $e');
      return null;
    }
  }

  @override
  Future<void> save(Manifest manifest) async {
    try {
      final file = await _resolveFile();
      final manifestMap = jsonDecode(manifest.toJsonString());
      // Temp+rename so a crash mid-write keeps the previous manifest (the
      // sync baseline) instead of leaving a truncated file that load()
      // discards — which would silently re-upload the full history.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'manifest': manifestMap,
        }),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (e) {
      debugPrint('[ManifestStore] Failed to save: $e');
      try {
        final file = await _resolveFile();
        final temp = File('${file.path}.tmp');
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // Non-critical: temp cleanup failure.
      }
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _resolveFile();
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[ManifestStore] Failed to clear: $e');
    }
  }
}
