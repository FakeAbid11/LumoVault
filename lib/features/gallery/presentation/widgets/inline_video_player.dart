import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'video_player_controls.dart';
import 'video_gestures.dart';

/// Full-featured video player for the full-screen media viewers.
///
/// Takes a decoded [file] on disk — a local capture in the device gallery or
/// a Telegram original downloaded on demand — and plays it in place with:
/// - Tap to play/pause
/// - Double-tap to seek ±10s
/// - Long-press for 2x speed
/// - Vertical swipe on left for brightness, right for volume
/// - Fullscreen toggle, playback speed picker, orientation lock
/// - Wakelock during playback
/// - Scrubber with elapsed/total time
class InlineVideoPlayer extends StatefulWidget {
  const InlineVideoPlayer({
    super.key,
    required this.file,
    this.autoPlay = true,
    this.onVideoCompleted,
  });

  final File file;

  /// Start playing as soon as the video is ready. Local playback opens paused
  /// on the poster frame is jarring, so both viewers autoplay by default.
  final bool autoPlay;

  /// Called when the video reaches the end. Used for auto-advance.
  final VoidCallback? onVideoCompleted;

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();

  /// Expose the controller for parent widgets that need to interact with the
  /// video player (e.g., thumbnail scrubber, PiP).
  static VideoPlayerController? controllerOf(BuildContext context) {
    final state = context.findAncestorStateOfType<_InlineVideoPlayerState>();
    return state?._controller;
  }
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  late final VideoPlayerController _controller;
  bool _initialized = false;
  Object? _error;
  bool _isPlaying = false;

  /// Playhead as of the last repaint, so [_onTick] can throttle rebuilds.
  Duration _lastPaintedPosition = Duration.zero;
  bool _controlsVisible = true;
  bool _isFullscreen = false;
  bool _hasCompleted = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _initialized = true);
          if (widget.autoPlay) {
            _controller.play();
            WakelockPlus.enable();
          }
          _controller.addListener(_onTick);
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = e);
        });
  }

  void _onTick() {
    if (!mounted) return;
    final isPlaying = _controller.value.isPlaying;
    final position = _controller.value.position;
    final duration = _controller.value.duration;

    // Auto-advance on completion
    if (duration.inMilliseconds > 0 &&
        position.inMilliseconds >= duration.inMilliseconds - 200 &&
        !_hasCompleted &&
        isPlaying) {
      _hasCompleted = true;
      widget.onVideoCompleted?.call();
    }

    if (isPlaying != _isPlaying) {
      setState(() => _isPlaying = isPlaying);
    }

    // Repaint as the playhead moves, not only when the play state flips.
    // Nothing below this widget listens to the controller — neither
    // VideoPlayerControls, which renders _format(value.position), nor
    // VideoThumbnailScrubber's progress bar — so both were painted once at the
    // current position and then stayed frozen: a playing clip showed 0:00 with
    // an empty bar for its whole duration.
    //
    // Throttled to ~10Hz: a moving bar needs no more precision than that, and
    // this rebuilds the player subtree rather than just the label.
    final moved = position - _lastPaintedPosition;
    if (moved >= const Duration(milliseconds: 100) || moved.isNegative) {
      // isNegative covers a backward seek / restart, which must repaint too.
      _lastPaintedPosition = position;
      setState(() {});
    }

    // Keep wakelock in sync with playback state
    if (isPlaying) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    WakelockPlus.disable();
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
  }

  void _toggleFullscreen() {
    if (_isFullscreen) {
      // Exit fullscreen
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      // Enter fullscreen
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    setState(() => _isFullscreen = !_isFullscreen);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return const Center(
        child: Icon(Symbols.broken_image, color: Colors.white38, size: 64),
      );
    }
    if (!_initialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }

    return VideoGestures(
      controller: _controller,
      // Single tap toggles the control bars. Play/pause is NOT wired to tap:
      // the gesture layer used to fire it from a tap-down timer, double-
      // firing whenever a deeper recognizer (center play button, this
      // toggle) also won the gesture.
      onTap: _toggleControls,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Video
          Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
          // Play/pause overlay when paused
          if (!_isPlaying)
            GestureDetector(
              onTap: _togglePlay,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Symbols.play_arrow,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          // Controls overlay (top bar + scrubber)
          VideoPlayerControls(
            controller: _controller,
            visible: _controlsVisible,
            isFullscreen: _isFullscreen,
            onFullscreenToggle: _toggleFullscreen,
            file: widget.file,
            onBack: () {
              if (_isFullscreen) {
                _toggleFullscreen();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }
}
