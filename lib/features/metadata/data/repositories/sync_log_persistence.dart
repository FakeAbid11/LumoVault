import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/metadata_models.dart';

/// Storage contract for the metadata sync log.
///
/// Kept as an interface so [SyncService] can be constructed without any
/// platform plugins (unit tests, isolates) and still behave correctly — it
/// simply keeps the log in memory when no store is supplied.
abstract class SyncLogStore {
  /// Load previously persisted entries, oldest first.
  Future<List<SyncLogEntity>> load();

  /// Replace the persisted entries with [entries].
  Future<void> save(List<SyncLogEntity> entries);

  /// Drop all persisted entries.
  Future<void> clear();
}

/// JSON-file implementation of [SyncLogStore].
///
/// Entries live at `<app_documents>/sync_log.json`. This follows the same
/// approach as `TransferQueuePersistence` (see the v1 -> v2 note in
/// `AppDatabase.migration`): small append-mostly queues/logs are persisted as
/// JSON rather than as drift tables.
class FileSyncLogStore implements SyncLogStore {
  FileSyncLogStore({this.maxEntries = 1000});

  /// Newest [maxEntries] entries are kept; older ones are dropped on save.
  final int maxEntries;

  File? _file;

  Future<File> _resolveFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    return _file = File('${dir.path}/sync_log.json');
  }

  @override
  Future<List<SyncLogEntity>> load() async {
    try {
      final file = await _resolveFile();
      if (!await file.exists()) return const [];

      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) return const [];
      final version = data['version'] as int? ?? 0;
      if (version < 1) return const [];

      final entries = data['entries'] as List<dynamic>? ?? const [];
      return entries
          .whereType<Map<String, dynamic>>()
          .map(SyncLogEntity.fromJson)
          .toList();
    } catch (e) {
      debugPrint('[SyncLogStore] Failed to load: $e');
      return const [];
    }
  }

  @override
  Future<void> save(List<SyncLogEntity> entries) async {
    try {
      final file = await _resolveFile();
      final trimmed = entries.length > maxEntries
          ? entries.sublist(entries.length - maxEntries)
          : entries;

      // Temp+rename so a crash mid-write keeps the previous log instead of
      // leaving a truncated file that load() silently discards.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'entries': trimmed.map((e) => e.toJson()).toList(),
        }),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (e) {
      debugPrint('[SyncLogStore] Failed to save: $e');
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
      debugPrint('[SyncLogStore] Failed to clear: $e');
    }
  }
}
