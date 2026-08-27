import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Reverse geocoding result with city, state, and country.
class GeoResult {
  const GeoResult({this.city, this.state, this.country, this.countryCode});

  factory GeoResult.fromJson(Map<String, dynamic> json) => GeoResult(
    city: json['city'] as String?,
    state: json['state'] as String?,
    country: json['country'] as String?,
    countryCode: json['countryCode'] as String?,
  );

  final String? city;
  final String? state;
  final String? country;
  final String? countryCode;

  String get displayName {
    final parts = <String>[
      if (city != null && city!.isNotEmpty) city!,
      if (state != null && state!.isNotEmpty && state != city) state!,
      if (country != null && country!.isNotEmpty) country!,
    ];
    return parts.join(', ');
  }

  bool get isEmpty => displayName.isEmpty;

  Map<String, dynamic> toJson() => {
    if (city != null) 'city': city,
    if (state != null) 'state': state,
    if (country != null) 'country': country,
    if (countryCode != null) 'countryCode': countryCode,
  };
}

/// Reverse geocoding service using Nominatim (OpenStreetMap) with disk cache.
///
/// Results are cached to avoid repeated API calls. Rate-limited to 1 req/sec
/// per Nominatim's acceptable use policy.
class GeocodingService {
  GeocodingService._();

  static final GeocodingService instance = GeocodingService._();

  final Map<String, GeoResult?> _memoryCache = {};
  Map<String, GeoResult?>? _diskCache;
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  bool _initializing = false;

  static const _cacheFileName = 'geocoding_cache.json';
  static const _userAgent = 'LumoVault/1.0 (photo-backup-app)';

  String _key(double lat, double lng) =>
      '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';

  Future<void> _ensureDiskCache() async {
    if (_diskCache != null) return;
    if (_initializing) {
      while (_diskCache == null) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    _initializing = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_cacheFileName');
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _diskCache = json.map(
          (k, v) => MapEntry(
            k,
            v != null ? GeoResult.fromJson(v as Map<String, dynamic>) : null,
          ),
        );
      } else {
        _diskCache = {};
      }
    } catch (_) {
      _diskCache = {};
    } finally {
      _initializing = false;
    }
  }

  Future<void> _persistCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_cacheFileName');
      final json = _diskCache!.map((k, v) => MapEntry(k, v?.toJson()));
      await file.writeAsString(jsonEncode(json));
    } catch (_) {
      // Best-effort persistence.
    }
  }

  /// Reverse-geocode a coordinate pair. Returns null if no result is found
  /// or if the network request fails.
  Future<GeoResult?> reverseGeocode(double lat, double lng) async {
    final key = _key(lat, lng);

    // 1. Memory cache hit.
    if (_memoryCache.containsKey(key)) return _memoryCache[key];

    // 2. Disk cache hit.
    await _ensureDiskCache();
    if (_diskCache!.containsKey(key)) {
      final result = _diskCache![key];
      _memoryCache[key] = result;
      return result;
    }

    // 3. Rate-limit: 1 request per second.
    final now = DateTime.now();
    final elapsed = now.difference(_lastRequest).inMilliseconds;
    if (elapsed < 1000) {
      await Future<void>.delayed(Duration(milliseconds: 1000 - elapsed));
    }
    _lastRequest = DateTime.now();

    // 4. Nominatim API call.
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lng&format=json&zoom=10',
      );
      final client = HttpClient();
      client.userAgent = _userAgent;
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final address = json['address'] as Map<String, dynamic>?;

        if (address != null) {
          final result = GeoResult(
            city:
                address['city'] as String? ??
                address['town'] as String? ??
                address['village'] as String? ??
                address['hamlet'] as String? ??
                address['municipality'] as String?,
            state: address['state'] as String?,
            country: address['country'] as String?,
            countryCode: address['country_code'] as String?,
          );
          _memoryCache[key] = result;
          _diskCache![key] = result;
          await _persistCache();
          return result;
        }
      }

      // Cache null to avoid re-querying known-empty spots.
      _memoryCache[key] = null;
      _diskCache![key] = null;
      await _persistCache();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Clear all cached results.
  Future<void> clearCache() async {
    _memoryCache.clear();
    _diskCache?.clear();
    await _persistCache();
  }
}
