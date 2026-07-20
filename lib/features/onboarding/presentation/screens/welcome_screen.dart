import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/onboarding_provider.dart';
import '../widgets/feature_card.dart';
import '../widgets/onboarding_progress_indicator.dart';

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
                ),
                child: Icon(
                  Icons.photo_library,
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
                  fontWeight: FontWeight.w600,
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
                      icon: Icons.cloud_upload_outlined,
                      title: 'Automatic Backup',
                      description:
                          'Back up photos and videos automatically in the background',
                    ),
                    SizedBox(height: 12),
                    FeatureCard(
                      icon: Icons.high_quality_outlined,
                      title: 'Original Quality',
                      description:
                          'Never compress your memories — full resolution, always',
                    ),
                    SizedBox(height: 12),
                    FeatureCard(
                      icon: Icons.shield_outlined,
                      title: 'Private & Secure',
                      description:
                          'Your files stay in your own Telegram account — fully encrypted',
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
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          ref.read(onboardingProvider.notifier).nextStep();
                          context.push('/onboarding/permissions');
                        },
                        child: const Text('Get Started'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        context.go('/login');
                      },
                      child: const Text('I already have an account'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
