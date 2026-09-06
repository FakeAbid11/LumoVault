import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Tile sources — the primary domain and a mirror. When the primary is blocked
/// or intercepted (e.g. an HTTP 200 with an empty image), [requestReload]
/// advances to the next source as an escape hatch.
const _tileSources = [
  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  'https://a.tile.openstreetmap.org/{z}/{x}/{y}.png',
];

/// How much the tiles are darkened under a dark theme.
const double _darkDimFactor = 0.72;

/// OpenStreetMap tile layer, dimmed under a dark theme.
///
/// Optionally accepts [urlTemplate] for tile-source cycling (see
/// [MapTileStatusProvider]). When null, uses the primary source.
class OsmTileLayer extends StatelessWidget {
  const OsmTileLayer({this.urlTemplate, super.key});

  /// Available tile sources, indexed by [MapTileStatus.sourceIndex].
  static const tileSources = _tileSources;

  /// The active tile URL template. Defaults to the primary source.
  final String? urlTemplate;

  @override
  Widget build(BuildContext context) {
    final layer = TileLayer(
      urlTemplate: urlTemplate ?? _tileSources[0],
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
