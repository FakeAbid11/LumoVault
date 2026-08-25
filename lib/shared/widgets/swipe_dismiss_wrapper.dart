import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A wrapper widget that provides a smooth drag-down-to-dismiss gesture
/// with interpolating background opacity and scaling.
class SwipeDismissWrapper extends StatefulWidget {
  const SwipeDismissWrapper({
    super.key,
    required this.child,
    this.onDismissed,
    this.dismissThreshold = 120.0,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onDismissed;
  final double dismissThreshold;
  final bool enabled;

  @override
  State<SwipeDismissWrapper> createState() => _SwipeDismissWrapperState();
}

class _SwipeDismissWrapperState extends State<SwipeDismissWrapper>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0.0;
  bool _isDragging = false;

  late final AnimationController _resetController;
  late Animation<double> _resetAnimation;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (!widget.enabled) return;
    _resetController.stop();
    setState(() {
      _isDragging = true;
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || !widget.enabled) return;
    // Only permit downward dragging for dismissal
    if (_dragOffset + details.delta.dy >= 0) {
      setState(() {
        _dragOffset += details.delta.dy;
      });
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_isDragging || !widget.enabled) return;
    _isDragging = false;

    if (_dragOffset > widget.dismissThreshold ||
        (details.primaryVelocity ?? 0) > 800) {
      HapticFeedback.lightImpact();
      if (widget.onDismissed != null) {
        widget.onDismissed!();
      } else {
        Navigator.of(context).pop();
      }
    } else {
      _resetAnimation =
          Tween<double>(begin: _dragOffset, end: 0.0).animate(
            CurvedAnimation(parent: _resetController, curve: Curves.easeOut),
          )..addListener(() {
            setState(() {
              _dragOffset = _resetAnimation.value;
            });
          });
      _resetController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragOffset / 300.0).clamp(0.0, 1.0);
    final opacity = (1.0 - progress * 0.7).clamp(0.0, 1.0);
    final scale = (1.0 - progress * 0.15).clamp(0.85, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: _onVerticalDragStart,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Container(
        color: Colors.black.withValues(alpha: opacity),
        child: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: Transform.scale(scale: scale, child: widget.child),
        ),
      ),
    );
  }
}
