import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/database_constants.dart';
import '../../../../core/di/backup_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../core/storage/thumbnail_cache.dart';

/// Snapshot of everything the storage screens display.
class StorageUsage {
  const StorageUsage({
    required this.deviceMediaBytes,
    required this.deviceMediaCount,
    required this.telegramBytes,
    required this.telegramItemCount,
    required this.localCacheBytes,
    required this.thumbnailCacheBytes,
    required this.metadataBytes,
    required this.databaseBytes,
  });

  /// Total size of all photos/videos scanned on the device (backed up or not).
  final int deviceMediaBytes;

  /// Number of photos/videos scanned on the device.
  final int deviceMediaCount;

  /// Bytes backed up to Telegram (sum of uploaded file sizes).
  final int telegramBytes;

  /// Number of media items backed up to Telegram.
  final int telegramItemCount;

  /// Temp-directory size, excluding the thumbnail cache (which is reported
  /// separately so the two tiles never double-count the same files).
  final int localCacheBytes;

  /// Size of the thumbnail cache on disk.
  final int thumbnailCacheBytes;

  /// Combined size of the JSON metadata state files.
  final int metadataBytes;

  /// Size of the drift database file.
  final int databaseBytes;
}

/// Aggregates real storage usage for the Settings -> Storage screen.
///
/// Each source is measured independently and a failure in one (e.g. a plugin
/// channel missing in a test environment) degrades that component to 0 rather
/// than failing the whole screen.
final storageUsageProvider = FutureProvider.autoDispose<StorageUsage>((ref) {
  final stats = ref.watch(backupStatsProvider);
  final gallery = ref.watch(galleryRepositoryProvider);

  return _collect(
    deviceMediaBytes: gallery.totalSize,
    deviceMediaCount: gallery.totalCount,
    telegramBytes: stats.backedUpBytes,
    telegramItemCount: stats.backedUpCount,
  );
});

Future<StorageUsage> _collect({
  required int deviceMediaBytes,
  required int deviceMediaCount,
  required int telegramBytes,
  required int telegramItemCount,
}) async {
  final tempDir = await _safeGetTemporaryDirectory();
  final docsDir = await _safeGetDocumentsDirectory();

  final thumbnailCacheBytes = await _safe(() async {
    return ThumbnailCache.instance.getDiskCacheSize();
  });

  final localCacheBytes = await _safe(() async {
    final temp = tempDir;
    if (temp == null) return 0;
    final thumbnailDir = Directory(p.join(temp.path, 'thumbnails'));
    var total = 0;
    await for (final entity in temp.list(recursive: true)) {
      if (entity is File && !entity.path.startsWith(thumbnailDir.path)) {
        total += await entity.length();
      }
    }
    return total;
  });

  final metadataBytes = await _safe(() async {
    final docs = docsDir;
    if (docs == null) return 0;
    const files = [
      'metadata_partitions.json',
      'metadata_manifest.json',
      'sync_log.json',
      'transfer_queue.json',
    ];
    var total = 0;
    for (final name in files) {
      final file = File(p.join(docs.path, name));
      if (await file.exists()) {
        total += await file.length();
      }
    }
    return total;
  });

  final databaseBytes = await _safe(() async {
    final docs = docsDir;
    if (docs == null) return 0;
    final file = File(
      p.join(docs.path, '${DatabaseConstants.databaseName}.sqlite'),
    );
    if (await file.exists()) return file.length();
    return 0;
  });

  return StorageUsage(
    deviceMediaBytes: deviceMediaBytes,
    deviceMediaCount: deviceMediaCount,
    telegramBytes: telegramBytes,
    telegramItemCount: telegramItemCount,
    localCacheBytes: localCacheBytes ?? 0,
    thumbnailCacheBytes: thumbnailCacheBytes ?? 0,
    metadataBytes: metadataBytes ?? 0,
    databaseBytes: databaseBytes ?? 0,
  );
}

Future<T?> _safe<T>(Future<T> Function() action) async {
  try {
    return await action();
  } catch (e) {
    return null;
  }
}

Future<Directory?> _safeGetTemporaryDirectory() async {
  try {
    return await getTemporaryDirectory();
  } catch (_) {
    return null;
  }
}

Future<Directory?> _safeGetDocumentsDirectory() async {
  try {
    return await getApplicationDocumentsDirectory();
  } catch (_) {
    return null;
  }
}
