import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/gallery/data/repositories/gallery_repository.dart';

/// Aggregated diagnostics information about the app state.
class DiagnosticsInfo {
  const DiagnosticsInfo({
    required this.platform,
    required this.deviceModel,
    required this.osVersion,
    required this.totalMediaItems,
    required this.totalFolders,
    required this.uploadedCount,
    required this.pendingCount,
    required this.failedCount,
    required this.databasePath,
    required this.databaseSizeBytes,
    required this.cacheSizeBytes,
  });
  final String platform;
  final String deviceModel;
  final String osVersion;
  final int totalMediaItems;
  final int totalFolders;
  final int uploadedCount;
  final int pendingCount;
  final int failedCount;
  final String databasePath;
  final int databaseSizeBytes;
  final int cacheSizeBytes;

  Map<String, String> toMap() {
    return {
      'Platform': '$platform ($osVersion)',
      'Device': deviceModel,
      'Total Media': '$totalMediaItems',
      'Folders': '$totalFolders',
      'Uploaded': '$uploadedCount',
      'Pending': '$pendingCount',
      'Failed': '$failedCount',
      'Database Size': _formatBytes(databaseSizeBytes),
      'Cache Size': _formatBytes(cacheSizeBytes),
    };
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Collects diagnostics and version information.
class DiagnosticsService {
  DiagnosticsService({required this._galleryRepository});

  final GalleryRepository _galleryRepository;

  /// Collect all diagnostics information.
  Future<DiagnosticsInfo> collect() async {
    final deviceInfo = DeviceInfoPlugin();

    String platform;
    String deviceModel;
    String osVersion;

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      platform = 'Android';
      deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
      osVersion = androidInfo.version.release;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      platform = 'iOS';
      deviceModel = iosInfo.model;
      osVersion = iosInfo.systemVersion;
    } else {
      platform = Platform.operatingSystem;
      deviceModel = 'Unknown';
      osVersion = Platform.operatingSystemVersion;
    }

    final cacheDir = await getTemporaryDirectory();
    final cacheSize = await _getDirSize(cacheDir);

    final dbDir = await getApplicationDocumentsDirectory();
    final dbSize = await _getDirSize(dbDir);

    final items = _galleryRepository.mediaItems;
    final uploaded = items.where((m) => m.status.name == 'uploaded').length;
    final pending = items.where((m) => m.status.name == 'pending').length;
    final failed = items.where((m) => m.status.name == 'failed').length;

    return DiagnosticsInfo(
      platform: platform,
      deviceModel: deviceModel,
      osVersion: osVersion,
      totalMediaItems: items.length,
      totalFolders: _galleryRepository.folders.length,
      uploadedCount: uploaded,
      pendingCount: pending,
      failedCount: failed,
      databasePath: dbDir.path,
      databaseSizeBytes: dbSize,
      cacheSizeBytes: cacheSize,
    );
  }

  /// Export diagnostics to a log file.
  Future<String> exportLogs() async {
    final info = await collect();
    final buffer = StringBuffer();
    buffer.writeln('=== LumoVault Diagnostics ===');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln();

    for (final entry in info.toMap().entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }

    buffer.writeln();
    buffer.writeln('=== End Diagnostics ===');

    final logDir = await getApplicationDocumentsDirectory();
    final logFile = File(
      '${logDir.path}/diagnostics_${DateTime.now().millisecondsSinceEpoch}.txt',
    );
    await logFile.writeAsString(buffer.toString());

    return logFile.path;
  }

  Future<int> _getDirSize(Directory dir) async {
    if (!await dir.exists()) return 0;

    int totalBytes = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        totalBytes += await entity.length();
      }
    }
    return totalBytes;
  }
}
