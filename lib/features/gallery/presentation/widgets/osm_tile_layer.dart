import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

import '../../../../shared/providers/map_tile_status_provider.dart';

/// The one basemap LumoVault uses: OpenStreetMap's standard raster style.
///
/// Both maps — the photo map and the location picker — render these tiles in
/// every theme, so the map looks the same whatever the app brightness is.
const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

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

/// An HTTP client that fails requests which make no progress for
/// [_tileRequestTimeout].
///
/// This bounds the wait for the response to *start*; a response whose body
/// stalls after headers is an accepted (rare) gap. It wraps the plain client
/// and is itself wrapped by a [RetryClient], so transient failures still get
/// retried — worst case a dead network reports its first error in
/// ~30s instead of never.
class _TimeoutClient extends http.BaseClient {
  _TimeoutClient() : _inner = http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner
        .send(request)
        .timeout(
          _tileRequestTimeout,
          onTimeout: () => throw TimeoutException(
            'Tile request to ${request.url.host} timed out',
            _tileRequestTimeout,
          ),
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
/// status as a banner and can call `requestReload` on the notifier — this
/// layer forwards the notifier's reload stream to `TileLayer.reset`, which
/// makes every tile drop and re-request.
class OsmTileLayer extends ConsumerStatefulWidget {
  const OsmTileLayer({super.key});

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
      httpClient: RetryClient(_TimeoutClient()),
    );
  }

  @override
  void dispose() {
    unawaited(_tileProvider.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The notifier instance is stable for the scope's lifetime, so watching
    // it never rebuilds hosts; state changes are watched by the banner only.
    final status = ref.watch(mapTileStatusProvider.notifier);

    // TileLayer has no const constructor, so this is a plain local.
    final layer = TileLayer(
      urlTemplate: _tileUrl,
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
