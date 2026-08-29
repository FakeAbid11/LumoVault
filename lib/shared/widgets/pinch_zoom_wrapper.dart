import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/data/models/app_settings.dart';
import '../../features/settings/presentation/providers/settings_providers.dart';

/// Wraps a scrollable grid with pinch-to-zoom for changing grid density.
///
/// Uses [Listener] instead of [GestureDetector] so the raw pointer events
/// don't enter Flutter's gesture arena — child recognizers like
/// [LongPressGestureRecognizer] (used for bulk-select) are never blocked.
class PinchZoomWrapper extends ConsumerStatefulWidget {
  const PinchZoomWrapper({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PinchZoomWrapper> createState() => _PinchZoomWrapperState();
}

class _PinchZoomWrapperState extends ConsumerState<PinchZoomWrapper> {
  double _lastPinchScale = 1.0;

  /// Active pointers keyed by pointer id.
  final Map<int, Offset> _pointers = {};

  /// Distance between the two fingers when the pinch started (or when the
  /// second finger touched down). Reset whenever we drop below 2 pointers.
  double _initialSpan = 0;

  void _handlePointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) {
      _initialSpan = _span;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length >= 2 && _initialSpan > 0) {
      final scale = _span / _initialSpan;
      _handlePinchScale(scale);
    }
  }

  void _handlePointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) {
      _initialSpan = 0;
    }
  }

  /// Euclidean distance between the two tracked pointers.
  double get _span {
    final pts = _pointers.values.toList();
    return (pts[0] - pts[1]).distance;
  }

  void _handlePinchScale(double scale) {
    if ((scale - _lastPinchScale).abs() < 0.25) return;
    _lastPinchScale = scale;

    final currentGrid = ref.read(settingsGridSizeProvider);
    if (scale > 1.25) {
      if (currentGrid == GridSize.small) {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(gridSize: GridSize.medium));
        HapticFeedback.lightImpact();
      } else if (currentGrid == GridSize.medium) {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(gridSize: GridSize.large));
        HapticFeedback.lightImpact();
      }
    } else if (scale < 0.75) {
      if (currentGrid == GridSize.large) {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(gridSize: GridSize.medium));
        HapticFeedback.lightImpact();
      } else if (currentGrid == GridSize.medium) {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(gridSize: GridSize.small));
        HapticFeedback.lightImpact();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerUp,
      child: widget.child,
    );
  }
}
