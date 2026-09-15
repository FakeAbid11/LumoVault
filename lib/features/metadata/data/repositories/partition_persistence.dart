import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/metadata_partition.dart';

/// Storage contract for the metadata partition set.
///
/// Kept as an interface so [PartitionService] can be constructed without any
/// platform plugins (unit tests, isolates) and still behave correctly — it
/// simply keeps partitions in memory when no store is supplied.
abstract class PartitionStore {
  /// Load previously persisted partitions.
  Future<List<MetadataPartition>> load();

  /// Replace the persisted set with [partitions].
  Future<void> save(List<MetadataPartition> partitions);

  /// Drop all persisted partitions.
  Future<void> clear();
}

/// JSON-file implementation of [PartitionStore].
///
/// Partitions live at `<app_documents>/metadata_partitions.json`. This follows
/// the same approach as `FileSyncLogStore` (see the v1 -> v2 note in
/// `AppDatabase.migration`): small metadata state is persisted as JSON rather
/// than as drift tables. Persisting partitions is what lets
/// [PartitionService.getAllPartitions] — and therefore the metadata repository's
/// layer-1 hydration — survive app restarts.
class FilePartitionStore implements PartitionStore {
  File? _file;

  Future<File> _resolveFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    return _file = File('${dir.path}/metadata_partitions.json');
  }

  @override
  Future<List<MetadataPartition>> load() async {
    try {
      final file = await _resolveFile();
      if (!await file.exists()) return const [];

      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) return const [];
      if ((data['version'] as int? ?? 0) < 1) return const [];

      final partitions = data['partitions'] as List<dynamic>? ?? const [];
      return partitions
          .whereType<Map<String, dynamic>>()
          .map((p) => MetadataPartition.fromJsonString(jsonEncode(p)))
          .whereType<MetadataPartition>()
          .toList();
    } catch (e) {
      debugPrint('[PartitionStore] Failed to load: $e');
      return const [];
    }
  }

  @override
  Future<void> save(List<MetadataPartition> partitions) async {
    try {
      final file = await _resolveFile();
      // Temp+rename so a crash mid-write leaves the previous partition set
      // intact instead of a truncated file that load() silently discards.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'partitions': partitions
              .map((p) => jsonDecode(p.toJsonString()))
              .toList(),
        }),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (e) {
      debugPrint('[PartitionStore] Failed to save: $e');
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
      debugPrint('[PartitionStore] Failed to clear: $e');
    }
  }
}
