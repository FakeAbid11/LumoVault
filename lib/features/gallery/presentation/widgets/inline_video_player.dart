import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Inline video player for the full-screen media viewers.
///
/// Takes a decoded [file] on disk — a local capture in the device gallery or
/// a Telegram original downloaded on demand — and plays it in place: tap to
/// toggle play/pause, with a scrubber and elapsed/total time along the bottom.
/// The controller is fully owned here (created, initialised, disposed), so the
/// callers just hand over a file.
class InlineVideoPlayer extends StatefulWidget {
  const InlineVideoPlayer({
    super.key,
    required this.file,
    this.autoPlay = true,
  });

  final File file;

  /// Start playing as soon as the video is ready. Local playback opens paused
  /// on the poster frame is jarring, so both viewers autoplay by default.
  final bool autoPlay;

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer>
    with WidgetsBindingObserver {
  late final VideoPlayerController _controller;
  bool _initialized = false;
  Object? _error;

  /// Mirrors `_controller.value.isPlaying` so the play/pause overlay only
  /// rebuilds on actual play-state transitions. The controller notifies on
  /// every position tick, and rebuilding the whole subtree at that rate made
  /// playback jank on slower devices.
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = VideoPlayerController.file(widget.file);
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {
            _initialized = true;
            _isPlaying = _controller.value.isPlaying;
          });
          if (widget.autoPlay) _controller.play();
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = e);
        });
    // Rebuild only on play/pause transitions so the overlay icon stays in
    // sync; the scrubber subscribes to the controller itself.
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    final playing = _controller.value.isPlaying;
    if (playing != _isPlaying && mounted) {
      setState(() => _isPlaying = playing);
    }
  }

  /// Backgrounding must not leave audio running under the app-lock screen —
  /// video_player does not pause itself when the activity loses focus.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_initialized && _controller.value.isPlaying) {
        _controller.pause();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    // The controller listener rebuilds on the play-state transition; no
    // explicit setState needed here.
    _controller.value.isPlaying ? _controller.pause() : _controller.play();
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

    final isPlaying = _isPlaying;
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
          // Play affordance shows only while paused; tapping the frame resumes.
          if (!isPlaying)
            Container(
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            // Lift the scrubber off the very bottom edge so it clears the
            // system navigation bar (the timeline viewer has no bottom bar of
            // its own) and doesn't sit uncomfortably low.
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _Scrubber(controller: _controller),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom scrubber: a seek bar plus elapsed / total time. Owns its own
/// controller listener so only this small row rebuilds on position ticks —
/// the player above stays untouched during playback.
class _Scrubber extends StatefulWidget {
  const _Scrubber({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant _Scrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTick);
      widget.controller.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    return Container(
      color: Colors.black54,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            _format(value.position),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: VideoProgressIndicator(
                widget.controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ),
          Text(
            _format(value.duration),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Hours-aware: a 75-minute video reads `1:15:00`, not `75:00`.
  String _format(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
