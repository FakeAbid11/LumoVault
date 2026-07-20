import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';

/// General settings screen — language and basic options.
class GeneralSettingsScreen extends ConsumerWidget {
  const GeneralSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('General')),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Language'),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('App Language'),
            subtitle: Text(_languageName(settings.languageCode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLanguagePicker(context, ref, settings),
          ),

          const Divider(),

          const _SectionHeader(title: 'Data'),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Reset Onboarding'),
            subtitle: const Text('Show the onboarding flow again'),
            onTap: () => _confirmResetOnboarding(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Reset All Settings'),
            subtitle: const Text('Restore all settings to defaults'),
            onTap: () => _confirmResetAll(context, ref),
          ),
        ],
      ),
    );
  }

  String _languageName(String code) {
    const names = {'en': 'English', 'es': 'Spanish', 'fr': 'French'};
    return names[code] ?? code;
  }

  void _showLanguagePicker(
    BuildContext context,
    WidgetRef ref,
    dynamic settings,
  ) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select Language'),
        children: [
          _languageOption(context, ref, 'en', 'English'),
          _languageOption(context, ref, 'es', 'Spanish'),
          _languageOption(context, ref, 'fr', 'French'),
        ],
      ),
    );
  }

  SimpleDialogOption _languageOption(
    BuildContext context,
    WidgetRef ref,
    String code,
    String name,
  ) {
    return SimpleDialogOption(
      onPressed: () {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(languageCode: code));
        Navigator.of(context).pop();
      },
      child: Text(name),
    );
  }

  void _confirmResetOnboarding(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Onboarding?'),
        content: const Text(
          'This will show the onboarding flow on next app launch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(appSettingsProvider.notifier)
                  .updateField((s) => s.copyWith(onboardingCompleted: false));
              Navigator.of(context).pop();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _confirmResetAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset All Settings?'),
        content: const Text(
          'This will restore all settings to their default values. '
          'Your data will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(appSettingsProvider.notifier).resetToDefaults();
              Navigator.of(context).pop();
            },
            child: const Text('Reset'),
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
