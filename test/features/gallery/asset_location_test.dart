import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/repositories/asset_location.dart';
import 'package:photo_manager/photo_manager.dart';

/// A plain [AssetEntity] data holder — no platform calls are made, since
/// [resolveAssetLocations] only reads its synchronous fields (id, type,
/// dimensions) and takes coordinates from the injected reader.
AssetEntity _asset(String id, {int typeInt = 1}) =>
    AssetEntity(id: id, typeInt: typeInt, width: 100, height: 100);

void main() {
  group('resolveAssetLocations', () {
    test('returns a lite MediaItem only for assets that have a fix', () async {
      final coords = <String, (double?, double?)>{
        'a': (37.7749, -122.4194),
        'b': (null, null), // no fix
        'c': (51.5074, -0.1278),
      };

      final result = await resolveAssetLocations([
        _asset('a'),
        _asset('b'),
        _asset('c'),
      ], reader: (asset) async => coords[asset.id] ?? (null, null));

      expect(result.map((i) => i.localId).toSet(), {'a', 'c'});
      final a = result.firstWhere((i) => i.localId == 'a');
      expect(a.hasLocation, isTrue);
      expect(a.latitude, 37.7749);
      expect(a.longitude, -122.4194);
      // Lite item: no hash, no file — the map derives thumbnails from the id.
      expect(a.fileHash, isEmpty);
      expect(a.filePath, isEmpty);
    });

    test('carries media type through so the map can flag videos', () async {
      final result = await resolveAssetLocations([
        _asset('vid', typeInt: 2),
      ], reader: (_) async => (10.0, 20.0));

      expect(result.single.isVideo, isTrue);
    });

    test(
      'drops the (0,0) null-island sentinel via the default reader path',
      () async {
        // The reader contract returns (null, null) for a no-fix asset; an item
        // is only produced when both coordinates are non-null.
        final result = await resolveAssetLocations([
          _asset('x'),
        ], reader: (_) async => (null, null));

        expect(result, isEmpty);
      },
    );

    test('a stuck coordinate read is bounded and omitted, not fatal', () async {
      final result = await resolveAssetLocations(
        [_asset('slow'), _asset('fast')],
        perAssetTimeout: const Duration(milliseconds: 20),
        reader: (asset) async {
          if (asset.id == 'slow') {
            await Future<void>.delayed(const Duration(seconds: 5));
            return (1.0, 2.0);
          }
          return (3.0, 4.0);
        },
      );

      // 'slow' times out to no-fix and is dropped; 'fast' still resolves.
      expect(result.map((i) => i.localId), ['fast']);
    });

    test('empty input yields no items', () async {
      final result = await resolveAssetLocations(
        const [],
        reader: (_) async {
          fail('reader should not be called for an empty asset list');
        },
      );
      expect(result, isEmpty);
    });
  });
}
