import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/device/brand_settings.dart';
import '../../../../core/device/device_info_service.dart';
import '../providers/onboarding_provider.dart';

/// Full-screen background permissions guide for aggressive Android skins.
///
/// Detects the device manufacturer and shows brand-specific steps for
/// Xiaomi/MIUI, Samsung/One UI, Huawei/EMUI, OnePlus/OxygenOS, and
/// Oppo/Realme/ColorOS. Not shown on Pixel, Nokia, or other stock devices.
class BackgroundPermissionsScreen extends ConsumerStatefulWidget {
  const BackgroundPermissionsScreen({super.key});

  @override
  ConsumerState<BackgroundPermissionsScreen> createState() =>
      _BackgroundPermissionsScreenState();
}

class _BackgroundPermissionsScreenState
    extends ConsumerState<BackgroundPermissionsScreen> {
  int _currentStep = 0;
  String? _packageName;
  DeviceBrand _brand = DeviceBrand.other;
  final Set<int> _completedSteps = {};

  List<_Step> _steps = [];

  @override
  void initState() {
    super.initState();
    _loadBrand();
  }

  Future<void> _loadBrand() async {
    final deviceInfo = DeviceInfoService();
    final brand = await deviceInfo.getDeviceBrand();
    _packageName = 'com.lumovault.app';

    if (!mounted) return;
    setState(() {
      _brand = brand;
      _steps = _getSteps(brand);
    });
  }

  List<_Step> _getSteps(DeviceBrand brand) {
    switch (brand) {
      case DeviceBrand.xiaomi:
        return _stepsXiaomi;
      case DeviceBrand.samsung:
        return _stepsSamsung;
      case DeviceBrand.huawei:
        return _stepsHuawei;
      case DeviceBrand.oneplus:
        return _stepsOnePlus;
      case DeviceBrand.oppo:
      case DeviceBrand.realme:
        return _stepsOppo;
      case DeviceBrand.other:
        return [];
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

  String _brandTitle() {
    switch (_brand) {
      case DeviceBrand.xiaomi:
        return 'MIUI Setup';
      case DeviceBrand.samsung:
        return 'Samsung Setup';
      case DeviceBrand.huawei:
        return 'EMUI Setup';
      case DeviceBrand.oneplus:
        return 'OnePlus Setup';
      case DeviceBrand.oppo:
      case DeviceBrand.realme:
        return 'Oppo Setup';
      case DeviceBrand.other:
        return 'Background Setup';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_steps.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final step = _steps[_currentStep];

    return Scaffold(
      appBar: AppBar(
        title: Text(_brandTitle()),
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
                    Text(
                      'Step ${_currentStep + 1} of ${_steps.length}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
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
                    Text(
                      step.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      step.description,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
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

// ── Brand-specific step definitions ────────────────────────────────

const _stepsXiaomi = [
  _Step(
    icon: Symbols.power_settings_new,
    title: 'Enable Autostart',
    description:
        'Allow LumoVault to start automatically when your phone boots. '
        "Without this, backup won't run after a restart.",
    instruction:
        'Find LumoVault in the list and toggle it ON. '
        'If you don\'t see it, tap "Add manually" and select LumoVault.',
    onOpenSettings: BrandSettings.openAutostartSettings,
  ),
  _Step(
    icon: Symbols.battery_alert,
    title: 'Disable Battery Saver',
    description:
        "MIUI's battery optimization kills background apps to save power. "
        'Whitelist LumoVault to keep backup running.',
    instruction:
        'Set LumoVault to "No restrictions" or "Unrestricted". '
        'This prevents MIUI from stopping backup when the screen is off.',
    onOpenSettings: BrandSettings.openBatterySettings,
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
    onOpenSettings: BrandSettings.openBatterySettings,
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
        '4. Tap the lock icon',
    isManual: true,
  ),
];

const _stepsSamsung = [
  _Step(
    icon: Symbols.battery_std,
    title: 'Battery Optimization',
    description:
        "Samsung's One UI optimizes battery by killing background apps. "
        'Set LumoVault to "Don\'t optimize" to prevent this.',
    instruction:
        '1. Open Settings > Battery > Background usage limits\n'
        '2. Find LumoVault\n'
        '3. Select "Don\'t optimize"',
    onOpenSettings: BrandSettings.openSamsungBatterySettings,
  ),
  _Step(
    icon: Symbols.bedtime,
    title: 'Check Sleeping Apps',
    description:
        'Samsung moves unused apps to a "Sleeping" list that kills them. '
        'Make sure LumoVault is not in this list.',
    instruction:
        '1. Settings > Battery > Background usage limits\n'
        '2. Check "Sleeping apps" and "Deep sleeping apps"\n'
        '3. Remove LumoVault from both lists',
    onOpenSettings: BrandSettings.openSamsungBatterySettings,
  ),
  _Step(
    icon: Symbols.speed,
    title: 'Disable Adaptive Battery',
    description:
        'Adaptive Battery learns which apps you use less and restricts them. '
        'Disable it for LumoVault to ensure reliable backup.',
    instruction:
        '1. Settings > Battery > More battery settings\n'
        '2. Turn OFF "Adaptive battery"',
    onOpenSettings: BrandSettings.openSamsungBatterySettings,
  ),
  _Step(
    icon: Symbols.lock,
    title: 'Lock in Recents',
    description:
        'Lock LumoVault in the Recent Apps screen to prevent Samsung '
        'from killing it when you switch between apps.',
    instruction:
        '1. Open Recent Apps (swipe up and hold)\n'
        '2. Find LumoVault\n'
        '3. Long-press on the app card\n'
        '4. Tap the lock icon',
    isManual: true,
  ),
];

const _stepsHuawei = [
  _Step(
    icon: Symbols.power_settings_new,
    title: 'App Launch',
    description:
        "Huawei's EMUI manages which apps can start automatically. "
        'Enable all options for LumoVault.',
    instruction:
        '1. Settings > Battery > App launch\n'
        '2. Find LumoVault\n'
        '3. Toggle OFF "Manage all automatically"\n'
        '4. Enable "Auto-launch", "Secondary launch", and "Run in background"',
    onOpenSettings: BrandSettings.openHuaweiAppLaunch,
  ),
  _Step(
    icon: Symbols.battery_alert,
    title: 'Battery Optimization',
    description:
        'Ensure LumoVault is not restricted by battery optimization. '
        'This keeps backup running when the screen is off.',
    instruction:
        '1. Settings > Battery > Battery optimization\n'
        '2. Find LumoVault\n'
        '3. Select "Don\'t allow"',
    onOpenSettings: BrandSettings.openHuaweiBatteryOptimization,
  ),
  _Step(
    icon: Symbols.apps,
    title: 'Startup Manager',
    description:
        'Allow LumoVault to start on boot and run in the background. '
        'Without this, backup may not start after a restart.',
    instruction:
        '1. Settings > All > Startup manager\n'
        '2. Find LumoVault\n'
        '3. Toggle it ON',
    isManual: true,
  ),
];

const _stepsOnePlus = [
  _Step(
    icon: Symbols.battery_std,
    title: 'Battery Optimization',
    description:
        "OnePlus's OxygenOS has aggressive battery optimization. "
        'Set LumoVault to "Don\'t optimize" to prevent background kill.',
    instruction:
        '1. Settings > Apps > Special Access > Battery Optimization\n'
        '2. Find LumoVault\n'
        '3. Select "Don\'t optimize"',
    onOpenSettings: BrandSettings.openOnePlusBatterySettings,
  ),
  _Step(
    icon: Symbols.speed,
    title: 'Disable Deep Optimization',
    description:
        'Deep Optimization and Sleep Standby both kill background apps. '
        'Disable both for LumoVault.',
    instruction:
        '1. Settings > Battery > Battery Optimization\n'
        '2. Tap the 3-dot menu > Advanced optimization\n'
        '3. Disable "Deep optimization" AND "Sleep standby optimization"',
    onOpenSettings: BrandSettings.openOnePlusBatterySettings,
  ),
  _Step(
    icon: Symbols.lock,
    title: 'Lock in Recents (Critical)',
    description:
        'OnePlus REVERTS "Don\'t optimize" settings randomly. '
        'Locking the app in Recents is the ONLY way to prevent this.',
    instruction:
        '1. Open Recent Apps (swipe up and hold)\n'
        '2. Find LumoVault\n'
        '3. Long-press on the app card\n'
        '4. Tap the lock icon',
    isManual: true,
  ),
  _Step(
    icon: Symbols.power_settings_new,
    title: 'Auto-Launch',
    description:
        'Allow LumoVault to start automatically on boot. '
        'Without this, backup won\'t run after a restart.',
    instruction:
        '1. Settings > Apps > Auto-Launch\n'
        '2. Find LumoVault\n'
        '3. Toggle it ON',
    onOpenSettings: BrandSettings.openOnePlusAutoLaunch,
  ),
];

const _stepsOppo = [
  _Step(
    icon: Symbols.power_settings_new,
    title: 'Startup Manager',
    description:
        "Oppo's ColorOS manages startup apps. "
        'Allow LumoVault to start automatically.',
    instruction:
        '1. Open the Security app > App management > Startup Manager\n'
        '2. Find LumoVault\n'
        '3. Toggle it ON',
    onOpenSettings: BrandSettings.openOppoStartupManager,
  ),
  _Step(
    icon: Symbols.play_arrow,
    title: 'Auto Start-up',
    description:
        'Grant LumoVault permission to auto start-up. '
        'This ensures backup runs on boot.',
    instruction:
        '1. App Info > Allow Auto Start-up\n'
        '2. Toggle ON for LumoVault',
    onOpenSettings: BrandSettings.openOppoStartupManager,
  ),
  _Step(
    icon: Symbols.battery_alert,
    title: 'Power Saver',
    description:
        'Set LumoVault to bypass power saving restrictions. '
        'This prevents ColorOS from killing backup in the background.',
    instruction:
        '1. App Info > Battery Usage > Power Saver\n'
        '2. Select "Don\'t optimize" or "Run in background"',
    onOpenSettings: BrandSettings.openOppoBatterySettings,
  ),
  _Step(
    icon: Symbols.push_pin,
    title: 'Pin in Recents',
    description:
        'Pin LumoVault in the Recent Apps screen to prevent ColorOS '
        'from killing it when the screen is off.',
    instruction:
        '1. Open Recent Apps (swipe up and hold)\n'
        '2. Find LumoVault\n'
        '3. Swipe down or long-press to pin the app',
    isManual: true,
  ),
];

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
