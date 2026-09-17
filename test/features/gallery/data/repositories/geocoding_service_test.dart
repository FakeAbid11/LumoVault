import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/repositories/geocoding_service.dart';

/// Records every call so the cache and rate-limiter decisions are observable
/// without touching the network.
class _FakeGeocodingHttpClient implements GeocodingHttpClient {
  final List<Uri> calls = [];
  final List<DateTime> callTimes = [];

  int statusCode = 200;
  String body = '{}';
  Object? error;

  @override
  Future<({int statusCode, String body})> get(
    Uri uri, {
    required String userAgent,
  }) async {
    calls.add(uri);
    callTimes.add(DateTime.now());
    if (error != null) {
      throw error!;
    }
    return (statusCode: statusCode, body: body);
  }
}

const _emptyAddressBody = '{"lat":"1.0","lon":"1.0"}';
const _parisBody =
    '{"address":{"city":"Paris","state":"Île-de-France",'
    '"country":"France","country_code":"fr"}}';

void main() {
  // path_provider needs a binding for the cache directory; the load falls
  // back to an empty in-memory map either way, but without this the log is
  // noise on every call.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GeocodingService caching', () {
    test('a server error is not negative-cached', () async {
      final client = _FakeGeocodingHttpClient()..statusCode = 500;
      final service = GeocodingService(httpClient: client);

      expect(await service.reverseGeocode(48.85, 2.35), isNull);
      expect(await service.reverseGeocode(48.85, 2.35), isNull);

      // A 500 used to be cached forever: the spot stayed blank and the only
      // recovery was clearCache. A transient failure must be retried.
      expect(client.calls.length, 2);
    });

    test('a thrown error is not negative-cached', () async {
      final client = _FakeGeocodingHttpClient()
        ..error = StateError('socket closed');
      final service = GeocodingService(httpClient: client);

      expect(await service.reverseGeocode(48.85, 2.35), isNull);
      expect(await service.reverseGeocode(48.85, 2.35), isNull);
      expect(client.calls.length, 2);
    });

    test('a genuinely-empty 200 is cached', () async {
      final client = _FakeGeocodingHttpClient()..body = _emptyAddressBody;
      final service = GeocodingService(httpClient: client);

      expect(await service.reverseGeocode(0, 0), isNull);
      expect(await service.reverseGeocode(0, 0), isNull);

      // Open water should not be re-queried on every map pan.
      expect(client.calls.length, 1);
    });

    test('a real result is cached and returned', () async {
      final client = _FakeGeocodingHttpClient()..body = _parisBody;
      final service = GeocodingService(httpClient: client);

      final first = await service.reverseGeocode(48.85, 2.35);
      expect(first?.city, 'Paris');
      expect(first?.country, 'France');

      final second = await service.reverseGeocode(48.85, 2.35);
      expect(second?.city, 'Paris');
      expect(client.calls.length, 1);
    });
  });

  group('GeocodingService rate limiting', () {
    test('concurrent lookups serialize to 1 request per second', () async {
      final client = _FakeGeocodingHttpClient()..body = _emptyAddressBody;
      final service = GeocodingService(httpClient: client);

      // Fire all three at once: before the limiter was chained they read the
      // same _lastRequest and departed inside a single second.
      await Future.wait([
        service.reverseGeocode(10, 10),
        service.reverseGeocode(20, 20),
        service.reverseGeocode(30, 30),
      ]);

      expect(client.callTimes.length, 3);
      for (var i = 1; i < client.callTimes.length; i++) {
        final gap = client.callTimes[i].difference(client.callTimes[i - 1]);
        expect(
          gap.inMilliseconds,
          greaterThanOrEqualTo(900),
          reason: 'requests must be spread at least ~1s apart',
        );
      }
    });
  });
}
