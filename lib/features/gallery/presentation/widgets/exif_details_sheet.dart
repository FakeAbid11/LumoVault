import 'dart:io';

import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:photo_manager/photo_manager.dart' hide LatLng;

import '../../../../core/di/gallery_providers.dart';
import '../../../../core/di/geocoding_providers.dart';
import '../../../../core/utils/format_utils.dart';
import '../../data/models/media_item.dart';
import 'osm_tile_layer.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Full-featured Apple Photos / Google Photos style EXIF and metadata details bottom sheet.
class ExifDetailsSheet extends ConsumerStatefulWidget {
  const ExifDetailsSheet({super.key, this.asset, this.item});

  final AssetEntity? asset;
  final MediaItem? item;

  @override
  ConsumerState<ExifDetailsSheet> createState() => _ExifDetailsSheetState();
}

class _ExifDetailsSheetState extends ConsumerState<ExifDetailsSheet> {
  int? _fileSize;
  String? _filePath;
  double? _assetLat;
  double? _assetLng;
  String? _cameraMake;
  String? _cameraModel;
  String? _lensModel;
  String? _aperture;
  String? _shutterSpeed;
  String? _iso;
  String? _focalLength;

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
        // Load EXIF data for camera details
        await _loadExifData(file);
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

  Future<void> _loadExifData(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final exifData = await readExifFromBytes(bytes);
      if (exifData.isEmpty || !mounted) return;

      setState(() {
        _cameraMake = _exifTagToString(exifData['Make']);
        _cameraModel = _exifTagToString(exifData['Model']);
        _lensModel = _exifTagToString(exifData['LensModel']);
        _aperture = _formatAperture(exifData['FNumber']);
        _shutterSpeed = _formatShutterSpeed(exifData['ExposureTime']);
        _iso = _exifTagToString(exifData['ISOSpeedRatings']);
        _focalLength = _exifTagToString(exifData['FocalLength']);
      });
    } catch (_) {
      // EXIF parsing failed — silently ignore, camera details won't show
    }
  }

  String? _exifTagToString(IfdTag? tag) {
    if (tag == null) return null;
    final value = tag.toString().trim();
    return value.isEmpty ? null : value;
  }

  String? _formatAperture(IfdTag? tag) {
    if (tag == null) return null;
    try {
      final value = tag.values.toList().first;
      if (value is Ratio) {
        final fNumber = value.numerator / value.denominator;
        return 'f/${fNumber.toStringAsFixed(1)}';
      }
    } catch (_) {}
    return tag.toString().trim();
  }

  String? _formatShutterSpeed(IfdTag? tag) {
    if (tag == null) return null;
    try {
      final value = tag.values.toList().first;
      if (value is Ratio) {
        final seconds = value.numerator / value.denominator;
        if (seconds >= 1) {
          return '${seconds.toStringAsFixed(1)}s';
        }
        final denominator = (1 / seconds).round();
        return '1/${denominator}s';
      }
    } catch (_) {}
    return tag.toString().trim();
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _editDate(context, date),
                    icon: const Icon(Symbols.edit_calendar, size: 16),
                    label: const Text('Edit'),
                  ),
                ],
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

              // Camera Details Card (if EXIF data available)
              if (_cameraMake != null || _cameraModel != null)
                _buildCameraCard(context),
              if (_cameraMake != null || _cameraModel != null)
                const SizedBox(height: 16),

              // Cloud / Backup Status Card
              _buildBackupCard(context),
              const SizedBox(height: 16),

              // Location Section (read-only)
              if (hasLocation) _buildLocationCard(context, lat, lng),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCameraCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final cameraName = [
      _cameraMake,
      _cameraModel,
    ].where((s) => s != null && s.isNotEmpty).join(' ');

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.camera_alt, size: 24, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    cameraName.isNotEmpty ? cameraName : 'Camera',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (_lensModel != null && _lensModel!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildExifRow(context, 'Lens', _lensModel!),
            ],
            if (_aperture != null) ...[
              const SizedBox(height: 4),
              _buildExifRow(context, 'Aperture', _aperture!),
            ],
            if (_shutterSpeed != null) ...[
              const SizedBox(height: 4),
              _buildExifRow(context, 'Shutter Speed', _shutterSpeed!),
            ],
            if (_iso != null) ...[
              const SizedBox(height: 4),
              _buildExifRow(context, 'ISO', _iso!),
            ],
            if (_focalLength != null) ...[
              const SizedBox(height: 4),
              _buildExifRow(context, 'Focal Length', _focalLength!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExifRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
              color: isUploaded ? Colors.green : colorScheme.onSurfaceVariant,
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

  Widget _buildLocationCard(BuildContext context, double? lat, double? lng) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (lat == null || lng == null) return const SizedBox.shrink();

    final geoAsync = ref.watch(reverseGeocodeProvider((lat, lng)));
    final geo = geoAsync.valueOrNull;
    final point = LatLng(lat, lng);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Symbols.location_on, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Location',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
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

  Future<void> _editDate(BuildContext context, DateTime currentDate) async {
    final assetId = widget.asset?.id ?? widget.item?.localId;
    if (assetId == null) return;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (!mounted || pickedDate == null) return;

    TimeOfDay? pickedTime;
    if (mounted) {
      pickedTime = await showTimePicker(
        context: this.context,
        initialTime: TimeOfDay.fromDateTime(currentDate),
      );
    }
    if (!mounted) return;

    final newDate = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime?.hour ?? currentDate.hour,
      pickedTime?.minute ?? currentDate.minute,
    );

    final repository = ref.read(galleryRepositoryProvider);
    await repository.setCreatedAt(assetId, newDate);

    if (mounted) {
      setState(() {});
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
