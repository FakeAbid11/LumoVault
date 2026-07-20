import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/app_constants.dart';

/// Manages on-disk and in-memory thumbnail caching.
///
/// Thumbnails are stored at `<app_cache>/thumbnails/<mediaItemId>.jpg`
/// LRU eviction is applied for both disk and memory caches.
class ThumbnailCache {
  ThumbnailCache._();

  static ThumbnailCache? _instance;
  static ThumbnailCache get instance => _instance ??= ThumbnailCache._();

  Directory? _cacheDir;
  final _memoryCache = <String, Uint8List>{};
  int _currentMemoryBytes = 0;
  static const int _maxMemoryBytes =
      AppConstants.thumbnailCacheSizeMB * 1024 * 1024 ~/ 4; // ~25% for memory

  /// Initialize the cache directory.
  Future<void> initialize() async {
    final cacheDir = await getTemporaryDirectory();
    _cacheDir = Directory('${cacheDir.path}/thumbnails');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
  }

  /// Get a cached thumbnail by media item ID.
  ///
  /// Returns the image bytes if cached (memory or disk), null otherwise.
  Future<Uint8List?> get(String mediaItemId) async {
    // Check memory cache first.
    final memBytes = _memoryCache[mediaItemId];
    if (memBytes != null) {
      // Move to end (most recently used).
      _memoryCache.remove(mediaItemId);
      _memoryCache[mediaItemId] = memBytes;
      return memBytes;
    }

    // Check disk cache.
    if (_cacheDir == null) return null;
    final file = _fileFor(mediaItemId);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      _addToMemoryCache(mediaItemId, bytes);
      return bytes;
    }

    return null;
  }

  /// Store a thumbnail in the cache.
  Future<void> put(String mediaItemId, Uint8List bytes) async {
    // Write to disk.
    final file = _fileFor(mediaItemId);
    await file.writeAsBytes(bytes, flush: true);

    // Add to memory cache.
    _addToMemoryCache(mediaItemId, bytes);
  }

  /// Check if a thumbnail is cached.
  Future<bool> contains(String mediaItemId) async {
    if (_memoryCache.containsKey(mediaItemId)) return true;
    if (_cacheDir == null) return false;
    return _fileFor(mediaItemId).exists();
  }

  /// Remove a specific thumbnail from the cache.
  Future<void> remove(String mediaItemId) async {
    _memoryCache.remove(mediaItemId);
    _recalcMemoryUsage();

    if (_cacheDir == null) return;
    final file = _fileFor(mediaItemId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Clear all cached thumbnails.
  Future<void> clear() async {
    _memoryCache.clear();
    _currentMemoryBytes = 0;

    if (_cacheDir != null && await _cacheDir!.exists()) {
      await _cacheDir!.delete(recursive: true);
      await _cacheDir!.create(recursive: true);
    }
  }

  /// Get total disk cache size in bytes.
  Future<int> getDiskCacheSize() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;

    int totalBytes = 0;
    await for (final entity in _cacheDir!.list()) {
      if (entity is File) {
        totalBytes += await entity.length();
      }
    }
    return totalBytes;
  }

  /// Get number of cached thumbnails.
  Future<int> getDiskCacheCount() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;

    int count = 0;
    await for (final entity in _cacheDir!.list()) {
      if (entity is File) count++;
    }
    return count;
  }

  /// Evict oldest entries if disk cache exceeds [maxSizeBytes].
  Future<void> evictIfOverSize({int? maxSizeBytes}) async {
    final maxSize =
        maxSizeBytes ?? AppConstants.thumbnailCacheSizeMB * 1024 * 1024;

    final currentSize = await getDiskCacheSize();
    if (currentSize <= maxSize) return;

    // Collect all files with their modified times.
    final files = <_CacheEntry>[];
    await for (final entity in _cacheDir!.list()) {
      if (entity is File) {
        final stat = await entity.stat();
        files.add(_CacheEntry(entity, stat.modified));
      }
    }

    // Sort by access time (oldest first).
    files.sort((a, b) => a.modified.compareTo(b.modified));

    // Delete oldest until under limit.
    var freedBytes = 0;
    for (final entry in files) {
      if (currentSize - freedBytes <= maxSize) break;
      final size = await entry.file.length();
      await entry.file.delete();
      freedBytes += size;

      // Also remove from memory cache.
      final name = entry.file.path.split('/').last.replaceAll('.jpg', '');
      _memoryCache.remove(name);
    }

    _recalcMemoryUsage();
  }

  File _fileFor(String mediaItemId) {
    return File('${_cacheDir!.path}/$mediaItemId.jpg');
  }

  void _addToMemoryCache(String key, Uint8List bytes) {
    _memoryCache.remove(key);
    _memoryCache[key] = bytes;
    _currentMemoryBytes += bytes.length;

    // Evict LRU entries if over memory limit.
    while (_currentMemoryBytes > _maxMemoryBytes && _memoryCache.length > 1) {
      final oldest = _memoryCache.keys.first;
      final removed = _memoryCache.remove(oldest)!;
      _currentMemoryBytes -= removed.length;
    }
  }

  void _recalcMemoryUsage() {
    _currentMemoryBytes = 0;
    for (final bytes in _memoryCache.values) {
      _currentMemoryBytes += bytes.length;
    }
  }
}

class _CacheEntry {
  _CacheEntry(this.file, this.modified);
  final File file;
  final DateTime modified;
}
