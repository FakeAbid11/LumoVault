import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/onboarding_provider.dart';
import '../widgets/feature_card.dart';
import '../widgets/onboarding_progress_indicator.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Welcome screen — first screen in the onboarding flow.
///
/// Displays app logo, tagline, feature highlights, and navigation buttons.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(onboardingProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colorScheme.primaryContainer, colorScheme.surface],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              // App logo
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Symbols.photo_library,
                  size: 48,
                  color: colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: 24),
              // App name
              Text(
                'LumoVault',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              // Tagline
              Text(
                'Your photos, your cloud, your control',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 40),
              // Feature highlights
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: const [
                    FeatureCard(
                      icon: Symbols.cloud_upload,
                      title: 'Automatic Backup',
                      description:
                          'Back up photos and videos automatically in the background',
                    ),
                    SizedBox(height: 12),
                    FeatureCard(
                      icon: Symbols.high_quality,
                      title: 'Original Quality',
                      description:
                          'Never compress your memories — full resolution, always',
                    ),
                    SizedBox(height: 12),
                    FeatureCard(
                      icon: Symbols.shield,
                      title: 'Private & Secure',
                      description:
                          'Your files stay in a private channel you own — nobody else can see them',
                    ),
                  ],
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
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 56),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      ref.read(onboardingProvider.notifier).nextStep();
                      context.push('/onboarding/permissions');
                    },
                    child: const Text('Get Started'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
