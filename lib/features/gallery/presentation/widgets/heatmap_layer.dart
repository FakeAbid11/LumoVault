import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// A lightweight grid-based heatmap layer for FlutterMap.
///
/// Divides the visible map into a grid, counts photo points per cell, and
/// renders colored circles proportional to density. Uses [CustomPainter] for
/// efficient rendering without external heatmap dependencies.
class HeatmapLayer extends StatelessWidget {
  const HeatmapLayer({
    super.key,
    required this.points,
    this.gridSize = 20,
    this.minRadius = 8,
    this.maxRadius = 28,
    this.minOpacity = 0.35,
    this.maxOpacity = 0.85,
  });

  /// Weighted points to render. Each point has a [LatLng] and a weight
  /// (default 1 per photo).
  final List<HeatmapPoint> points;

  /// Number of grid cells along each axis.
  final int gridSize;

  /// Minimum circle radius for the least-dense cell.
  final double minRadius;

  /// Maximum circle radius for the most-dense cell.
  final double maxRadius;

  /// Minimum opacity for the least-dense cell.
  final double minOpacity;

  /// Maximum opacity for the most-dense cell.
  final double maxOpacity;

  @override
  Widget build(BuildContext context) {
    return _HeatmapPainterWidget(
      points: points,
      gridSize: gridSize,
      minRadius: minRadius,
      maxRadius: maxRadius,
      minOpacity: minOpacity,
      maxOpacity: maxOpacity,
    );
  }
}

class _HeatmapPainterWidget extends StatefulWidget {
  const _HeatmapPainterWidget({
    required this.points,
    required this.gridSize,
    required this.minRadius,
    required this.maxRadius,
    required this.minOpacity,
    required this.maxOpacity,
  });

  final List<HeatmapPoint> points;
  final int gridSize;
  final double minRadius;
  final double maxRadius;
  final double minOpacity;
  final double maxOpacity;

  @override
  State<_HeatmapPainterWidget> createState() => _HeatmapPainterWidgetState();
}

class _HeatmapPainterWidgetState extends State<_HeatmapPainterWidget> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size.width == 0 || size.height == 0) {
          return const SizedBox.shrink();
        }
        return CustomPaint(
          size: size,
          painter: _HeatmapPainter(
            points: widget.points,
            gridSize: widget.gridSize,
            minRadius: widget.minRadius,
            maxRadius: widget.maxRadius,
            minOpacity: widget.minOpacity,
            maxOpacity: widget.maxOpacity,
          ),
        );
      },
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.points,
    required this.gridSize,
    required this.minRadius,
    required this.maxRadius,
    required this.minOpacity,
    required this.maxOpacity,
  });

  final List<HeatmapPoint> points;
  final int gridSize;
  final double minRadius;
  final double maxRadius;
  final double minOpacity;
  final double maxOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final bounds = _computeBounds();
    final cellWidth = (bounds.maxLon - bounds.minLon) / gridSize;
    final cellHeight = (bounds.maxLat - bounds.minLat) / gridSize;

    if (cellWidth <= 0 || cellHeight <= 0) return;

    // Count points per grid cell.
    final grid = List.generate(gridSize, (_) => List.filled(gridSize, 0));
    for (final point in points) {
      final col = ((point.latLng.longitude - bounds.minLon) / cellWidth)
          .floor()
          .clamp(0, gridSize - 1);
      final row = ((point.latLng.latitude - bounds.minLat) / cellHeight)
          .floor()
          .clamp(0, gridSize - 1);
      grid[row][col] += point.weight;
    }

    // Find max count for normalization.
    var maxCount = 0;
    for (final row in grid) {
      for (final count in row) {
        if (count > maxCount) maxCount = count;
      }
    }
    if (maxCount == 0) return;

    // Draw circles.
    final paint = Paint()..style = PaintingStyle.fill;

    for (var row = 0; row < gridSize; row++) {
      for (var col = 0; col < gridSize; col++) {
        final count = grid[row][col];
        if (count == 0) continue;

        final normalized = count / maxCount;
        final radius = lerpDouble(minRadius, maxRadius, normalized)!;
        final opacity = lerpDouble(minOpacity, maxOpacity, normalized)!;

        final centerLon = bounds.minLon + (col + 0.5) * cellWidth;
        final centerLat = bounds.minLat + (row + 0.5) * cellHeight;

        final screenX =
            ((centerLon - bounds.minLon) / (bounds.maxLon - bounds.minLon)) *
            size.width;
        final screenY =
            size.height -
            ((centerLat - bounds.minLat) / (bounds.maxLat - bounds.minLat)) *
                size.height;

        paint.color = _densityColor(normalized).withValues(alpha: opacity);
        canvas.drawCircle(Offset(screenX, screenY), radius, paint);
      }
    }
  }

  _LatLngBounds _computeBounds() {
    var minLat = points.first.latLng.latitude;
    var maxLat = points.first.latLng.latitude;
    var minLon = points.first.latLng.longitude;
    var maxLon = points.first.latLng.longitude;

    for (final point in points) {
      final lat = point.latLng.latitude;
      final lon = point.latLng.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lon < minLon) minLon = lon;
      if (lon > maxLon) maxLon = lon;
    }

    // Add padding so edge cells aren't cut off.
    final latPad = (maxLat - minLat) * 0.05;
    final lonPad = (maxLon - minLon) * 0.05;
    return _LatLngBounds(
      minLat: minLat - latPad,
      maxLat: maxLat + latPad,
      minLon: minLon - lonPad,
      maxLon: maxLon + lonPad,
    );
  }

  /// Green (low) → Yellow (medium) → Red (high).
  static Color _densityColor(double normalized) {
    if (normalized < 0.5) {
      final t = normalized * 2;
      return Color.lerp(const Color(0xFF4CAF50), const Color(0xFFFFEB3B), t)!;
    }
    final t = (normalized - 0.5) * 2;
    return Color.lerp(const Color(0xFFFFEB3B), const Color(0xFFF44336), t)!;
  }

  @override
  bool shouldRepaint(_HeatmapPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.gridSize != gridSize ||
        oldDelegate.minRadius != minRadius ||
        oldDelegate.maxRadius != maxRadius;
  }
}

class _LatLngBounds {
  const _LatLngBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
}

/// A weighted point for the heatmap.
class HeatmapPoint {
  const HeatmapPoint({required this.latLng, this.weight = 1});

  final LatLng latLng;
  final int weight;
}
