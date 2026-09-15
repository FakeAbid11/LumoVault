import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  final GlobalKey _thumbKey = GlobalKey();

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
      if (!mounted) return;
      setState(() {});

      // Wait for the off-screen VideoPlayer widget to render the first frame.
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;

      final interval = duration.inMilliseconds ~/ (_thumbnailCount + 1);

      for (int i = 0; i < _thumbnailCount; i++) {
        final positionMs = interval * (i + 1);
        final position = Duration(milliseconds: positionMs);

        await _thumbController!.seekTo(position);
        // Allow the platform decoder to render the frame.
        await Future.delayed(const Duration(milliseconds: 150));
        if (!mounted) return;

        // Force a repaint so the RepaintBoundary captures the new frame.
        _thumbKey.currentContext?.findRenderObject()?.markNeedsPaint();
        await Future.delayed(const Duration(milliseconds: 50));
        if (!mounted) return;

        try {
          final boundary =
              _thumbKey.currentContext?.findRenderObject()
                  as RenderRepaintBoundary?;
          if (boundary != null && boundary.hasSize) {
            final image = await boundary.toImage(pixelRatio: 1.0);
            _thumbnails.add(image);
          } else {
            _thumbnails.add(null);
          }
        } catch (_) {
          _thumbnails.add(null);
        }
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

    return Stack(
      children: [
        // Off-screen secondary VideoPlayer for thumbnail frame capture.
        if (_thumbController != null &&
            _thumbController!.value.isInitialized &&
            !_generating)
          Positioned(
            left: -9999,
            top: -9999,
            child: RepaintBoundary(
              key: _thumbKey,
              child: SizedBox(
                width: 114,
                height: 64,
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: _thumbController!.value.size.width,
                    height: _thumbController!.value.size.height,
                    child: VideoPlayer(_thumbController!),
                  ),
                ),
              ),
            ),
          ),
        // Visible scrubber UI
        GestureDetector(
          onHorizontalDragStart: (details) => _onDragStart(details, context),
          onHorizontalDragUpdate: (details) => _onDragUpdate(details, context),
          onHorizontalDragEnd: _onDragEnd,
          child: SizedBox(
            height: _isHovering ? 100 : 56,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isHovering)
                  SizedBox(
                    height: 64,
                    width: 114,
                    child: _buildPreview(duration),
                  ),
                if (_isHovering) const SizedBox(height: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
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
        ),
      ],
    );
  }

  Widget _buildPreview(Duration duration) {
    final index = _thumbnailIndexForPosition(_hoverPosition, duration);
    final image = index != null && index < _thumbnails.length
        ? _thumbnails[index]
        : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null)
            RawImage(
              image: image,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          Positioned(
            bottom: 2,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  _format(_hoverPosition),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int? _thumbnailIndexForPosition(Duration position, Duration duration) {
    if (_thumbnails.isEmpty || duration.inMilliseconds <= 0) return null;
    final interval = duration.inMilliseconds ~/ (_thumbnailCount + 1);
    if (interval <= 0) return null;
    final index = (position.inMilliseconds ~/ interval) - 1;
    return index.clamp(0, _thumbnails.length - 1);
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
