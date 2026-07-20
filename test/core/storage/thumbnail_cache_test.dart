import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/storage/thumbnail_cache.dart';

void main() {
  group('ThumbnailCache', () {
    late ThumbnailCache cache;

    setUp(() {
      cache = ThumbnailCache.instance;
    });

    test('instance is singleton', () {
      final a = ThumbnailCache.instance;
      final b = ThumbnailCache.instance;
      expect(identical(a, b), isTrue);
    });

    test('get returns null for non-existent key', () async {
      // Without initialize(), the cache dir is null.
      // get() should handle this gracefully.
      final result = await cache.get('nonexistent');
      expect(result, isNull);
    });

    test('contains returns false for non-existent key', () async {
      final result = await cache.contains('nonexistent');
      expect(result, isFalse);
    });

    test('remove does not throw for non-existent key', () async {
      // Should not throw.
      await cache.remove('nonexistent');
    });

    test('clear does not throw on empty cache', () async {
      // Should not throw.
      await cache.clear();
    });

    test('getDiskCacheSize returns 0 when not initialized', () async {
      final size = await cache.getDiskCacheSize();
      expect(size, equals(0));
    });

    test('getDiskCacheCount returns 0 when not initialized', () async {
      final count = await cache.getDiskCacheCount();
      expect(count, equals(0));
    });

    test('evictIfOverSize does not throw when not initialized', () async {
      // Should not throw.
      await cache.evictIfOverSize(maxSizeBytes: 1024);
    });
  });

  group('ThumbnailCache memory management', () {
    test('LinkedHashMap maintains insertion order for LRU', () {
      final cache = <String, int>{};

      cache['a'] = 1;
      cache['b'] = 2;
      cache['c'] = 3;

      // Access 'a' to make it most recently used.
      cache.remove('a');
      cache['a'] = 1;

      // Now 'b' is the oldest.
      expect(cache.keys.first, equals('b'));
    });
  });
}
