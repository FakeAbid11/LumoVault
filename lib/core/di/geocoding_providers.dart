import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/gallery/data/repositories/geocoding_service.dart';

/// Singleton geocoding service.
final geocodingServiceProvider = Provider<GeocodingService>((ref) {
  return GeocodingService.instance;
});

/// Reverse-geocode a coordinate pair. Returns null if no result is found.
final reverseGeocodeProvider = FutureProvider.autoDispose
    .family<GeoResult?, (double, double)>((ref, coords) async {
      final service = ref.read(geocodingServiceProvider);
      return service.reverseGeocode(coords.$1, coords.$2);
    });
