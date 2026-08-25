import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// An interactive fast-scroll scrubber that displays a draggable handle
/// and a floating Material 3 date bubble indicator.
class FastScrollScrubber extends StatefulWidget {
  const FastScrollScrubber({
    super.key,
    required this.scrollController,
    required this.child,
    this.dateResolver,
  });

  final ScrollController scrollController;
  final Widget child;

  /// Given the current scroll progress (0.0 to 1.0), returns the corresponding
  /// date label to display in the floating bubble.
  final String Function(double progress)? dateResolver;

  @override
  State<FastScrollScrubber> createState() => _FastScrollScrubberState();
}

class _FastScrollScrubberState extends State<FastScrollScrubber>
    with SingleTickerProviderStateMixin {
  bool _isDragging = false;
  double _dragProgress = 0.0;
  String _currentDateLabel = '';
  Timer? _fadeTimer;

  late final AnimationController _bubbleAnimation;
  late final Animation<double> _bubbleFade;
  late final Animation<double> _bubbleScale;

  @override
  void initState() {
    super.initState();
    _bubbleAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _bubbleFade = CurvedAnimation(
      parent: _bubbleAnimation,
      curve: Curves.easeOut,
    );
    _bubbleScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _bubbleAnimation, curve: Curves.easeOutBack),
    );

    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    widget.scrollController.removeListener(_onScroll);
    _bubbleAnimation.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isDragging || !widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    if (position.maxScrollExtent > 0) {
      final progress = (position.pixels / position.maxScrollExtent).clamp(
        0.0,
        1.0,
      );
      if ((progress - _dragProgress).abs() > 0.01) {
        setState(() => _dragProgress = progress);
      }
    }
  }

  void _handleDragUpdate(DragUpdateDetails details, double trackHeight) {
    if (trackHeight <= 0) return;
    final dy = details.localPosition.dy.clamp(0.0, trackHeight);
    final progress = (dy / trackHeight).clamp(0.0, 1.0);

    setState(() {
      _isDragging = true;
      _dragProgress = progress;
    });

    _fadeTimer?.cancel();
    _bubbleAnimation.forward();

    if (widget.scrollController.hasClients) {
      final maxScroll = widget.scrollController.position.maxScrollExtent;
      widget.scrollController.jumpTo(maxScroll * progress);
    }

    if (widget.dateResolver != null) {
      final label = widget.dateResolver!(progress);
      if (label != _currentDateLabel && label.isNotEmpty) {
        _currentDateLabel = label;
        HapticFeedback.selectionClick();
      }
    }
  }

  void _handleDragEnd() {
    _fadeTimer?.cancel();
    _fadeTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _isDragging = false);
        _bubbleAnimation.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = constraints.maxHeight - 80; // Margin top/bottom
        final handleTop =
            40 + (trackHeight * _dragProgress).clamp(0.0, trackHeight);

        return Stack(
          children: [
            widget.child,

            // Draggable Scrubber Rail & Handle on right edge
            Positioned(
              top: 40,
              right: 2,
              bottom: 40,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragDown: (details) {
                  _handleDragUpdate(
                    DragUpdateDetails(
                      globalPosition: details.globalPosition,
                      localPosition: details.localPosition,
                    ),
                    trackHeight,
                  );
                },
                onVerticalDragUpdate: (details) =>
                    _handleDragUpdate(details, trackHeight),
                onVerticalDragEnd: (_) => _handleDragEnd(),
                onVerticalDragCancel: () => _handleDragEnd(),
                child: SizedBox(
                  width: 32,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: _isDragging ? 6 : 4,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _isDragging
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.35,
                              ),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: _isDragging
                            ? [
                                BoxShadow(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Floating Date Bubble Indicator
            if (_currentDateLabel.isNotEmpty)
              Positioned(
                top: (handleTop - 20).clamp(16.0, constraints.maxHeight - 64),
                right: 42,
                child: FadeTransition(
                  opacity: _bubbleFade,
                  child: ScaleTransition(
                    scale: _bubbleScale,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(20),
                      color: colorScheme.primaryContainer,
                      shadowColor: Colors.black26,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Text(
                          _currentDateLabel,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
