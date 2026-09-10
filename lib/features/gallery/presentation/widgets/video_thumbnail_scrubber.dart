import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoThumbnailScrubber extends StatefulWidget {
  const VideoThumbnailScrubber({
    super.key,
    required this.controller,
    required this.file,
  });

  final VideoPlayerController controller;
  final File file;

  @override
  State<VideoThumbnailScrubber> createState() => _VideoThumbnailScrubberState();
}

class _VideoThumbnailScrubberState extends State<VideoThumbnailScrubber> {
  final List<ui.Image?> _thumbnails = [];
  bool _generating = false;
  VideoPlayerController? _thumbController;

  static const int _thumbnailCount = 10;
  Duration _hoverPosition = Duration.zero;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _generateThumbnails();
  }

  @override
  void dispose() {
    _thumbController?.dispose();
    for (final img in _thumbnails) {
      img?.dispose();
    }
    super.dispose();
  }

  Future<void> _generateThumbnails() async {
    if (_generating) return;
    _generating = true;

    final duration = widget.controller.value.duration;
    if (duration.inMilliseconds <= 0) {
      _generating = false;
      return;
    }

    _thumbController = VideoPlayerController.file(widget.file);
    try {
      await _thumbController!.initialize();
      final interval = duration.inMilliseconds ~/ (_thumbnailCount + 1);

      for (int i = 0; i < _thumbnailCount; i++) {
        final positionMs = interval * (i + 1);
        final position = Duration(milliseconds: positionMs);

        await _thumbController!.seekTo(position);
        await Future.delayed(const Duration(milliseconds: 100));

        if (!mounted) return;

        // Store null thumbnails — the UI shows a text-based placeholder.
        _thumbnails.add(null);
      }
    } catch (_) {
      // Silently handle thumbnail generation failures
    } finally {
      _thumbController?.dispose();
      _thumbController = null;
      if (mounted) setState(() {});
    }
  }

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final duration = value.duration;
    if (duration.inMilliseconds <= 0) return const SizedBox.shrink();

    return GestureDetector(
      onHorizontalDragStart: (details) => _onDragStart(details, context),
      onHorizontalDragUpdate: (details) => _onDragUpdate(details, context),
      onHorizontalDragEnd: _onDragEnd,
      child: SizedBox(
        height: _isHovering ? 100 : 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail preview (shown on hover)
            if (_isHovering)
              SizedBox(
                height: 64,
                width: 114,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Center(
                    child: Text(
                      _format(_hoverPosition),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            if (_isHovering) const SizedBox(height: 4),
            // Progress bar
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Background bar
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Buffered
                    FractionallySizedBox(
                      widthFactor: value.buffered.isNotEmpty
                          ? (value.buffered.last.end.inMilliseconds /
                                    duration.inMilliseconds)
                                .clamp(0.0, 1.0)
                          : 0.0,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white38,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Played
                    FractionallySizedBox(
                      widthFactor:
                          (value.position.inMilliseconds /
                                  duration.inMilliseconds)
                              .clamp(0.0, 1.0),
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Thumb indicator
                    Positioned(
                      left:
                          ((value.position.inMilliseconds /
                                      duration.inMilliseconds)
                                  .clamp(0.0, 1.0) *
                              (MediaQuery.of(context).size.width - 24) -
                          6),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDragStart(DragStartDetails details, BuildContext context) {
    setState(() => _isHovering = true);
    _seekToPosition(details.localPosition, context);
  }

  void _onDragUpdate(DragUpdateDetails details, BuildContext context) {
    _seekToPosition(details.localPosition, context);
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() => _isHovering = false);
    // Seek to the final position
    widget.controller.seekTo(_hoverPosition);
  }

  void _seekToPosition(Offset localPosition, BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final progress = (localPosition.dx / (screenWidth - 24)).clamp(0.0, 1.0);
    final duration = widget.controller.value.duration;
    final position = Duration(
      milliseconds: (duration.inMilliseconds * progress).round(),
    );
    setState(() => _hoverPosition = position);
  }
}
