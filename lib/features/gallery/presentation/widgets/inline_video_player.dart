import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  late final VideoPlayerController _controller;
  bool _initialized = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _initialized = true);
          if (widget.autoPlay) _controller.play();
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = e);
        });
    // Rebuild on play/pause and position changes so the overlay icon and the
    // scrubber stay in sync.
    _controller.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return const Center(
        child: Icon(Icons.broken_image, color: Colors.white38, size: 64),
      );
    }
    if (!_initialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }

    final isPlaying = _controller.value.isPlaying;
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
                Icons.play_arrow,
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

/// Bottom scrubber: a seek bar plus elapsed / total time.
class _Scrubber extends StatelessWidget {
  const _Scrubber({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
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
                controller,
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

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
