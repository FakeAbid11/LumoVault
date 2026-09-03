import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

import '../../../../shared/providers/map_tile_status_provider.dart';

/// How much the tiles are darkened under a dark theme.
///
/// A plain multiply on RGB, so it is the same map with the glare taken off
/// rather than a different basemap. Roads and labels keep their relative
/// contrast; only the overall luminance drops.
const double _darkDimFactor = 0.72;

/// Per-attempt bound for tile HTTP requests.
///
/// flutter_map's default tile client has NO timeout: a fetch against a
/// black-holed host (VPN, captive portal, Wi-Fi that is "connected" without
/// internet, an ISP/region blocking tile.openstreetmap.org) hangs for the OS
/// TCP timeout — minutes — during which the basemap is silently blank and no
/// error ever fires. Bounding each attempt makes that failure surface
/// quickly, so it can be reported into [mapTileStatusProvider] and shown.
const Duration _tileRequestTimeout = Duration(seconds: 10);

/// An HTTP client that fails requests which make no progress within
/// [_tileRequestTimeout], both while waiting for the response to *start* and
/// while reading the body.
///
/// flutter_map's default stack only ever surfaces errors from the request
/// phase; a middlebox that accepts the connection and then stalls the body
/// (or answers HTTP 200 with an empty payload) would otherwise keep the
/// basemap blank forever with no error to report. This client closes both
/// gaps by buffering the body itself under a future timeout — the provider
/// collects the full bytes anyway, so buffering tile-sized data is free.
/// It is wrapped by a [RetryClient] by the caller, so transient failures
/// still get one quick retry — a dead network reports its first error in
/// ~20s instead of never.
class _TimeoutClient extends http.BaseClient {
  _TimeoutClient();

  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner
        .send(request)
        .timeout(
          _tileRequestTimeout,
          onTimeout: () => throw TimeoutException(
            'Tile request to ${request.url.host} timed out',
            _tileRequestTimeout,
          ),
        );

    // Guard the body: reading must finish within the window too, or the
    // decoder gets an error (which flows into errorTileCallback) instead of
    // hanging forever on a stalled middlebox.
    final bytes = await response.stream.toBytes().timeout(
      _tileRequestTimeout,
      onTimeout: () => throw TimeoutException(
        'Tile body from ${request.url.host} stalled',
        _tileRequestTimeout,
      ),
    );

    // Re-serve the buffered body as a single chunk, preserving the envelope
    // (status code, headers, …) so the provider's status handling is
    // unaffected.
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

/// OpenStreetMap tile layer, dimmed under a dark theme.
///
/// Only the tiles pass through the filter — markers and clusters are siblings
/// in the [FlutterMap] children list, so pins stay at full brightness and
/// remain the most legible thing on a dimmed map.
///
/// Tile fetch failures are reported into [mapTileStatusProvider]: raster
/// tiles otherwise fail silently (a failed tile is just an absent image, with
/// no error UI anywhere below this layer). Hosts like the Map tab surface the
/// status as a banner whose Retry *cycles the tile source* — [tileSources]
/// wraps, so a network that blocks or intercepts the primary domain gets a
/// second, differently-hosted mirror on the next tap.flutter_map refetches
/// every tile on its own when the template changes, and the notifier's
/// reload stream is additionally wired to `TileLayer.reset`.
class OsmTileLayer extends ConsumerStatefulWidget {
  const OsmTileLayer({super.key});

  /// Tile sources tried in order; every Retry advances the index (wrapping).
  ///
  /// All entries serve standard OpenStreetMap raster tiles under the same
  /// attribution; the mirror is FOSSGIS-operated on a different domain/CDN,
  /// which is what escapes domain-specific interception.
  static const tileSources = [
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
  ];

  @override
  ConsumerState<OsmTileLayer> createState() => _OsmTileLayerState();
}

class _OsmTileLayerState extends ConsumerState<OsmTileLayer> {
  /// Created once per layer (not per build): the provider owns a long-lived
  /// HTTP client, and flutter_map keeps whatever provider it is handed —
  /// rebuilding with a fresh one every frame would leak clients.
  late final NetworkTileProvider _tileProvider;

  @override
  void initState() {
    super.initState();
    _tileProvider = NetworkTileProvider(
      // One quick retry per request: a second full timeout chain would push
      // the first visible error past a minute, and the Retry banner already
      // offers a deliberate second attempt.
      httpClient: RetryClient(_TimeoutClient(), retries: 1),
    );
  }

  @override
  void dispose() {
    unawaited(_tileProvider.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only a source *switch* may rebuild this layer: flutter_map reloads all
    // tiles when the template changes (its didUpdateWidget compares URLs),
    // which is exactly the retry semantic. Watching the full status instead
    // would also rebuild on error-state churn for no benefit.
    final sourceIndex =
        ref.watch(
          mapTileStatusProvider.select((status) => status.sourceIndex),
        ) %
        OsmTileLayer.tileSources.length;
    final status = ref.watch(mapTileStatusProvider.notifier);

    // TileLayer has no const constructor, so this is a plain local.
    final layer = TileLayer(
      urlTemplate: OsmTileLayer.tileSources[sourceIndex],
      userAgentPackageName: 'com.lumovault.app',
      tileProvider: _tileProvider,
      errorTileCallback: (tile, error, stackTrace) =>
          status.onTileError(error, stackTrace),
      reset: status.reloadStream,
    );

    if (Theme.of(context).brightness != Brightness.dark) return layer;

    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        _darkDimFactor, 0, 0, 0, 0, //
        0, _darkDimFactor, 0, 0, 0, //
        0, 0, _darkDimFactor, 0, 0, //
        0, 0, 0, 1, 0, //
      ]),
      child: layer,
    );
  }
}
