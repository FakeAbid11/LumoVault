import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          const _SectionHeader(title: 'Theme'),
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

          const Divider(),

          const _SectionHeader(title: 'Colors'),
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

          const Divider(),

          const _SectionHeader(title: 'Gallery'),
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
      case 0:
        return 'Small (3 columns)';
      case 1:
        return 'Medium (2 columns)';
      case 2:
        return 'Large (1 column)';
      default:
        return 'Medium (2 columns)';
    }
  }

  void _showGridPicker(BuildContext context, WidgetRef ref, dynamic settings) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Grid Size'),
        children: [
          _gridOption(context, ref, 0, 'Small (3 columns)'),
          _gridOption(context, ref, 1, 'Medium (2 columns)'),
          _gridOption(context, ref, 2, 'Large (1 column)'),
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
