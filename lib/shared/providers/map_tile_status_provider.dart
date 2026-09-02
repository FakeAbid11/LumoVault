import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Why the map basemap is (or was last) failing to draw tiles.
///
/// Raster tile layers have no in-UI error surface — a tile that fails to
/// load is simply an absent image — so [OsmTileLayer] reports fetch errors
/// here and the Map tab surfaces them with a banner. See
/// `map_tile_error_banner.dart`.
@immutable
class MapTileStatus {
  const MapTileStatus({this.lastError, this.failedAt});

  /// The most recent tile-fetch error, or `null` while tiles load fine.
  final Object? lastError;

  /// When [lastError] was first observed.
  final DateTime? failedAt;

  bool get hasFailures => lastError != null;
}

/// Collects tile-fetch failures from the map's [TileLayer] and broadcasts
/// reload requests back to it.
///
/// A single pan around an offline map can fail dozens of tiles at once, so
/// this deliberately does not rebuild per failure: the first error flips the
/// state once (raising the banner), and later errors are absorbed silently —
/// the user needs "tiles are failing", not a failure counter. [requestReload]
/// (the banner's Retry) clears the state and emits on [reloadStream], which
/// every [OsmTileLayer] forwards to `TileLayer.reset` so all tiles drop and
/// re-request; if they fail again the state re-raises.
///
/// Note the status is app-global: every [OsmTileLayer] (photo map, location
/// picker, EXIF sheet mini-maps) reports into it, since they share one
/// basemap and one failure mode.
class MapTileStatusNotifier extends StateNotifier<MapTileStatus> {
  MapTileStatusNotifier() : super(const MapTileStatus());

  final _reloadController = StreamController<void>.broadcast();

  /// Emits whenever [requestReload] asks the tiles to be fetched again.
  ///
  /// [OsmTileLayer] wires this into `TileLayer.reset`, which reloads all
  /// tiles on each event. The broadcast stream instance is stable for the
  /// notifier's lifetime, so a listener survives host rebuilds.
  Stream<void> get reloadStream => _reloadController.stream;

  /// Report a failed tile fetch. Matches [TileLayer.errorTileCallback]'s
  /// error/stack arguments (the tile itself carries nothing we display).
  void onTileError(Object error, StackTrace? stackTrace) {
    // Already surfaced — keep the banner steady instead of flickering it
    // with every individual tile that fails during the same outage.
    if (state.hasFailures) return;
    state = MapTileStatus(lastError: error, failedAt: DateTime.now());
  }

  /// Clear the failure state (hides the banner) and re-request every tile
  /// via [reloadStream].
  void requestReload() {
    state = const MapTileStatus();
    _reloadController.add(null);
  }

  /// Clear the failure state without refetching (the banner's dismiss).
  void reset() => state = const MapTileStatus();

  @override
  void dispose() {
    unawaited(_reloadController.close());
    super.dispose();
  }
}

final mapTileStatusProvider =
    StateNotifierProvider<MapTileStatusNotifier, MapTileStatus>(
      (ref) => MapTileStatusNotifier(),
    );
