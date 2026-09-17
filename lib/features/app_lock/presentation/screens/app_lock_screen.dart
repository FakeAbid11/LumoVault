import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/security/pin_service.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../providers/app_lock_provider.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Full-screen challenge shown while the app is locked.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  final _pinController = TextEditingController();
  bool _promptedOnce = false;

  @override
  void initState() {
    super.initState();
    // Show the biometric sheet immediately so the common case is one tap.
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptBiometrics());
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _promptBiometrics() async {
    if (!mounted || _promptedOnce) return;
    if (!ref.read(appSettingsProvider).biometricLockEnabled) return;
    _promptedOnce = true;
    await ref.read(appLockProvider.notifier).authenticateWithBiometrics();
  }

  Future<void> _submitPin() async {
    final ok = await ref
        .read(appLockProvider.notifier)
        .submitPin(_pinController.text);
    if (ok) return;
    if (!mounted) return;
    _pinController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final settings = ref.watch(appSettingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.lock,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'LumoVault is locked',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 32),

                  if (settings.pinLockEnabled && settings.pinHash != null) ...[
                    TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      autofocus: !settings.biometricLockEnabled,
                      maxLength: kMaxPinLength,
                      enabled: !lock.checking,
                      onSubmitted: (_) => _submitPin(),
                      decoration: const InputDecoration(
                        labelText: 'PIN',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: lock.checking ? null : _submitPin,
                      child: const Text('Unlock'),
                    ),
                  ],

                  if (settings.biometricLockEnabled) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: lock.checking
                          ? null
                          : () => ref
                                .read(appLockProvider.notifier)
                                .authenticateWithBiometrics(),
                      icon: const Icon(Symbols.fingerprint),
                      label: const Text('Use biometrics'),
                    ),
                  ],

                  if (lock.checking) ...[
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(),
                  ],

                  if (lock.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      lock.error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
