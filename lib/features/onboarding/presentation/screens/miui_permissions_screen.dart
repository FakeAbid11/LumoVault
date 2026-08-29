import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/device/miui_settings.dart';
import '../providers/onboarding_provider.dart';

/// Dedicated full-screen MIUI/Xiaomi background permissions guide.
///
/// Shown only on Xiaomi/Redmi/POCO devices during onboarding, after the
/// standard permissions screen. Walks the user through 4 settings that
/// must be configured for reliable background backup on MIUI.
class MiuiPermissionsScreen extends ConsumerStatefulWidget {
  const MiuiPermissionsScreen({super.key});

  @override
  ConsumerState<MiuiPermissionsScreen> createState() =>
      _MiuiPermissionsScreenState();
}

class _MiuiPermissionsScreenState extends ConsumerState<MiuiPermissionsScreen> {
  int _currentStep = 0;
  String? _packageName;
  final Set<int> _completedSteps = {};

  static const _steps = _MiuiStepData.steps;

  @override
  void initState() {
    super.initState();
    _loadPackageName();
  }

  Future<void> _loadPackageName() async {
    final pkg = await MiuiSettings.getPackageName();
    if (mounted) {
      setState(() => _packageName = pkg ?? 'com.lumovault.app');
    }
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
    } else {
      _finish();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  void _finish() {
    ref.read(onboardingProvider.notifier).nextStep();
    context.push('/onboarding/folders');
  }

  void _skip() {
    ref.read(onboardingProvider.notifier).nextStep();
    context.push('/onboarding/folders');
  }

  void _markCompleted(int index) {
    setState(() => _completedSteps.add(index));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final step = _steps[_currentStep];

    return Scaffold(
      appBar: AppBar(
        title: const Text('MIUI Setup'),
        actions: [
          TextButton(onPressed: _skip, child: const Text('Skip for now')),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    // Step counter
                    Text(
                      'Step ${_currentStep + 1} of ${_steps.length}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Step icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        step.icon,
                        size: 40,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Step title
                    Text(
                      step.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    // Step description
                    Text(
                      step.description,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Step-specific instruction card
                    _InstructionCard(
                      instruction: step.instruction,
                      packageName: _packageName ?? 'com.lumovault.app',
                      onOpenSettings: step.onOpenSettings,
                      isManualStep: step.isManual,
                      isCompleted: _completedSteps.contains(_currentStep),
                      onMarkCompleted: () => _markCompleted(_currentStep),
                    ),
                  ],
                ),
              ),
            ),
            // Progress dots
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        i == _currentStep
                            ? Icons.circle
                            : _completedSteps.contains(i)
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        size: 10,
                        color: i == _currentStep
                            ? scheme.primary
                            : _completedSteps.contains(i)
                            ? scheme.primary
                            : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
            ),
            // Navigation buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _previousStep,
                        child: const Text('Back'),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _currentStep < _steps.length - 1
                          ? _nextStep
                          : _finish,
                      child: Text(
                        _currentStep < _steps.length - 1 ? 'Next' : 'Done',
                      ),
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

/// Instruction card shown for each step.
class _InstructionCard extends StatelessWidget {
  const _InstructionCard({
    required this.instruction,
    required this.packageName,
    required this.onOpenSettings,
    required this.isManualStep,
    required this.isCompleted,
    required this.onMarkCompleted,
  });

  final String instruction;
  final String packageName;
  final Future<bool> Function(String)? onOpenSettings;
  final bool isManualStep;
  final bool isCompleted;
  final VoidCallback onMarkCompleted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: isCompleted
          ? scheme.primaryContainer.withValues(alpha: 0.3)
          : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isCompleted ? Symbols.check_circle : Symbols.info,
                  size: 20,
                  color: isCompleted ? Colors.green : scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    instruction,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!isManualStep && !isCompleted)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (onOpenSettings != null) {
                      await onOpenSettings!(packageName);
                    }
                  },
                  icon: const Icon(Symbols.open_in_new, size: 18),
                  label: const Text('Open Settings'),
                ),
              ),
            if (isManualStep && !isCompleted)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onMarkCompleted,
                  icon: const Icon(Symbols.check, size: 18),
                  label: const Text("I've done this"),
                ),
              ),
            if (isCompleted)
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Completed',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MiuiStepData {
  const _MiuiStepData._();

  static const steps = [
    _Step(
      icon: Symbols.power_settings_new,
      title: 'Enable Autostart',
      description:
          'Allow LumoVault to start automatically when your phone boots. '
          'Without this, backup won\'t run after a restart.',
      instruction:
          'Find LumoVault in the list and toggle it ON. '
          'If you don\'t see it, tap "Add manually" and select LumoVault.',
      onOpenSettings: MiuiSettings.openAutostartSettings,
    ),
    _Step(
      icon: Symbols.battery_alert,
      title: 'Disable Battery Saver',
      description:
          'MIUI\'s battery optimization kills background apps to save power. '
          'Whitelist LumoVault to keep backup running.',
      instruction:
          'Set LumoVault to "No restrictions" or "Unrestricted". '
          'This prevents MIUI from stopping backup when the screen is off.',
      onOpenSettings: MiuiSettings.openBatterySettings,
    ),
    _Step(
      icon: Symbols.apps,
      title: 'Allow Background Activity',
      description:
          'Grant LumoVault permission to run in the background. '
          'This ensures photos back up even when the app is closed.',
      instruction:
          'Toggle "Allow background activity" to ON. '
          'This is separate from battery optimization.',
      onOpenSettings: MiuiSettings.openBatterySettings,
    ),
    _Step(
      icon: Symbols.lock,
      title: 'Lock in Recents',
      description:
          'Lock LumoVault in the Recent Apps screen to prevent MIUI '
          'from killing it when you switch between apps.',
      instruction:
          '1. Open Recent Apps (swipe up and hold)\n'
          '2. Find LumoVault\n'
          '3. Swipe down on the app card to reveal the lock icon\n'
          '4. Tap the lock icon 🔒',
      isManual: true,
    ),
  ];
}

class _Step {
  const _Step({
    required this.icon,
    required this.title,
    required this.description,
    required this.instruction,
    this.onOpenSettings,
    this.isManual = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String instruction;
  final Future<bool> Function(String)? onOpenSettings;
  final bool isManual;
}
