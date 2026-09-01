import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:photo_manager/photo_manager.dart' hide LatLng;

import '../../../../core/di/gallery_providers.dart';
import '../../../../core/di/geocoding_providers.dart';
import '../../../../core/theme/status_color.dart';
import '../../../../core/utils/format_utils.dart';
import '../../data/models/media_item.dart';
import '../screens/location_picker_screen.dart';
import 'osm_tile_layer.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Full-featured Apple Photos / Google Photos style EXIF and metadata details bottom sheet.
class ExifDetailsSheet extends ConsumerStatefulWidget {
  const ExifDetailsSheet({
    super.key,
    this.asset,
    this.item,
    this.onLocationChanged,
  });

  final AssetEntity? asset;
  final MediaItem? item;
  final VoidCallback? onLocationChanged;

  @override
  ConsumerState<ExifDetailsSheet> createState() => _ExifDetailsSheetState();
}

class _ExifDetailsSheetState extends ConsumerState<ExifDetailsSheet> {
  int? _fileSize;
  String? _filePath;
  double? _assetLat;
  double? _assetLng;

  @override
  void initState() {
    super.initState();
    _loadFileDetails();
  }

  Future<void> _loadFileDetails() async {
    if (widget.asset != null) {
      final file = await widget.asset!.file;
      if (file != null && mounted) {
        final length = await file.length();
        setState(() {
          _fileSize = length;
          _filePath = file.path;
        });
      }
      if (widget.item?.latitude == null) {
        final latlng = await widget.asset!.latlngAsync();
        if (latlng != null && mounted) {
          final lat = latlng.latitude;
          final lng = latlng.longitude;
          if (lat != 0 || lng != 0) {
            setState(() {
              _assetLat = lat;
              _assetLng = lng;
            });
          }
        }
      }
    } else if (widget.item != null) {
      setState(() {
        _fileSize = widget.item!.fileSize;
        _filePath = widget.item!.filePath;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final date =
        widget.asset?.createDateTime ??
        widget.item?.createdAt ??
        DateTime.now();
    final width = widget.asset?.width ?? widget.item?.width ?? 0;
    final height = widget.asset?.height ?? widget.item?.height ?? 0;
    final isVideo =
        widget.asset?.type == AssetType.video ||
        (widget.item?.isVideo ?? false);
    final durationMs = widget.asset != null
        ? widget.asset!.duration * 1000
        : widget.item?.durationMs;

    final lat = widget.item?.latitude ?? _assetLat;
    final lng = widget.item?.longitude ?? _assetLng;
    final hasLocation = lat != null && lng != null;

    final megaPixels = (width > 0 && height > 0)
        ? ((width * height) / 1000000).toStringAsFixed(1)
        : null;

    final fileName =
        widget.item?.fileName ??
        widget.asset?.title ??
        (_filePath != null
            ? _filePath!.split(Platform.pathSeparator).last
            : 'Media');

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              const SizedBox(height: 8),

              // Date & Time
              Text(
                _formatFullDate(date),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _formatTime(date),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // Technical Details Card
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isVideo ? Symbols.videocam : Symbols.image,
                            size: 24,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fileName,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _buildSpecSummary(
                                    width: width,
                                    height: height,
                                    megaPixels: megaPixels,
                                    fileSize: _fileSize,
                                    isVideo: isVideo,
                                    durationMs: durationMs,
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Cloud / Backup Status Card
              _buildBackupCard(context),
              const SizedBox(height: 16),

              // Location Section
              if (hasLocation)
                _buildLocationSectionWithGeo(context, lat, lng)
              else
                _buildLocationSection(context, lat, lng, hasLocation),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBackupCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUploaded = widget.item?.status == MediaStatus.uploaded;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isUploaded ? Symbols.cloud_done : Symbols.cloud_queue,
              color: isUploaded ? successColor : colorScheme.onSurfaceVariant,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUploaded
                        ? 'Backed up to Telegram'
                        : 'Stored on this device',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.item?.telegramMessageId != null)
                    Text(
                      'Message #${widget.item!.telegramMessageId}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSection(
    BuildContext context,
    double? lat,
    double? lng,
    bool hasLocation,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!hasLocation) {
      return Card(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          leading: Icon(Symbols.add_location_alt, color: colorScheme.primary),
          title: const Text('Add location'),
          subtitle: const Text('Pin where this photo was taken'),
          onTap: () => _openLocationPicker(null, null),
        ),
      );
    }

    final point = LatLng(lat!, lng!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Location',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              onPressed: () => _openLocationPicker(lat, lng),
              icon: const Icon(Symbols.edit_location_alt, size: 16),
              label: const Text('Edit'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Mini Map Preview
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 140,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 14,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                const OsmTileLayer(),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 36,
                      height: 36,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.error,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4),
                          ],
                        ),
                        child: Icon(
                          Symbols.location_on,
                          color: colorScheme.onError,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _formatCoordinates(lat, lng),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildLocationSectionWithGeo(
    BuildContext context,
    double? lat,
    double? lng,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (lat == null || lng == null) {
      return _buildLocationSection(context, lat, lng, false);
    }
    final geoAsync = ref.watch(reverseGeocodeProvider((lat, lng)));
    final geo = geoAsync.valueOrNull;
    final point = LatLng(lat, lng);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Location',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              onPressed: () => _openLocationPicker(lat, lng),
              icon: const Icon(Symbols.edit_location_alt, size: 16),
              label: const Text('Edit'),
            ),
          ],
        ),
        if (geo != null && geo.displayName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            geo.displayName,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 8),

        // Mini Map Preview
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 140,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 14,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                const OsmTileLayer(),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 36,
                      height: 36,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.error,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4),
                          ],
                        ),
                        child: Icon(
                          Symbols.location_on,
                          color: colorScheme.onError,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _formatCoordinates(lat, lng),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _openLocationPicker(
    double? currentLat,
    double? currentLng,
  ) async {
    final assetId = widget.asset?.id ?? widget.item?.localId;
    if (assetId == null) return;

    final result = await context.push<LocationPickerResult>(
      '/gallery/pick-location',
      extra: {'latitude': currentLat, 'longitude': currentLng},
    );

    if (!mounted || result == null) return;

    final repository = ref.read(galleryRepositoryProvider);
    if (result.isRemove) {
      await repository.setLocation(assetId);
    } else if (result.isConfirm) {
      await repository.setLocation(
        assetId,
        latitude: result.latitude,
        longitude: result.longitude,
      );
    }

    if (mounted) {
      setState(() {});
      widget.onLocationChanged?.call();
    }
  }

  String _formatFullDate(DateTime dt) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final weekday = weekdays[dt.weekday - 1];
    final month = months[dt.month - 1];
    return '$weekday, $month ${dt.day}, ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _buildSpecSummary({
    required int width,
    required int height,
    required String? megaPixels,
    required int? fileSize,
    required bool isVideo,
    required int? durationMs,
  }) {
    final parts = <String>[];
    if (megaPixels != null && !isVideo) parts.add('${megaPixels}MP');
    if (width > 0 && height > 0) parts.add('$width × $height');
    if (fileSize != null && fileSize > 0) parts.add(formatBytes(fileSize));
    if (isVideo && durationMs != null) {
      final sec = (durationMs / 1000).round();
      final min = sec ~/ 60;
      final remSec = sec % 60;
      parts.add('$min:${remSec.toString().padLeft(2, '0')}');
    }
    return parts.join(' · ');
  }

  String _formatCoordinates(double lat, double lng) {
    final latDir = lat >= 0 ? 'N' : 'S';
    final lngDir = lng >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(4)}° $latDir, ${lng.abs().toStringAsFixed(4)}° $lngDir';
  }
}
