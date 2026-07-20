import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';

/// Privacy settings — locks, sensitive content, clipboard.
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

          const _SectionHeader(title: 'Content'),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off),
            title: const Text('Hide Sensitive Albums'),
            subtitle: const Text('Hide certain albums from view'),
            value: settings.hideSensitiveAlbums,
            onChanged: (value) {
              ref
                  .read(appSettingsProvider.notifier)
                  .updateField((s) => s.copyWith(hideSensitiveAlbums: value));
            },
          ),

          const Divider(),

          const _SectionHeader(title: 'Data Protection'),
          SwitchListTile(
            secondary: const Icon(Icons.content_paste),
            title: const Text('Clear Clipboard After Share'),
            subtitle: const Text('Auto-clear clipboard 60s after sharing'),
            value: settings.clearClipboardAfterShare,
            onChanged: (value) {
              ref
                  .read(appSettingsProvider.notifier)
                  .updateField(
                    (s) => s.copyWith(clearClipboardAfterShare: value),
                  );
            },
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
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set PIN'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 8,
          decoration: const InputDecoration(
            hintText: 'Enter PIN',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.length >= 4) {
                // In production, hash the PIN before storing.
                ref
                    .read(appSettingsProvider.notifier)
                    .updateField(
                      (s) => s.copyWith(
                        pinLockEnabled: true,
                        pinHash: controller.text,
                      ),
                    );
                Navigator.of(context).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
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
