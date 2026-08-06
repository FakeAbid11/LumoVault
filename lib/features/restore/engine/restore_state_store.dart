import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persists the set of file hashes already restored so an interrupted
/// restore can resume (per PRD Section 10.4 differential restore) without
/// re-downloading thumbnails that were already fetched.
///
/// Writes are atomic: the JSON is written to a `.tmp` sibling file first,
/// then renamed over the real file, so a crash mid-write can never corrupt
/// the previously saved state.
class RestoreStateStore {
  RestoreStateStore({this.filePath});

  /// Overrides the state file location (tests). Defaults to a file in the
  /// app documents directory when null.
  final String? filePath;
  File? _cachedFile;

  /// The resolved state file, for tests that need to assert on disk state.
  @visibleForTesting
  File? get cachedFile => _cachedFile;

  Future<File> _file() async {
    final cached = _cachedFile;
    if (cached != null) return cached;
    final path = filePath;
    if (path != null) {
      final file = File(path);
      _cachedFile = file;
      return file;
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/lumovault_restore_state.json');
    _cachedFile = file;
    return file;
  }

  /// Load the persisted set of restored hashes.
  ///
  /// Returns an empty set when no state exists yet or the file is unreadable
  /// — a broken state file must never block a restore, it only costs a few
  /// redundant downloads.
  Future<Set<String>> load() async {
    final file = await _file();
    if (!await file.exists()) return {};
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return (json['hashes'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toSet();
    } catch (e) {
      debugPrint('[RestoreStateStore] Failed to load restore state: $e');
      return {};
    }
  }

  /// Atomically persist the given set of restored hashes.
  Future<void> save(Set<String> hashes) async {
    final file = await _file();
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({'hashes': hashes.toList()..sort()}),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  /// Delete any persisted restore state.
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }
}
