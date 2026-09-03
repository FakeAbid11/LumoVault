import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:photo_manager/photo_manager.dart' hide LatLng;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/di/gallery_providers.dart';
import '../../../../core/di/geocoding_providers.dart';
import '../../../../shared/utils/snackbars.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/settings_gear_button.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/geocoding_service.dart';
import '../widgets/map_tile_error_banner.dart';
import '../widgets/media_tile.dart';
import '../widgets/osm_tile_layer.dart';
import '../../../../shared/providers/connectivity_provider.dart';
import '../../../../shared/providers/map_tile_status_provider.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Immich & Google Photos style photo map: plots every device photo that carries GPS EXIF as a
/// clustered marker over OpenStreetMap tiles. Locations are read straight from
/// the gallery (see `mapPhotosProvider`), so a photo appears here as soon as
/// it's on the device.
///
/// Tapping a pin opens it in the media viewer; floating buttons recenter on
/// the device's current location or fit all photos within view.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  bool _locating = false;

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(mapPhotosProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: const [SettingsGearButton()],
      ),
      body: photosAsync.when(
        loading: () => _buildLoadingMap(),
        // The one failure the tile layer can't show for itself: the photo
        // data failed to load. Keep the basemap visible (it has its own
        // error handling) and layer the problem message over it, instead of
        // a blank page with no way to see the map.
        error: (error, _) => Stack(
          children: [
            _buildMapOnly(),
            _mapStatusOverlay(),
            _ErrorCard(message: 'Could not load the map: $error'),
          ],
        ),
        data: (photos) => _buildBody(context, photos),
      ),
    );
  }

  /// Map tiles only — shown while the first stream emission arrives.
  Widget _buildMapOnly() {
    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(initialCenter: LatLng(0, 0), initialZoom: 2),
      children: [
        const OsmTileLayer(),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () =>
                  launchUrl(Uri.parse('https://openstreetmap.org/copyright')),
            ),
          ],
        ),
      ],
    );
  }

  /// Map plus a progress hint, shown until the photo-location stream emits.
  /// Resolving GPS for a large library takes seconds — without this pill the
  /// tab reads as a blank, broken map rather than a loading one. The status
  /// overlay covers the tiles' own failure mode even before photo data is
  /// ready.
  Widget _buildLoadingMap() {
    return Stack(
      children: [
        _buildMapOnly(),
        _mapStatusOverlay(),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 48,
          child: Center(child: _StatusPill(label: 'Loading photos…')),
        ),
      ],
    );
  }

  /// The offline / tile-failure banner (or nothing), positioned over the top
  /// of the map. Shared by every body branch so the basemap's failure state
  /// is visible no matter what the photo data is doing — including while it
  /// is still loading.
  Widget _mapStatusOverlay() {
    final offline = !ref.watch(isOnlineProvider);
    final tileError = ref.watch(mapTileStatusProvider).hasFailures;
    if (!offline && !tileError) return const SizedBox.shrink();
    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: SafeArea(
        bottom: false,
        child: offline ? const _OfflineBanner() : const MapTileErrorBanner(),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<MediaItem> photos) {
    if (photos.isEmpty) return _buildEmptyState(context);

    // The shell floats its navigation capsule over this tab's body
    // (Scaffold.extendBody) — keep the map canvas, attribution and FABs
    // clear of it. 96 = SafeArea minimum bottom (40) + NavigationBar (56).
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final double capsuleClearance = MediaQuery.sizeOf(context).width < 600
        ? math.max(bottomInset, 96)
        : bottomInset;

    final points = [for (final p in photos) LatLng(p.latitude!, p.longitude!)];

    return Stack(
      children: [
        _mapStatusOverlay(),
        Padding(
          padding: EdgeInsets.only(bottom: capsuleClearance),
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: points.first,
              initialZoom: _pointsHaveSpan(points) ? 4 : 14,
              // A zero-area bounds (every photo sharing one GPS fix — burst
              // shots, same-second captures) makes CameraFit produce an
              // infinite/NaN camera that renders nothing: no tiles, no pins,
              // and no tile errors to raise the failure banner (the
              // blank-map report). Only fit when the points span an area.
              initialCameraFit: _pointsHaveSpan(points)
                  ? CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(points),
                      padding: const EdgeInsets.all(48),
                    )
                  : null,
            ),
            children: [
              const OsmTileLayer(),
              _buildClusterLayer(context, photos),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () => launchUrl(
                      Uri.parse('https://openstreetmap.org/copyright'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Floating map controls: Fit All Photos & My Location
        Positioned(
          right: 16,
          bottom: capsuleClearance + 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'fit_bounds_fab',
                onPressed: () => _fitAllPoints(points),
                tooltip: 'Fit all photos in view',
                child: const Icon(Symbols.zoom_out_map),
              ),
              const SizedBox(height: 12),
              FloatingActionButton(
                heroTag: 'my_location_fab',
                onPressed: _locating ? null : _goToMyLocation,
                tooltip: 'My location',
                child: _locating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Symbols.my_location),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Whether the points cover a non-degenerate area. A small epsilon counts
  /// near-identical GPS fixes (re-reads of the same shot) as one location.
  bool _pointsHaveSpan(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = minLat;
    var minLng = points.first.longitude;
    var maxLng = minLng;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    const epsilon = 1e-6; // ~0.1 m.
    return (maxLat - minLat) > epsilon || (maxLng - minLng) > epsilon;
  }

  void _fitAllPoints(List<LatLng> points) {
    HapticFeedback.lightImpact();
    // Same degenerate-bounds guard as the initial camera fit: fitting a
    // zero-area bounds would move the camera to an infinite/NaN zoom.
    if (points.isEmpty || !_pointsHaveSpan(points)) {
      if (points.isNotEmpty) _mapController.move(points.first, 14);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(48),
      ),
    );
  }

  Widget _buildClusterLayer(BuildContext context, List<MediaItem> photos) {
    String latLngKey(double lat, double lng) =>
        '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

    final photosByPoint = <String, List<MediaItem>>{};
    for (final p in photos) {
      final key = latLngKey(p.latitude!, p.longitude!);
      (photosByPoint[key] ??= []).add(p);
    }

    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        maxClusterRadius: 45,
        size: const Size(48, 48),
        padding: const EdgeInsets.all(48),
        markers: [
          for (final photo in photos)
            Marker(
              point: LatLng(photo.latitude!, photo.longitude!),
              width: 48,
              height: 48,
              child: _PhotoMarker(
                item: photo,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _openItem(context, photo);
                },
              ),
            ),
        ],
        builder: (context, markers) {
          final clusterPhotos = <MediaItem>[];
          for (final m in markers) {
            final key = latLngKey(m.point.latitude, m.point.longitude);
            if (photosByPoint[key] != null) {
              clusterPhotos.addAll(photosByPoint[key]!);
            }
          }
          return _buildCluster(context, markers.length, clusterPhotos);
        },
      ),
    );
  }

  Widget _buildCluster(
    BuildContext context,
    int count,
    List<MediaItem> clusterPhotos,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final topPhoto = clusterPhotos.firstOrNull;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        if (clusterPhotos.isNotEmpty) {
          _showClusterPreview(context, clusterPhotos);
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Circular photo thumbnail preview
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
              color: scheme.primaryContainer,
            ),
            child: ClipOval(
              child: topPhoto != null
                  ? FutureBuilder<Uint8List?>(
                      future: MediaTile.defaultThumbnailLoader(topPhoto),
                      builder: (context, snapshot) {
                        final bytes = snapshot.data;
                        if (bytes != null) {
                          return Image.memory(
                            bytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          );
                        }
                        return Container(
                          color: scheme.primary,
                          alignment: Alignment.center,
                          child: Icon(
                            Symbols.photo_library,
                            size: 22,
                            color: scheme.onPrimary,
                          ),
                        );
                      },
                    )
                  : Container(
                      color: scheme.primary,
                      alignment: Alignment.center,
                      child: Icon(
                        Symbols.photo_library,
                        size: 22,
                        color: scheme.onPrimary,
                      ),
                    ),
            ),
          ),
          // Badge indicator with count
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              alignment: Alignment.center,
              child: Text(
                '$count',
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showClusterPreview(BuildContext context, List<MediaItem> items) {
    HapticFeedback.lightImpact();
    final firstWithLoc = items.firstWhere(
      (i) => i.latitude != null && i.longitude != null,
      orElse: () => items.first,
    );
    final lat = firstWithLoc.latitude;
    final lng = firstWithLoc.longitude;
    final geoFuture = (lat != null && lng != null)
        ? ref.read(geocodingServiceProvider).reverseGeocode(lat, lng)
        : Future.value(null);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<GeoResult?>(
                future: geoFuture,
                builder: (context, snapshot) {
                  final geo = snapshot.data;
                  final locationName = geo?.displayName;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          locationName != null && locationName.isNotEmpty
                              ? 'Photos in $locationName (${items.length})'
                              : 'Photos at this location (${items.length})',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Symbols.close),
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Close',
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _openClusterItems(context, items, index);
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 120,
                          child: MediaTile(mediaItem: item),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return const EmptyState(
      icon: Symbols.location_off,
      title: 'No photos with location yet',
      message:
          'Photos with GPS location data appear here. On Android, make '
          'sure location access is granted for your photos so their '
          'coordinates can be read.',
    );
  }

  /// Open a single photo in the media viewer.
  Future<void> _openItem(BuildContext context, MediaItem item) async {
    try {
      final asset = await AssetEntity.fromId(
        item.localId,
      ).timeout(const Duration(seconds: 15));
      if (asset != null && context.mounted) {
        context.push(
          '/gallery/media/${asset.id}',
          extra: (assets: [asset], initialIndex: 0, allowDeviceDelete: true),
        );
      }
    } catch (_) {
      // Missing asset, timeout, or revoked permission — nothing to open.
    }
  }

  /// Open cluster photos in media viewer with full album swipe.
  Future<void> _openClusterItems(
    BuildContext context,
    List<MediaItem> items,
    int initialIndex,
  ) async {
    final validAssets = <AssetEntity>[];
    int targetIndex = 0;
    for (int i = 0; i < items.length; i++) {
      try {
        final asset = await AssetEntity.fromId(
          items[i].localId,
        ).timeout(const Duration(seconds: 15));
        if (asset != null) {
          if (i == initialIndex) {
            targetIndex = validAssets.length;
          }
          validAssets.add(asset);
        }
      } catch (_) {
        // Skip unreadable assets rather than failing the whole cluster.
      }
    }
    if (validAssets.isNotEmpty && context.mounted) {
      context.push(
        '/gallery/media/${validAssets[targetIndex].id}',
        extra: (
          assets: validAssets,
          initialIndex: targetIndex,
          allowDeviceDelete: true,
        ),
      );
    }
  }

  Future<void> _goToMyLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showSnack('Turn on location services to center the map on you.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showSnack('Location permission is needed to center on your position.');
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      _mapController.move(LatLng(position.latitude, position.longitude), 14);
    } catch (_) {
      _showSnack('Could not determine your location.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    showLumoSnackBar(context, message);
  }
}

/// A single map pin: a small rounded photo thumbnail with a white border and
/// drop shadow so it reads against the map tiles. Loads its bytes through the
/// same cache-backed loader the grid tiles use.
class _PhotoMarker extends StatefulWidget {
  const _PhotoMarker({required this.item, required this.onTap});

  final MediaItem item;
  final VoidCallback onTap;

  @override
  State<_PhotoMarker> createState() => _PhotoMarkerState();
}

class _PhotoMarkerState extends State<_PhotoMarker> {
  late final Future<Uint8List?> _thumbnail;

  @override
  void initState() {
    super.initState();
    _thumbnail = MediaTile.defaultThumbnailLoader(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 4, spreadRadius: 1),
          ],
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: ClipOval(
          child: FutureBuilder<Uint8List?>(
            future: _thumbnail,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes != null) {
                return Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => _placeholder(context),
                );
              }
              return _placeholder(context);
            },
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Icon(
      widget.item.isVideo ? Symbols.videocam : Symbols.image,
      size: 20,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

/// Overlay shown when the map's photo data fails to load. The basemap stays
/// interactive underneath — this just explains why there are no pins.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Positioned(
      left: 24,
      right: 24,
      bottom: 48,
      child: Card(
        color: colors.surface,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Symbols.error, color: colors.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact overlay shown when the device has no connectivity — the tile
/// fetches will fail anyway, so this pre-empts the tile-error banner with
/// the more actionable cause.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.wifi_off, size: 18, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              "You're offline — the map needs a connection.",
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded hint pill (e.g. "Loading photos…") so a slow state reads as
/// progress rather than a silently broken map.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ),
    );
  }
}
