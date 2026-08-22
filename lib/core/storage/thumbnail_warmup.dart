import 'package:photo_manager/photo_manager.dart';

import '../constants/app_constants.dart';
import 'thumbnail_cache.dart';

/// Pre-warms the thumbnail cache during scans, fire-and-forget.
///
/// Timeline tiles consult [ThumbnailCache] first, so the fastest way to get a
/// grid of real thumbnails after a scan is to populate it while scanning
/// rather than making each tile generate its own thumbnail on first paint.
/// Work is capped at [_maxConcurrent] concurrent photo_manager thumbnail
/// calls — decoding 300×300 JPEGs for a whole library is cheap but not free,
/// and a scan that's also hashing files shouldn't contend with unbounded
/// decode work for thumbnails nobody has scrolled to yet.
class ThumbnailWarmup {
  ThumbnailWarmup._();

  static const int _maxConcurrent = 4;
  static final _queue = <Future<void> Function()>[];
  static int _active = 0;
  static bool _initialized = false;

  /// Schedule [asset]'s thumbnail to be decoded and cached under [asset.id].
  /// Safe to call from any isolate; failures are swallowed (warmup is
  /// best-effort — a miss just means the tile regenerates on demand).
  static void schedule(AssetEntity asset) {
    Future<void> job() async {
      try {
        if (!_initialized) {
          await ThumbnailCache.instance.initialize();
          _initialized = true;
        }
        final bytes = await asset.thumbnailDataWithSize(
          const ThumbnailSize(
            AppConstants.thumbnailPixelSize,
            AppConstants.thumbnailPixelSize,
          ),
        );
        if (bytes != null) {
          await ThumbnailCache.instance.put(asset.id, bytes);
        }
      } catch (_) {
        // Best-effort: a failed warmup only costs the on-demand regenerate.
      }
    }

    if (_active < _maxConcurrent) {
      _active++;
      job().whenComplete(_finish);
    } else {
      _queue.add(job);
    }
  }

  static void _finish() {
    _active--;
    while (_active < _maxConcurrent && _queue.isNotEmpty) {
      _active++;
      _queue.removeAt(0)().whenComplete(_finish);
    }
  }
}
