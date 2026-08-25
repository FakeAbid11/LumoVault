import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/settings_section_card.dart';
import '../../data/models/app_settings.dart';
import '../providers/settings_providers.dart';

/// Main settings screen — modern Material 3 navigation hub.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: [
          // ── Account Section ──
          SettingsSectionCard(
            title: 'Account',
            children: [
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: const Text('Account'),
                subtitle: const Text('Manage your Telegram account'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/account'),
              ),
            ],
          ),

          // ── Backup & Storage Section ──
          SettingsSectionCard(
            title: 'Backup & Storage',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.backup),
                title: const Text('Auto Backup'),
                subtitle: const Text('Automatically back up new photos'),
                value: settings.autoBackupEnabled,
                onChanged: (value) {
                  ref
                      .read(appSettingsProvider.notifier)
                      .updateField((s) => s.copyWith(autoBackupEnabled: value));
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.wifi),
                title: const Text('Wi-Fi Only'),
                subtitle: const Text('Only upload on Wi-Fi'),
                value: settings.wifiOnly,
                onChanged: (value) {
                  ref
                      .read(appSettingsProvider.notifier)
                      .updateField((s) => s.copyWith(wifiOnly: value));
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Backup Settings'),
                subtitle: const Text('Advanced backup configuration'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/backup'),
              ),
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('Storage Usage'),
                subtitle: const Text('Device cache and storage cleanup'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/storage'),
              ),
            ],
          ),

          // ── Vault & Privacy Section ──
          SettingsSectionCard(
            title: 'Vault & Privacy',
            children: [
              ListTile(
                leading: const Icon(Icons.lock),
                title: const Text('Privacy & App Lock'),
                subtitle: Text(_privacyStatus(settings)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/privacy'),
              ),
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('Media Folders'),
                subtitle: const Text('Included folders and albums'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/media'),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off),
                title: const Text('Hidden Album'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/hidden'),
              ),
              ListTile(
                leading: const Icon(Icons.archive),
                title: const Text('Archive'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/archive'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Trash'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/trash'),
              ),
            ],
          ),

          // ── Preferences Section ──
          SettingsSectionCard(
            title: 'Preferences',
            children: [
              ListTile(
                leading: const Icon(Icons.palette),
                title: const Text('Appearance'),
                subtitle: Text(_themeModeName(settings.themeMode)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/appearance'),
              ),
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('Language'),
                subtitle: Text(_languageName(settings.languageCode)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/general'),
              ),
              ListTile(
                leading: const Icon(Icons.notifications),
                title: const Text('Notifications'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/notifications'),
              ),
            ],
          ),

          // ── About & System Section ──
          SettingsSectionCard(
            title: 'About & System',
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About LumoVault'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/about'),
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('Developer Options'),
                subtitle: const Text('Debug info and diagnostics'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/developer'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _languageName(String code) {
    const names = {'en': 'English', 'es': 'Spanish', 'fr': 'French'};
    return names[code] ?? code;
  }

  String _themeModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System default';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  String _privacyStatus(AppSettings s) {
    if (s.biometricLockEnabled) return 'Biometric lock enabled';
    if (s.pinLockEnabled) return 'PIN lock enabled';
    return 'No lock set';
  }
}
