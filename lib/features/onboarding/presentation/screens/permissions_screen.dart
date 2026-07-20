import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/permissions/permission_service.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_progress_indicator.dart';
import '../widgets/permission_card.dart';

/// Permissions screen — requests necessary app permissions.
///
/// Shows cards for storage, notification, and background permissions.
/// Uses the real PermissionService for actual permission handling.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  PermissionStatus _mediaStatus = PermissionStatus.notDetermined;
  PermissionStatus _notificationStatus = PermissionStatus.notDetermined;
  bool _batteryOptimizationDisabled = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkCurrentPermissions();
  }

  Future<void> _checkCurrentPermissions() async {
    final permissionService = ref.read(permissionServiceProvider);

    final results = await Future.wait([
      permissionService.checkMediaPermissionStatus(),
      permissionService.checkNotificationPermissionStatus(),
      permissionService.isBatteryOptimizationDisabled(),
    ]);

    if (mounted) {
      setState(() {
        _mediaStatus = results[0] as PermissionStatus;
        _notificationStatus = results[1] as PermissionStatus;
        _batteryOptimizationDisabled = results[2] as bool;
        _isLoading = false;
      });
    }
  }

  Future<void> _requestMediaPermission() async {
    final permissionService = ref.read(permissionServiceProvider);
    final result = await permissionService.requestMediaPermission();
    if (mounted) {
      setState(() {
        _mediaStatus = result.status;
      });
    }
  }

  Future<void> _requestNotificationPermission() async {
    final permissionService = ref.read(permissionServiceProvider);
    final result = await permissionService.requestNotificationPermission();
    if (mounted) {
      setState(() {
        _notificationStatus = result.status;
      });
    }
  }

  Future<void> _requestBatteryOptimization() async {
    final permissionService = ref.read(permissionServiceProvider);
    final granted = await permissionService.requestIgnoreBatteryOptimizations();
    if (mounted) {
      setState(() {
        _batteryOptimizationDisabled = granted;
      });
    }
  }

  Future<void> _openAppSettings() async {
    final permissionService = ref.read(permissionServiceProvider);
    await permissionService.openAppSettings();
    // Re-check permissions when returning from settings.
    await _checkCurrentPermissions();
  }

  bool get _canProceed {
    // Media permission is required; notification and battery are recommended.
    return _mediaStatus == PermissionStatus.granted ||
        _mediaStatus == PermissionStatus.limited;
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions'),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(onboardingProvider.notifier).nextStep();
              context.push('/onboarding/folders');
            },
            child: const Text('Skip'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        'Grant permissions',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'LumoVault needs access to your photos and videos to back them up.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      PermissionCard(
                        icon: Icons.photo_library_outlined,
                        title: 'Storage Access',
                        description: 'Access your photos and videos for backup',
                        status: _mediaStatus,
                        onGrant: _requestMediaPermission,
                        onOpenSettings: _openAppSettings,
                        onManageLimited: _requestMediaPermission,
                      ),
                      const SizedBox(height: 12),
                      PermissionCard(
                        icon: Icons.notifications_outlined,
                        title: 'Notifications',
                        description:
                            'Get notified about backup progress and completion',
                        status: _notificationStatus,
                        onGrant: _requestNotificationPermission,
                        onOpenSettings: _openAppSettings,
                      ),
                      const SizedBox(height: 12),
                      PermissionCard(
                        icon: Icons.sync_outlined,
                        title: 'Background Execution',
                        description:
                            'Continue backing up when the app is in the background',
                        status: _batteryOptimizationDisabled
                            ? PermissionStatus.granted
                            : PermissionStatus.denied,
                        onGrant: _requestBatteryOptimization,
                        onOpenSettings: _openAppSettings,
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
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            ref
                                .read(onboardingProvider.notifier)
                                .previousStep();
                            context.pop();
                          },
                          child: const Text('Back'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton(
                          onPressed: _canProceed
                              ? () {
                                  ref
                                      .read(onboardingProvider.notifier)
                                      .nextStep();
                                  context.push('/onboarding/folders');
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
    );
  }
}
