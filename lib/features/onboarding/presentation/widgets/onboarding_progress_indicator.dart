import 'package:flutter/material.dart';

import '../providers/onboarding_provider.dart';

/// Progress indicator showing current step in onboarding flow.
///
/// Displays dots for each step with the current step highlighted.
class OnboardingProgressIndicator extends StatelessWidget {
  const OnboardingProgressIndicator({required this.currentStep, super.key});

  final OnboardingStep currentStep;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const steps = OnboardingStep.values;
    final currentIndex = steps.indexOf(currentStep);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(steps.length, (index) {
        final isActive = index == currentIndex;
        final isPast = index < currentIndex;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? colorScheme.primary
                : isPast
                ? colorScheme.primary.withValues(alpha: 0.5)
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
