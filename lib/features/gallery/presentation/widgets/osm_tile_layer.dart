import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

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
class OsmTileLayer extends StatelessWidget {
  const OsmTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    // TileLayer has no const constructor, so this is a plain local.
    final layer = TileLayer(
      urlTemplate: _tileUrl,
      userAgentPackageName: 'com.lumovault.app',
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
