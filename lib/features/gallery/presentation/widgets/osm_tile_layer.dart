import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/map_tile_status_provider.dart';

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
/// Watches [mapTileStatusProvider] to select the active tile source. On retry
/// the provider advances [MapTileStatus.sourceIndex], and the layer reads it
/// to switch the URL template.
class OsmTileLayer extends ConsumerWidget {
  const OsmTileLayer({super.key});

  /// Available tile sources, indexed by [MapTileStatus.sourceIndex].
  static const tileSources = _tileSources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceIndex = ref.watch(mapTileStatusProvider).sourceIndex;
    final urlTemplate = tileSources[sourceIndex % tileSources.length];

    final layer = TileLayer(
      urlTemplate: urlTemplate,
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
