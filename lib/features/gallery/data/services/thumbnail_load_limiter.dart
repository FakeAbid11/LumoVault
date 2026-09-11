import 'dart:async';
import 'dart:collection';

/// Caps how many thumbnail loads run concurrently.
///
/// At scroll-top the grid builds a full viewport of tiles at once and each
/// fires a `thumbnailDataWithSize` platform-channel call simultaneously —
/// that burst is what stalls photo_manager into an infinite shimmer on the
/// newest sections (dark theme renders a stuck loading tile as background).
/// Requests queue here and complete in small batches instead.
class ThumbnailLoadLimiter {
  ThumbnailLoadLimiter({this.maxConcurrent = 6});

  final int maxConcurrent;

  int _active = 0;
  final _waiters = ListQueue<Completer<void>>();

  /// Runs [action], waiting for a free slot when [maxConcurrent] loads are
  /// already in flight. FIFO wake-up, one slot per completed load.
  Future<T> run<T>(Future<T> Function() action) async {
    while (_active >= maxConcurrent) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _active++;
    try {
      return await action();
    } finally {
      _active--;
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      }
    }
  }
}

/// Shared limiter for every gallery tile thumbnail load (local grid, cloud
/// grid) so their bursts share one budget.
final thumbnailLoadLimiter = ThumbnailLoadLimiter(maxConcurrent: 6);
