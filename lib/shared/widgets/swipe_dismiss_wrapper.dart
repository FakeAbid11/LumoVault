import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A wrapper widget that provides a smooth drag-down-to-dismiss gesture
/// and a swipe-up callback to reveal metadata/details.
class SwipeDismissWrapper extends StatefulWidget {
  const SwipeDismissWrapper({
    super.key,
    required this.child,
    this.onDismissed,
    this.onSwipeUp,
    this.dismissThreshold = 120.0,
    this.swipeUpThreshold = 60.0,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onDismissed;
  final VoidCallback? onSwipeUp;
  final double dismissThreshold;
  final double swipeUpThreshold;
  final bool enabled;

  @override
  State<SwipeDismissWrapper> createState() => _SwipeDismissWrapperState();
}

class _SwipeDismissWrapperState extends State<SwipeDismissWrapper>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0.0;
  double _upDragOffset = 0.0;
  bool _isDragging = false;
  int _pointerCount = 0;

  late final AnimationController _resetController;

  /// One curve, one listener, built once in [initState].
  ///
  /// A fresh Tween + CurvedAnimation + addListener used to be created on every
  /// partial swipe-down and never removed, so after N swipes N listeners each
  /// wrote a competing _dragOffset — the sheet jittered and refused to settle —
  /// and dispose() ran while those stale animations were still attached to the
  /// controller it had just killed.
  late final CurvedAnimation _resetCurve;

  /// Offset the current reset is easing back from.
  double _resetFrom = 0.0;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _resetCurve = CurvedAnimation(parent: _resetController, curve: Curves.easeOut)
      ..addListener(() {
        if (!mounted) return;
        // Equivalent to Tween(begin: _resetFrom, end: 0).transform(curve.value).
        setState(() {
          _dragOffset = _resetFrom * (1.0 - _resetCurve.value);
        });
      });
  }

  @override
  void dispose() {
    _resetCurve.dispose();
    _resetController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointerCount++;
    if (_pointerCount > 1 && _isDragging) {
      _cancelDrag();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointerCount = (_pointerCount - 1).clamp(0, 10);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointerCount = (_pointerCount - 1).clamp(0, 10);
  }

  void _cancelDrag() {
    setState(() {
      _isDragging = false;
      _dragOffset = 0.0;
      _upDragOffset = 0.0;
    });
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (!widget.enabled || _pointerCount > 1) return;
    _resetController.stop();
    setState(() {
      _isDragging = true;
      _upDragOffset = 0.0;
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || !widget.enabled || _pointerCount > 1) return;
    if (details.delta.dy > 0 || _dragOffset > 0) {
      // Downward drag for dismissal
      setState(() {
        _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, 400.0);
      });
    } else if (details.delta.dy < 0) {
      // Upward drag for EXIF / details sheet
      _upDragOffset += details.delta.dy.abs();
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_isDragging || !widget.enabled) return;
    _isDragging = false;

    // Check for swipe-up action
    if (_upDragOffset > widget.swipeUpThreshold ||
        (details.primaryVelocity ?? 0) < -400) {
      if (widget.onSwipeUp != null) {
        HapticFeedback.lightImpact();
        widget.onSwipeUp!();
        return;
      }
    }

    // Check for swipe-down dismissal
    if (_dragOffset > widget.dismissThreshold ||
        (details.primaryVelocity ?? 0) > 800) {
      HapticFeedback.lightImpact();
      if (widget.onDismissed != null) {
        widget.onDismissed!();
      } else {
        Navigator.of(context).pop();
      }
    } else {
      // Re-target and replay the single pre-built animation; see _resetCurve.
      _resetFrom = _dragOffset;
      _resetController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragOffset / 300.0).clamp(0.0, 1.0);
    final opacity = (1.0 - progress * 0.7).clamp(0.0, 1.0);
    final scale = (1.0 - progress * 0.15).clamp(0.85, 1.0);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Container(
          color: Color.fromRGBO(0, 0, 0, opacity),
          child: Transform.translate(
            offset: Offset(0, _dragOffset),
            child: Transform.scale(scale: scale, child: widget.child),
          ),
        ),
      ),
    );
  }
}
