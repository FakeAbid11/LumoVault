import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_manager/photo_manager.dart' hide LatLng;

import '../../../../core/di/gallery_providers.dart';
import '../../data/models/media_item.dart';
import '../widgets/media_tile.dart';

/// Light tile URL (OpenStreetMap standard).
const _lightTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Dark-mode tile URL: CartoDB Voyager — a soft, light, readable basemap.
/// (Replaces CartoDB "Dark Matter", which rendered near-black / too dark.)
const _darkTileUrl =
    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';

/// CartoDB subdomains for dark tiles.
const _darkSubdomains = ['a', 'b', 'c'];

/// Immich-style photo map: plots every device photo that carries GPS EXIF as a
/// clustered marker over OpenStreetMap tiles. Locations are read straight from
/// the gallery (see `mapPhotosProvider`), so a photo appears here as soon as
/// it's on the device — it does not have to be backed up or scanned first.
///
/// Tapping a pin opens it in the media viewer; a floating button recenters on
/// the device's current location (the only thing geolocator is used for —
/// photo coordinates come from photo_manager EXIF, not geolocator).
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
        loading: () => const Center(child: CircularProgressIndicator()),
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

  bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  Widget _buildBody(BuildContext context, List<MediaItem> photos) {
    if (photos.isEmpty) return _buildEmptyState(context);

    final points = [for (final p in photos) LatLng(p.latitude!, p.longitude!)];
    final dark = _isDark(context);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 4,
            // Fit all located photos in view on first render. A single photo
            // has no bounds to fit, so it just centers (handled by initialCenter
            // above); multiple photos get a padded bounding box.
            initialCameraFit: points.length > 1
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(48),
                  )
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: dark ? _darkTileUrl : _lightTileUrl,
              subdomains: dark ? _darkSubdomains : const [],
              userAgentPackageName: 'com.lumovault.app',
            ),
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
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: _locating ? null : _goToMyLocation,
            tooltip: 'My location',
            child: _locating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  Widget _buildClusterLayer(BuildContext context, List<MediaItem> photos) {
    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        maxClusterRadius: 45,
        size: const Size(44, 44),
        padding: const EdgeInsets.all(48),
        markers: [
          for (final photo in photos)
            Marker(
              point: LatLng(photo.latitude!, photo.longitude!),
              width: 48,
              height: 48,
              child: _PhotoMarker(
                item: photo,
                onTap: () => _openItem(context, photo),
              ),
            ),
        ],
        builder: (context, markers) => _buildCluster(context, markers.length),
      ),
    );
  }

  Widget _buildCluster(BuildContext context, int count) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off_outlined, size: 64, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              'No photos with location yet',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Photos with GPS location data appear here. On Android, make '
              'sure location access is granted for your photos so their '
              'coordinates can be read.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Open a photo in the media viewer, mirroring the timeline's local-item
  /// path: resolve the [AssetEntity] by id, then push the viewer.
  void _openItem(BuildContext context, MediaItem item) {
    AssetEntity.fromId(item.localId).then((asset) {
      if (asset != null && context.mounted) {
        context.push(
          '/gallery/media/${asset.id}',
          extra: (assets: [asset], initialIndex: 0),
        );
      }
    });
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
      widget.item.isVideo ? Icons.videocam : Icons.image,
      size: 20,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}
