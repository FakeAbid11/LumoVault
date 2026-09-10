import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerControls extends StatefulWidget {
  const VideoPlayerControls({
    super.key,
    required this.controller,
    this.visible = true,
    this.onFullscreenToggle,
    this.onBack,
    this.isFullscreen = false,
  });

  final VideoPlayerController controller;
  final bool visible;
  final VoidCallback? onFullscreenToggle;
  final VoidCallback? onBack;
  final bool isFullscreen;

  @override
  State<VideoPlayerControls> createState() => _VideoPlayerControlsState();
}

class _VideoPlayerControlsState extends State<VideoPlayerControls>
    with SingleTickerProviderStateMixin {
  double _currentSpeed = 1.0;
  bool _orientationLocked = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    final controller = widget.controller;

    return AnimatedOpacity(
      opacity: widget.visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: Column(
        children: [
          // Top bar
          SafeArea(
            bottom: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  if (widget.onBack != null)
                    IconButton(
                      icon: const Icon(Symbols.arrow_back, color: Colors.white),
                      onPressed: widget.onBack,
                    ),
                  const Spacer(),
                  // Speed button
                  _SpeedButton(
                    currentSpeed: _currentSpeed,
                    onTap: () => _showSpeedPicker(context),
                  ),
                  // Orientation lock
                  IconButton(
                    icon: Icon(
                      _orientationLocked
                          ? Symbols.screen_lock_rotation
                          : Symbols.screen_rotation,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: _toggleOrientationLock,
                    tooltip: _orientationLocked
                        ? 'Unlock orientation'
                        : 'Lock orientation',
                  ),
                  // Fullscreen toggle
                  if (widget.onFullscreenToggle != null)
                    IconButton(
                      icon: Icon(
                        widget.isFullscreen
                            ? Symbols.fullscreen_exit
                            : Symbols.fullscreen,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: widget.onFullscreenToggle,
                    ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Bottom scrubber area
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black54, Colors.transparent],
                stops: [0.0, 1.0],
              ),
            ),
            child: SafeArea(
              top: false,
              child: _ScrubberRow(controller: controller),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleOrientationLock() {
    setState(() => _orientationLocked = !_orientationLocked);
    if (_orientationLocked) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _showSpeedPicker(BuildContext context) {
    final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xDD1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Playback speed',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
            ...speeds.map((speed) {
              final isSelected = speed == _currentSpeed;
              final label = speed == 1.0 ? 'Normal' : '${speed}x';
              return ListTile(
                leading: Icon(
                  isSelected
                      ? Symbols.radio_button_checked
                      : Symbols.radio_button_unchecked,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white54,
                ),
                title: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                onTap: () {
                  widget.controller.setPlaybackSpeed(speed);
                  setState(() => _currentSpeed = speed);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.currentSpeed, required this.onTap});

  final double currentSpeed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: currentSpeed != 1.0
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)
              : Colors.white12,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          currentSpeed == 1.0 ? '1x' : '${currentSpeed}x',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ScrubberRow extends StatelessWidget {
  const _ScrubberRow({required this.controller});

  final VideoPlayerController controller;

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    return Padding(
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
}
