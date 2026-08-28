import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/data/models/app_settings.dart';
import '../../features/settings/presentation/providers/settings_providers.dart';

/// Wraps a scrollable grid with pinch-to-zoom for changing grid density.
///
/// Consolidates the identical `_handlePinchScale` logic that was duplicated
/// across [LocalScreen] and [TimelineScreen].
class PinchZoomWrapper extends ConsumerStatefulWidget {
  const PinchZoomWrapper({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PinchZoomWrapper> createState() => _PinchZoomWrapperState();
}

class _PinchZoomWrapperState extends ConsumerState<PinchZoomWrapper> {
  double _lastPinchScale = 1.0;

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
    return GestureDetector(
      onScaleUpdate: (details) {
        if (details.pointerCount >= 2) {
          _handlePinchScale(details.scale);
        }
      },
      child: widget.child,
    );
  }
}
