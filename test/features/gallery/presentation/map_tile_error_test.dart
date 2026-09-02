import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:lumovault/features/gallery/presentation/widgets/map_tile_error_banner.dart';
import 'package:lumovault/features/gallery/presentation/widgets/osm_tile_layer.dart';
import 'package:lumovault/shared/providers/map_tile_status_provider.dart';

/// Regression coverage for the map basemap's silent-failure fix.
///
/// Raster tiles have no in-UI error surface — a tile that fails to load is
/// just an absent image — so tile-fetch failures used to render as a blank
/// gray basemap with no explanation. `OsmTileLayer` now reports fetch errors
/// into `mapTileStatusProvider`, and the Map tab surfaces them as a banner
/// with a Retry that re-requests every tile.
void main() {
  group('MapTileStatusNotifier', () {
    test('first tile error raises the status; later ones are absorbed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(mapTileStatusProvider.notifier);

      expect(container.read(mapTileStatusProvider).hasFailures, isFalse);

      final firstError = StateError('failed host lookup');
      notifier.onTileError(firstError, null);
      final raised = container.read(mapTileStatusProvider);
      expect(raised.hasFailures, isTrue);
      expect(raised.lastError, same(firstError));
      expect(raised.failedAt, isNotNull);

      // One pan across an offline map fails dozens of tiles at once — they
      // must not churn the (already surfaced) status.
      notifier.onTileError(const SocketException('another tile'), null);
      final after = container.read(mapTileStatusProvider);
      expect(after.lastError, same(firstError));
      expect(after.failedAt, raised.failedAt);
    });

    test(
      'requestReload clears the status and broadcasts exactly one reload',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(mapTileStatusProvider.notifier);

        final reloads = <void>[];
        final sub = notifier.reloadStream.listen(reloads.add);
        addTearDown(sub.cancel);

        notifier.onTileError(Exception('offline'), null);
        expect(container.read(mapTileStatusProvider).hasFailures, isTrue);

        notifier.requestReload();
        expect(container.read(mapTileStatusProvider).hasFailures, isFalse);
        // The reload broadcasts asynchronously — flush the event queue.
        await pumpEventQueue();
        expect(reloads.length, 1);

        // Dismiss clears without asking the layer to refetch.
        notifier.onTileError(Exception('offline'), null);
        notifier.reset();
        expect(container.read(mapTileStatusProvider).hasFailures, isFalse);
        await pumpEventQueue();
        expect(reloads.length, 1);
      },
    );
  });

  group('MapTileErrorBanner', () {
    testWidgets('hidden while healthy; Retry reloads once; dismiss clears', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: MapTileErrorBanner())),
        ),
      );
      const message = 'Map tiles failed to load. Check your connection.';
      expect(find.text(message), findsNothing);

      final reloads = <void>[];
      final sub = container
          .read(mapTileStatusProvider.notifier)
          .reloadStream
          .listen(reloads.add);
      addTearDown(sub.cancel);

      container
          .read(mapTileStatusProvider.notifier)
          .onTileError(const SocketException('offline'), null);
      await tester.pump();
      expect(find.text(message), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.text(message), findsNothing);
      expect(reloads.length, 1, reason: 'Retry must trigger one reload');

      // Dismiss also clears the status — without another reload event.
      container
          .read(mapTileStatusProvider.notifier)
          .onTileError(Exception('x'), null);
      await tester.pump();
      expect(find.text(message), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      expect(find.text(message), findsNothing);
      expect(reloads.length, 1);
    });
  });

  group('OsmTileLayer', () {
    testWidgets('failed tile fetches are reported into the status provider', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(0, 0),
                  initialZoom: 2,
                ),
                children: [OsmTileLayer()],
              ),
            ),
          ),
        ),
      );

      // The test binding fails every HTTP image request, driving tiles
      // through the same error path a real outage takes. Errors land
      // asynchronously — pump until the first one is recorded.
      for (
        var i = 0;
        i < 30 && !container.read(mapTileStatusProvider).hasFailures;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(container.read(mapTileStatusProvider).hasFailures, isTrue);
    });
  });
}
