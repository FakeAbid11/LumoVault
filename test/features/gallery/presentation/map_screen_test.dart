import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumovault/core/di/gallery_providers.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/presentation/screens/map_screen.dart';
import 'package:material_symbols_icons/symbols.dart';

void main() {
  Widget wrap(List<MediaItem> photos) {
    return ProviderScope(
      overrides: [
        mapPhotosProvider.overrideWith((ref) => Stream.value(photos)),
      ],
      child: const MaterialApp(home: MapScreen()),
    );
  }

  MediaItem locatedPhoto(String id) => MediaItem(
    localId: id,
    fileHash: 'hash_$id',
    filePath: 'device://$id',
    fileName: 'photo_$id.jpg',
    mimeType: 'image/jpeg',
    fileSize: 0,
    width: 100,
    height: 100,
    createdAt: DateTime(2026, 1, 1),
    modifiedAt: DateTime(2026, 1, 1),
    scannedAt: DateTime(2026, 1, 1),
    status: MediaStatus.uploaded,
    latitude: 52.52,
    longitude: 13.405,
  );

  testWidgets('shows empty state when no photo carries a location', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const []));
    await tester.pumpAndSettle();

    expect(find.text('No photos with location yet'), findsOneWidget);
    expect(find.byIcon(Symbols.location_off), findsOneWidget);
  });

  testWidgets('renders the clustered map for located photos', (tester) async {
    // Regression guard for the Map tab's blank-canvas report: the data
    // branch must come up with the cluster layer present. Tiles never load
    // under the test binding (every HTTP image fetch fails), so pump a
    // bounded number of frames instead of pumpAndSettle.
    await tester.pumpWidget(wrap([locatedPhoto('a'), locatedPhoto('b')]));
    // Pump a generous fake-clock window so every deferred timer elapses
    // before the binding's no-pending-timers check: the thumbnail loaders'
    // 15s photo_manager timeout + 5s file fallback (the platform channel
    // never resolves under the test binding), plus the tile client's retry
    // backoff (0.5+1+2+4+8s under forced HTTP failures). 90s covers both.
    for (var i = 0; i < 360; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(MarkerClusterLayerWidget), findsOneWidget);
    expect(find.text('No photos with location yet'), findsNothing);
  });

  testWidgets('shows a loading pill while photo data has not emitted', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Never emits: mirrors a slow/hung photo-location resolution.
          mapPhotosProvider.overrideWith(
            (ref) => const Stream<List<MediaItem>>.empty(),
          ),
        ],
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Loading photos…'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
  });
}
