import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';

/// Media settings — folders, albums, backup content options.
class MediaSettingsScreen extends ConsumerWidget {
  const MediaSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Media Settings')),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Backup Content'),
          SwitchListTile(
            secondary: const Icon(Icons.photo),
            title: const Text('Backup Photos'),
            subtitle: const Text('Include photos in backups'),
            value: settings.backupPhotos,
            onChanged: (value) {
              ref
                  .read(appSettingsProvider.notifier)
                  .updateField((s) => s.copyWith(backupPhotos: value));
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.videocam),
            title: const Text('Backup Videos'),
            subtitle: const Text('Include videos in backups'),
            value: settings.backupVideos,
            onChanged: (value) {
              ref
                  .read(appSettingsProvider.notifier)
                  .updateField((s) => s.copyWith(backupVideos: value));
            },
          ),

          const Divider(),

          const _SectionHeader(title: 'Folders'),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Included Folders'),
            subtitle: Text(
              settings.includedFolders.isEmpty
                  ? 'All folders (default)'
                  : '${settings.includedFolders.length} folder(s) selected',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showIncludedFolders(context, ref, settings),
          ),
          ListTile(
            leading: const Icon(Icons.folder_off),
            title: const Text('Excluded Folders'),
            subtitle: Text(
              settings.excludedFolders.isEmpty
                  ? 'None'
                  : '${settings.excludedFolders.length} folder(s) excluded',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showExcludedFolders(context, ref, settings),
          ),

          const Divider(),

          const _SectionHeader(title: 'Albums'),
          ListTile(
            leading: const Icon(Icons.album),
            title: const Text('Excluded Albums'),
            subtitle: Text(
              settings.excludedAlbums.isEmpty
                  ? 'None'
                  : '${settings.excludedAlbums.length} album(s) excluded',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showExcludedAlbums(context, ref, settings),
          ),

          const Divider(),

          const _SectionHeader(title: 'Trash'),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Trash Duration'),
            subtitle: Text('${settings.trashDurationDays} days'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showTrashDuration(context, ref, settings),
          ),

          const Divider(),

          const _SectionHeader(title: 'Size Limits'),
          ListTile(
            leading: const Icon(Icons.file_upload),
            title: const Text('Max File Size'),
            subtitle: Text(_maxFileSizeDisplay(settings.maxFileSizeBytes)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showMaxFileSize(context, ref, settings),
          ),
        ],
      ),
    );
  }

  String _maxFileSizeDisplay(int bytes) {
    if (bytes == 0) return 'No limit';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _showIncludedFolders(
    BuildContext context,
    WidgetRef ref,
    dynamic settings,
  ) {
    // In production, show a multi-select dialog with device folders.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Folder selection — coming soon')),
    );
  }

  void _showExcludedFolders(
    BuildContext context,
    WidgetRef ref,
    dynamic settings,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Folder exclusion — coming soon')),
    );
  }

  void _showExcludedAlbums(
    BuildContext context,
    WidgetRef ref,
    dynamic settings,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Album exclusion — coming soon')),
    );
  }

  void _showTrashDuration(
    BuildContext context,
    WidgetRef ref,
    dynamic settings,
  ) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Trash Duration'),
        children: [
          _trashOption(context, ref, 7, '7 days'),
          _trashOption(context, ref, 14, '14 days'),
          _trashOption(context, ref, 30, '30 days'),
          _trashOption(context, ref, 60, '60 days'),
          _trashOption(context, ref, 90, '90 days'),
          _trashOption(context, ref, 365, '1 year'),
          _trashOption(context, ref, 0, 'Never delete'),
        ],
      ),
    );
  }

  SimpleDialogOption _trashOption(
    BuildContext context,
    WidgetRef ref,
    int days,
    String label,
  ) {
    return SimpleDialogOption(
      onPressed: () {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(trashDurationDays: days));
        Navigator.of(context).pop();
      },
      child: Text(label),
    );
  }

  void _showMaxFileSize(BuildContext context, WidgetRef ref, dynamic settings) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Max File Size'),
        children: [
          _sizeOption(context, ref, 0, 'No limit'),
          _sizeOption(context, ref, 5 * 1024 * 1024, '5 MB'),
          _sizeOption(context, ref, 10 * 1024 * 1024, '10 MB'),
          _sizeOption(context, ref, 50 * 1024 * 1024, '50 MB'),
          _sizeOption(context, ref, 100 * 1024 * 1024, '100 MB'),
          _sizeOption(context, ref, 500 * 1024 * 1024, '500 MB'),
          _sizeOption(context, ref, 1024 * 1024 * 1024, '1 GB'),
        ],
      ),
    );
  }

  SimpleDialogOption _sizeOption(
    BuildContext context,
    WidgetRef ref,
    int bytes,
    String label,
  ) {
    return SimpleDialogOption(
      onPressed: () {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(maxFileSizeBytes: bytes));
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
