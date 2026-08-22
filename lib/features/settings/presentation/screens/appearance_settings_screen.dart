import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/settings_section_card.dart';
import '../../data/models/app_settings.dart';
import '../providers/settings_providers.dart';

/// Appearance settings — theme, grid, animations.
class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        children: [
          const SizedBox(height: 4),
          SettingsSectionCard(
            title: 'Theme',
            children: [
              _themeTile(
                context,
                ref,
                settings,
                ThemeMode.system,
                'System default',
                Icons.brightness_auto,
              ),
              _themeTile(
                context,
                ref,
                settings,
                ThemeMode.light,
                'Light',
                Icons.light_mode,
              ),
              _themeTile(
                context,
                ref,
                settings,
                ThemeMode.dark,
                'Dark',
                Icons.dark_mode,
              ),
            ],
          ),
          SettingsSectionCard(
            title: 'Colors',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.palette),
                title: const Text('Dynamic Color'),
                subtitle: const Text('Use system wallpaper colors'),
                value: settings.useDynamicColor,
                onChanged: (value) {
                  ref
                      .read(appSettingsProvider.notifier)
                      .updateField((s) => s.copyWith(useDynamicColor: value));
                },
              ),
            ],
          ),
          SettingsSectionCard(
            title: 'Gallery',
            children: [
              ListTile(
                leading: const Icon(Icons.grid_view),
                title: const Text('Grid Size'),
                subtitle: Text(_gridSizeName(settings.gridSize)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showGridPicker(context, ref, settings),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.view_module),
                title: const Text('Compact Mode'),
                subtitle: const Text('Show more items on screen'),
                value: settings.compactMode,
                onChanged: (value) {
                  ref
                      .read(appSettingsProvider.notifier)
                      .updateField((s) => s.copyWith(compactMode: value));
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.animation),
                title: const Text('Animations'),
                subtitle: const Text('Enable transition animations'),
                value: settings.animationsEnabled,
                onChanged: (value) {
                  ref
                      .read(appSettingsProvider.notifier)
                      .updateField((s) => s.copyWith(animationsEnabled: value));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _themeTile(
    BuildContext context,
    WidgetRef ref,
    dynamic settings,
    ThemeMode mode,
    String label,
    IconData icon,
  ) {
    final isSelected = settings.themeMode == mode;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: isSelected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: () {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(themeMode: mode));
      },
    );
  }

  String _gridSizeName(dynamic gridSize) {
    switch (gridSize) {
      case GridSize.small:
        return 'Small (5 per row)';
      case GridSize.medium:
        return 'Medium (4 per row)';
      case GridSize.large:
        return 'Large (3 per row)';
      default:
        return 'Medium (4 per row)';
    }
  }

  void _showGridPicker(BuildContext context, WidgetRef ref, dynamic settings) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Grid Size'),
        children: [
          _gridOption(context, ref, 0, 'Small (5 per row)'),
          _gridOption(context, ref, 1, 'Medium (4 per row)'),
          _gridOption(context, ref, 2, 'Large (3 per row)'),
        ],
      ),
    );
  }

  SimpleDialogOption _gridOption(
    BuildContext context,
    WidgetRef ref,
    int index,
    String label,
  ) {
    return SimpleDialogOption(
      onPressed: () {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(gridSize: GridSize.values[index]));
        Navigator.of(context).pop();
      },
      child: Text(label),
    );
  }
}
