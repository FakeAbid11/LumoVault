import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../widgets/osm_tile_layer.dart';

/// Result returned by [LocationPickerScreen].
///
/// Distinguishes between confirming a location, removing a location, and
/// simply dismissing the picker (back button).
class LocationPickerResult {
  const LocationPickerResult({required this.latitude, required this.longitude})
    : _remove = false;
  const LocationPickerResult.remove()
    : latitude = null,
      longitude = null,
      _remove = true;

  final double? latitude;
  final double? longitude;
  final bool _remove;

  bool get isRemove => _remove;
  bool get isConfirm => latitude != null && longitude != null;
}

/// Full-screen map picker for setting a photo's GPS location.
///
/// Returns a [LocationPickerResult] via [Navigator.pop]:
/// - [LocationPickerResult] with coordinates on confirm
/// - [LocationPickerResult.remove] when the user removes the location
/// - `null` when the user dismisses via back button
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    this.initialLatitude,
    this.initialLongitude,
    super.key,
  });

  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late final MapController _mapController;
  LatLng? _selectedPoint;
  bool _hasExistingLocation = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _hasExistingLocation =
        widget.initialLatitude != null && widget.initialLongitude != null;
    if (_hasExistingLocation) {
      _selectedPoint = LatLng(
        widget.initialLatitude!,
        widget.initialLongitude!,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final center =
        _selectedPoint ?? const LatLng(48.8566, 2.3522); // Paris default

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set location'),
        actions: [
          if (_hasExistingLocation || _selectedPoint != null)
            TextButton(onPressed: _removeLocation, child: const Text('Remove')),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: _selectedPoint != null ? 14 : 4,
              onTap: (tapPosition, latLng) {
                setState(() => _selectedPoint = latLng);
              },
            ),
            children: [
              const OsmTileLayer(),
              if (_selectedPoint != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedPoint!,
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.location_pin,
                        size: 40,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
          // Hint text at the top
          if (_selectedPoint == null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    'Tap anywhere on the map to set a location',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          // Coordinates display
          if (_selectedPoint != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    '${_selectedPoint!.latitude.toStringAsFixed(6)}, '
                    '${_selectedPoint!.longitude.toStringAsFixed(6)}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _selectedPoint != null
          ? FloatingActionButton.extended(
              onPressed: _confirm,
              label: const Text('Confirm'),
              icon: const Icon(Icons.check),
            )
          : null,
    );
  }

  void _confirm() {
    if (_selectedPoint != null) {
      Navigator.of(context).pop(
        LocationPickerResult(
          latitude: _selectedPoint!.latitude,
          longitude: _selectedPoint!.longitude,
        ),
      );
    }
  }

  void _removeLocation() {
    Navigator.of(context).pop(const LocationPickerResult.remove());
  }
}
