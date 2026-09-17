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
      // Reporting errors never touches the tile source — only Retry does.
      expect(after.sourceIndex, 0);
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
        // Every retry advances the tile source (wrapping) — the escape
        // hatch for networks that block or intercept the primary domain.
        expect(container.read(mapTileStatusProvider).sourceIndex, 1);
        // The reload broadcasts asynchronously — flush the event queue.
        await pumpEventQueue();
        expect(reloads.length, 1);

        // Dismiss clears without asking the layer to refetch, and leaves
        // the source where the user left it.
        notifier.onTileError(Exception('offline'), null);
        notifier.reset();
        expect(container.read(mapTileStatusProvider).hasFailures, isFalse);
        expect(container.read(mapTileStatusProvider).sourceIndex, 1);
        await pumpEventQueue();
        expect(reloads.length, 1);
      },
    );

    test('retry cycles the tile sources with wrapping', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(mapTileStatusProvider.notifier);

      notifier.requestReload();
      expect(container.read(mapTileStatusProvider).sourceIndex, 1);
      notifier.requestReload();
      expect(container.read(mapTileStatusProvider).sourceIndex, 2);
      // With two sources (see OsmTileLayer.tileSources) the layer reads
      // `sourceIndex % 2`, so index 3 lands on the mirror after wrap.
      notifier.requestReload();
      expect(container.read(mapTileStatusProvider).sourceIndex, 3);
    });
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

      // The re-raised failure after a source switch explains what Retry now
      // does — "check your connection" would be misleading at this point —
      // and the action label changes accordingly.
      container
          .read(mapTileStatusProvider.notifier)
          .onTileError(const SocketException('still offline'), null);
      await tester.pump();
      expect(
        find.text('Still failing — Retry tries a different map server.'),
        findsOneWidget,
      );
      expect(find.text('Next server'), findsOneWidget);

      await tester.tap(find.text('Next server'));
      await tester.pump();
      expect(
        find.text('Still failing — Retry tries a different map server.'),
        findsNothing,
      );
      expect(reloads.length, 2, reason: 'Next server reloads once too');

      // Dismiss also clears the status — without another reload event.
      container
          .read(mapTileStatusProvider.notifier)
          .onTileError(Exception('x'), null);
      await tester.pump();
      expect(
        find.text('Still failing — Retry tries a different map server.'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      expect(
        find.text('Still failing — Retry tries a different map server.'),
        findsNothing,
      );
      expect(reloads.length, 2);
    });

    testWidgets('after a source switch the wording and label change', (
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
      const switchedMessage =
          'Still failing — Retry tries a different map server.';
      expect(find.text(switchedMessage), findsNothing);

      // A first retry advanced the source; the next failure must explain
      // that Retry now means "try another server", not "check connection".
      container.read(mapTileStatusProvider.notifier).requestReload();
      container
          .read(mapTileStatusProvider.notifier)
          .onTileError(const SocketException('offline'), null);
      await tester.pump();

      expect(find.text(switchedMessage), findsOneWidget);
      expect(
        find.text('Map tiles failed to load. Check your connection.'),
        findsNothing,
      );
      expect(find.text('Next server'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
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

    testWidgets('retry switches the tile source the layer fetches from', (
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
      await tester.pump(const Duration(milliseconds: 50));

      String? currentUrl() =>
          tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate;

      expect(currentUrl(), OsmTileLayer.tileSources[0]);

      // Retry #1 → mirror. This is the escape hatch for networks that block
      // or intercept the primary domain: a different host, refetched via
      // flutter_map's urlTemplate-change reload. The pumps advance fake
      // clock past the retry backoff so no timer is pending at test end.
      container.read(mapTileStatusProvider.notifier).requestReload();
      await tester.pump(const Duration(milliseconds: 600));
      expect(currentUrl(), OsmTileLayer.tileSources[1]);

      // Retry #2 → wraps back to the primary.
      container.read(mapTileStatusProvider.notifier).requestReload();
      await tester.pump(const Duration(milliseconds: 600));
      expect(currentUrl(), OsmTileLayer.tileSources[0]);
    });
  });
}
