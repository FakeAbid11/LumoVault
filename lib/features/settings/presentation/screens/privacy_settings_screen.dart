import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/production_providers.dart';
import '../../../../core/security/pin_service.dart';
import '../providers/settings_providers.dart';

/// Privacy settings — app lock and encryption.
class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        children: [
          const _SectionHeader(title: 'App Lock'),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Biometric Lock'),
            subtitle: const Text('Require fingerprint or face to open app'),
            value: settings.biometricLockEnabled,
            onChanged: (value) {
              ref
                  .read(appSettingsProvider.notifier)
                  .updateField((s) => s.copyWith(biometricLockEnabled: value));
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.pin),
            title: const Text('PIN Lock'),
            subtitle: const Text('Require PIN to open app'),
            value: settings.pinLockEnabled,
            onChanged: (value) {
              if (value) {
                _showPinSetupDialog(context, ref);
              } else {
                ref
                    .read(appSettingsProvider.notifier)
                    .updateField(
                      (s) =>
                          s.copyWith(pinLockEnabled: false, clearPinHash: true),
                    );
                // Drop the failure history too, otherwise re-enabling the PIN
                // later would start inside a stale lockout.
                ref.read(pinAttemptThrottleProvider).recordSuccess();
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_clock),
            title: const Text('Require on App Open'),
            subtitle: const Text('Lock every time app is opened'),
            value: settings.requireAuthOnAppOpen,
            onChanged: settings.biometricLockEnabled || settings.pinLockEnabled
                ? (value) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .updateField(
                          (s) => s.copyWith(requireAuthOnAppOpen: value),
                        );
                  }
                : null,
          ),

          const Divider(),

          const _SectionHeader(title: 'Encryption'),
          const ListTile(
            leading: Icon(Icons.enhanced_encryption),
            title: Text('End-to-End Encryption'),
            subtitle: Text('Coming soon — encrypt all backups'),
            enabled: false,
          ),
        ],
      ),
    );
  }

  void _showPinSetupDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => const _PinSetupDialog(),
    );
  }
}

/// Two-field PIN setup: the PIN is hashed with a salt before it is stored, so
/// the persisted value is never the PIN itself.
class _PinSetupDialog extends ConsumerStatefulWidget {
  const _PinSetupDialog();

  @override
  ConsumerState<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends ConsumerState<_PinSetupDialog> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pinController.text;

    if (!PinService.isValidPin(pin)) {
      setState(() {
        _error =
            'Use $kMinPinLength-$kMaxPinLength digits '
            '(numbers only).';
      });
      return;
    }
    if (pin != _confirmController.text) {
      setState(() => _error = 'PINs do not match.');
      return;
    }

    final hash = ref.read(pinServiceProvider).hashPin(pin);
    await ref
        .read(appSettingsProvider.notifier)
        .updateField((s) => s.copyWith(pinLockEnabled: true, pinHash: hash));
    await ref.read(pinAttemptThrottleProvider).recordSuccess();

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            autofocus: true,
            maxLength: kMaxPinLength,
            decoration: const InputDecoration(
              labelText: 'Enter PIN',
              hintText: 'At least $kMinPinLength digits',
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmController,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: kMaxPinLength,
            decoration: const InputDecoration(
              labelText: 'Confirm PIN',
              counterText: '',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
