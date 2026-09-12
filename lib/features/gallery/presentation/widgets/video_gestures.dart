import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:video_player/video_player.dart';

class VideoGestures extends StatefulWidget {
  const VideoGestures({
    super.key,
    required this.controller,
    required this.child,
    this.onDoubleTapSeek,
    this.onTap,
  });

  final VideoPlayerController controller;
  final Widget child;
  final ValueChanged<Duration>? onDoubleTapSeek;

  /// Single tap on the video surface (e.g. toggle the control bars).
  ///
  /// Play/pause is NOT wired here on purpose: a tap-down timer used to fire
  /// it 300ms after every pointer-down, double-firing when a deeper
  /// recognizer (the center play button, the controls toggle) also won the
  /// gesture — buttons appeared to fight each other.
  final VoidCallback? onTap;

  @override
  State<VideoGestures> createState() => _VideoGesturesState();
}

class _VideoGesturesState extends State<VideoGestures> {
  // Double-tap seek
  DateTime? _lastTapTime;
  bool _isDoubleTapping = false;
  _SeekDirection? _seekDirection;
  Timer? _seekIndicatorTimer;

  // Long-press fast-forward
  bool _isFastForwarding = false;
  double _previousSpeed = 1.0;

  // Volume / brightness gestures
  _SlideMode? _slideMode;
  double _slideStartValue = 0;
  double _slideDelta = 0;
  bool _isSliding = false;
  Timer? _slideIndicatorTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _seekIndicatorTimer?.cancel();
    _slideIndicatorTimer?.cancel();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    final now = DateTime.now();

    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < const Duration(milliseconds: 300)) {
      // Double tap detected
      _handleDoubleTap(details.localPosition);
      _lastTapTime = null;
      return;
    }

    _lastTapTime = now;
  }

  void _handleDoubleTap(Offset position) {
    final size = context.size ?? Size.zero;
    final isLeftHalf = position.dx < size.width / 2;
    final seekBy = Duration(seconds: isLeftHalf ? -10 : 10);

    setState(() {
      _isDoubleTapping = true;
      _seekDirection = isLeftHalf
          ? _SeekDirection.back
          : _SeekDirection.forward;
    });

    final newPos = widget.controller.value.position + seekBy;
    final clamped = newPos < Duration.zero
        ? Duration.zero
        : newPos > widget.controller.value.duration
        ? widget.controller.value.duration
        : newPos;
    widget.controller.seekTo(clamped);

    _seekIndicatorTimer?.cancel();
    _seekIndicatorTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _isDoubleTapping = false);
    });
  }

  void _onLongPressStart(LongPressStartDetails details) {
    _previousSpeed = widget.controller.value.playbackSpeed;
    setState(() => _isFastForwarding = true);
    widget.controller.setPlaybackSpeed(2.0);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    setState(() => _isFastForwarding = false);
    widget.controller.setPlaybackSpeed(_previousSpeed);
  }

  void _onVerticalDragStart(DragStartDetails details) {
    final size = context.size ?? Size.zero;
    final isLeftHalf = details.localPosition.dx < size.width / 2;

    _slideMode = isLeftHalf ? _SlideMode.brightness : _SlideMode.volume;
    _slideStartValue = 0;
    _slideDelta = 0;

    if (_slideMode == _SlideMode.brightness) {
      ScreenBrightness.instance.application
          .then((v) {
            _slideStartValue = v;
          })
          .catchError((_) {});
    } else {
      VolumeController()
          .getVolume()
          .then((v) {
            _slideStartValue = v;
          })
          .catchError((_) {});
    }

    setState(() => _isSliding = true);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_slideMode == null || !_isSliding) return;

    final delta = -details.delta.dy / (context.size?.height ?? 400);
    _slideDelta = delta;

    final newValue = (_slideStartValue + delta).clamp(0.0, 1.0);

    if (_slideMode == _SlideMode.brightness) {
      ScreenBrightness.instance
          .setApplicationScreenBrightness(newValue)
          .catchError((_) {});
    } else {
      VolumeController().setVolume(newValue);
    }

    setState(() {});
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _slideIndicatorTimer?.cancel();
    _slideIndicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _isSliding = false;
          _slideMode = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onTap,
      onTapDown: _onTapDown,
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      onVerticalDragStart: _onVerticalDragStart,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Stack(
        children: [
          widget.child,
          // Double-tap seek indicator
          if (_isDoubleTapping && _seekDirection != null)
            _SeekIndicator(direction: _seekDirection!),
          // Long-press fast-forward indicator
          if (_isFastForwarding) const _FastForwardIndicator(),
          // Volume/brightness slide indicator
          if (_isSliding && _slideMode != null)
            _SlideIndicator(
              mode: _slideMode!,
              value: _slideMode == _SlideMode.brightness
                  ? (_slideStartValue + _slideDelta).clamp(0.0, 1.0)
                  : (_slideStartValue + _slideDelta).clamp(0.0, 1.0),
            ),
        ],
      ),
    );
  }
}

enum _SeekDirection { back, forward }

enum _SlideMode { brightness, volume }

class _SeekIndicator extends StatelessWidget {
  const _SeekIndicator({required this.direction});

  final _SeekDirection direction;

  @override
  Widget build(BuildContext context) {
    final isForward = direction == _SeekDirection.forward;
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 0.0),
        duration: const Duration(milliseconds: 600),
        builder: (context, value, child) {
          return Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.8 + (1.0 - value) * 0.4,
              child: child,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isForward ? Symbols.forward_10 : Symbols.replay_10,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 4),
              Text(
                isForward ? '+10s' : '-10s',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FastForwardIndicator extends StatelessWidget {
  const _FastForwardIndicator();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.fast_forward, color: Colors.white, size: 20),
            SizedBox(width: 4),
            Text(
              '2x',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideIndicator extends StatelessWidget {
  const _SlideIndicator({required this.mode, required this.value});

  final _SlideMode mode;
  final double value;

  @override
  Widget build(BuildContext context) {
    final isBrightness = mode == _SlideMode.brightness;
    final icon = isBrightness
        ? (value > 0.5 ? Symbols.light_mode : Symbols.dark_mode)
        : (value < 0.1
              ? Symbols.volume_off
              : value < 0.5
              ? Symbols.volume_down
              : Symbols.volume_up);

    return Positioned(
      left: isBrightness ? 24 : null,
      right: isBrightness ? null : 24,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          width: 48,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(height: 8),
              RotatedBox(
                quarterTurns: -1,
                child: SizedBox(
                  width: 100,
                  child: LinearProgressIndicator(
                    value: value.clamp(0.0, 1.0),
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${(value * 100).round()}',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
