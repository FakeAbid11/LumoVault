import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_progress_indicator.dart';

/// Initial scan screen — scans selected folders for media.
///
/// Shows animated scanning indicator and progress counter.
class InitialScanScreen extends ConsumerStatefulWidget {
  const InitialScanScreen({super.key});

  @override
  ConsumerState<InitialScanScreen> createState() => _InitialScanScreenState();
}

class _InitialScanScreenState extends ConsumerState<InitialScanScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  int _currentPhotoCount = 0;
  int _currentVideoCount = 0;
  int _targetPhotos = 0;
  int _targetVideos = 0;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // Simulate scan results
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScan();
    });
  }

  void _startScan() {
    final notifier = ref.read(onboardingProvider.notifier);
    notifier.startScan();

    // Simulate finding media
    _targetPhotos = 847;
    _targetVideos = 124;

    int step = 0;
    const totalSteps = 20;
    _scanTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      step++;
      if (step >= totalSteps) {
        timer.cancel();
        setState(() {
          _currentPhotoCount = _targetPhotos;
          _currentVideoCount = _targetVideos;
        });
        notifier.updateScanResults(
          photoCount: _targetPhotos,
          videoCount: _targetVideos,
          estimatedSizeBytes: 2147483648,
        );
        notifier.completeScan();
      } else {
        final progress = step / totalSteps;
        setState(() {
          _currentPhotoCount = (_targetPhotos * progress).round();
          _currentVideoCount = (_targetVideos * progress).round();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scanTimer?.cancel();
    super.dispose();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Animated scanning indicator
                      ScaleTransition(
                        scale: _animation,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            onboarding.scanComplete
                                ? Icons.check_circle_outline
                                : Icons.search,
                            size: 48,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        onboarding.scanComplete
                            ? 'Scan complete!'
                            : 'Scanning your folders...',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      // Progress counter
                      Text(
                        'Found $_currentPhotoCount photos and $_currentVideoCount videos',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (onboarding.scanComplete) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Estimated backup size: ${_formatSize(2147483648)}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Progress indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: OnboardingProgressIndicator(
                currentStep: onboarding.currentStep,
              ),
            ),
            // Navigation buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        ref.read(onboardingProvider.notifier).previousStep();
                        context.pop();
                      },
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: onboarding.scanComplete
                          ? () {
                              ref.read(onboardingProvider.notifier).nextStep();
                              context.push('/onboarding/telegram');
                            }
                          : null,
                      child: const Text('Continue'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
