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
import '../../../../shared/widgets/empty_state.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/geocoding_service.dart';
import '../widgets/media_tile.dart';
import '../widgets/osm_tile_layer.dart';
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
      appBar: AppBar(title: const Text('Map')),
      body: photosAsync.when(
        loading: () => _buildMapOnly(),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load the map: $error'),
          ),
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

  Widget _buildBody(BuildContext context, List<MediaItem> photos) {
    if (photos.isEmpty) return _buildEmptyState(context);

    final points = [for (final p in photos) LatLng(p.latitude!, p.longitude!)];

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 4,
            initialCameraFit: points.length > 1
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
        // Floating map controls: Fit All Photos & My Location
        Positioned(
          right: 16,
          bottom: 16,
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

  void _fitAllPoints(List<LatLng> points) {
    HapticFeedback.lightImpact();
    if (points.length == 1) {
      _mapController.move(points.first, 14);
    } else if (points.length > 1) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(48),
        ),
      );
    }
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
