import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/backup_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../widgets/folder_selection_widget.dart';

/// Backup settings screen — configure backup options.
///
/// Per PRD Section 8.3 settings wireframe:
/// - Auto Backup toggle
/// - Wi-Fi Only toggle
/// - Charging Only toggle
/// - Max File Size
/// - Included Folders
class BackupSettingsScreen extends ConsumerWidget {
  const BackupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(backupSettingsProvider);
    final folders = ref.watch(galleryRepositoryProvider).folders;

    return Scaffold(
      appBar: AppBar(title: const Text('Backup Settings')),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Schedule'),
          SwitchListTile(
            title: const Text('Auto Backup'),
            subtitle: const Text('Automatically back up new photos'),
            value: settings.isAutoBackupEnabled,
            onChanged: (value) {
              ref.read(backupSettingsProvider.notifier).updateAutoBackup(value);
            },
          ),
          SwitchListTile(
            title: const Text('Wi-Fi Only'),
            subtitle: const Text('Only upload on Wi-Fi'),
            value: settings.wifiOnly,
            onChanged: (value) {
              ref.read(backupSettingsProvider.notifier).updateWifiOnly(value);
            },
          ),
          SwitchListTile(
            title: const Text('Charging Only'),
            subtitle: const Text('Only upload while charging'),
            value: settings.chargingOnly,
            onChanged: (value) {
              ref
                  .read(backupSettingsProvider.notifier)
                  .updateChargingOnly(value);
            },
          ),
          const Divider(),
          const _SectionHeader(title: 'Limits'),
          ListTile(
            title: const Text('Max File Size'),
            subtitle: Text(
              settings.maxFileSize != null
                  ? _formatBytes(settings.maxFileSize!)
                  : 'No limit',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showMaxFileSizeDialog(context, ref, settings),
          ),
          const Divider(),
          FolderSelectionWidget(
            folders: folders,
            settings: settings,
            onToggleFolder: (folderPath) {
              ref
                  .read(backupSettingsProvider.notifier)
                  .toggleFolderExclusion(folderPath);
            },
          ),
          const Divider(),
          const _SectionHeader(title: 'Upload Tuning'),
          ListTile(
            title: const Text('Batch Size'),
            subtitle: Text('${settings.uploadBatchSize} files per batch'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showBatchSizeDialog(context, ref, settings),
          ),
          ListTile(
            title: const Text('Upload Delay'),
            subtitle: Text('${settings.uploadDelayMs}ms between uploads'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDelayDialog(context, ref, settings),
          ),
        ],
      ),
    );
  }

  void _showMaxFileSizeDialog(
    BuildContext context,
    WidgetRef ref,
    dynamic settings,
  ) {
    final options = [
      (null as int?, 'No limit'),
      (5 * 1024 * 1024, '5 MB'),
      (10 * 1024 * 1024, '10 MB'),
      (50 * 1024 * 1024, '50 MB'),
      (100 * 1024 * 1024, '100 MB'),
      (500 * 1024 * 1024, '500 MB'),
      (1024 * 1024 * 1024, '1 GB'),
      (2 * 1024 * 1024 * 1024, '2 GB'),
    ];

    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Max File Size'),
        children: options.map((option) {
          final (size, label) = option;
          return SimpleDialogOption(
            onPressed: () {
              ref.read(backupSettingsProvider.notifier).updateMaxFileSize(size);
              Navigator.pop(context);
            },
            child: Text(label),
          );
        }).toList(),
      ),
    );
  }

  void _showBatchSizeDialog(
    BuildContext context,
    WidgetRef ref,
    dynamic settings,
  ) {
    final options = [5, 10, 20, 50];

    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Batch Size'),
        children: options.map((size) {
          return SimpleDialogOption(
            onPressed: () {
              ref
                  .read(backupSettingsProvider.notifier)
                  .updateUploadBatchSize(size);
              Navigator.pop(context);
            },
            child: Text('$size files'),
          );
        }).toList(),
      ),
    );
  }

  void _showDelayDialog(BuildContext context, WidgetRef ref, dynamic settings) {
    final options = [
      (500, '500ms'),
      (1000, '1 second'),
      (2000, '2 seconds'),
      (5000, '5 seconds'),
    ];

    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Upload Delay'),
        children: options.map((option) {
          final (delay, label) = option;
          return SimpleDialogOption(
            onPressed: () {
              ref
                  .read(backupSettingsProvider.notifier)
                  .updateUploadDelayMs(delay);
              Navigator.pop(context);
            },
            child: Text(label),
          );
        }).toList(),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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
