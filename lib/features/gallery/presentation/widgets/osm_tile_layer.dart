import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class OsmTileLayer extends ConsumerWidget {
  const OsmTileLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The notifier instance is stable for the scope's lifetime, so watching
    // it never rebuilds hosts; state changes are watched by the banner only.
    final status = ref.watch(mapTileStatusProvider.notifier);

    // TileLayer has no const constructor, so this is a plain local.
    final layer = TileLayer(
      urlTemplate: _tileUrl,
      userAgentPackageName: 'com.lumovault.app',
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
