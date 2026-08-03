import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/backup_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../widgets/folder_selection_widget.dart';
import '../../data/models/backup_settings.dart';

/// Enhanced backup settings screen with all production features.
class BackupSettingsScreenV2 extends ConsumerWidget {
  const BackupSettingsScreenV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(backupSettingsProvider);
    final stats = ref.watch(backupStatsProvider);
    final isBackupActive = ref.watch(isBackupActiveProvider);
    final isPaused = ref.watch(isBackupPausedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup Settings'),
        actions: [
          if (isBackupActive)
            IconButton(
              icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
              tooltip: isPaused ? 'Resume' : 'Pause',
              onPressed: () {
                final notifier = ref.read(backupEngineProvider.notifier);
                if (isPaused) {
                  notifier.resumeBackup();
                } else {
                  notifier.pauseBackup();
                }
              },
            ),
        ],
      ),
      body: ListView(
        children: [
          // -- Status --
          if (isBackupActive) ...[
            const _SectionHeader(title: 'Status'),
            _buildStatusTile(context, stats, isPaused),
            const Divider(),
          ],

          // -- Schedule --
          const _SectionHeader(title: 'Schedule'),
          SwitchListTile(
            secondary: const Icon(Icons.backup),
            title: const Text('Auto Backup'),
            subtitle: const Text('Automatically back up new photos'),
            value: settings.isAutoBackupEnabled,
            onChanged: (value) {
              ref.read(backupSettingsProvider.notifier).updateAutoBackup(value);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi),
            title: const Text('Wi-Fi Only'),
            subtitle: const Text('Only upload on Wi-Fi'),
            value: settings.wifiOnly,
            onChanged: (value) {
              ref.read(backupSettingsProvider.notifier).updateWifiOnly(value);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.battery_charging_full),
            title: const Text('Charging Only'),
            subtitle: const Text('Only upload while charging'),
            value: settings.chargingOnly,
            onChanged: (value) {
              ref
                  .read(backupSettingsProvider.notifier)
                  .updateChargingOnly(value);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.phone_android),
            title: const Text('Background Backup'),
            subtitle: const Text('Continue backup when app is minimized'),
            value: true,
            onChanged: (value) {
              // Wire to background backup service.
            },
          ),

          const Divider(),

          // -- Content --
          const _SectionHeader(title: 'Content'),
          SwitchListTile(
            secondary: const Icon(Icons.photo),
            title: const Text('Back Up Photos'),
            value: settings.backupPhotos,
            onChanged: (value) {
              ref
                  .read(backupSettingsProvider.notifier)
                  .updateBackupPhotos(value);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.videocam),
            title: const Text('Back Up Videos'),
            value: settings.backupVideos,
            onChanged: (value) {
              ref
                  .read(backupSettingsProvider.notifier)
                  .updateBackupVideos(value);
            },
          ),

          const Divider(),

          // -- Manual Actions --
          const _SectionHeader(title: 'Actions'),
          ListTile(
            leading: const Icon(Icons.play_circle),
            title: const Text('Start Backup Now'),
            subtitle: const Text('Begin backing up pending items'),
            onTap: isBackupActive
                ? null
                : () {
                    ref.read(backupEngineProvider.notifier).startBackup();
                  },
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Retry Failed Uploads'),
            subtitle: Text('${stats.failedCount} failed item(s)'),
            onTap: stats.failedCount > 0
                ? () {
                    ref.read(backupEngineProvider.notifier).retryFailed();
                  }
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep),
            title: const Text('Clear Finished'),
            subtitle: const Text('Remove completed items from queue'),
            onTap: () {
              ref.read(backupEngineProvider.notifier).clearFinished();
            },
          ),

          const Divider(),

          // -- Limits --
          const _SectionHeader(title: 'Limits'),
          ListTile(
            leading: const Icon(Icons.file_upload),
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

          // -- Upload Tuning --
          const _SectionHeader(title: 'Upload Tuning'),
          ListTile(
            leading: const Icon(Icons.queue),
            title: const Text('Batch Size'),
            subtitle: Text('${settings.uploadBatchSize} files per batch'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showBatchSizeDialog(context, ref, settings),
          ),
          ListTile(
            leading: const Icon(Icons.timer),
            title: const Text('Upload Delay'),
            subtitle: Text('${settings.uploadDelayMs}ms between uploads'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDelayDialog(context, ref, settings),
          ),

          const Divider(),

          // -- Folders --
          const _SectionHeader(title: 'Folders'),
          ref
              .watch(deviceFoldersProvider)
              .when(
                data: (folders) => FolderSelectionWidget(
                  folders: folders,
                  settings: settings,
                  onToggleFolder: (folderPath) {
                    ref
                        .read(backupSettingsProvider.notifier)
                        .toggleFolderExclusion(folderPath);
                  },
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Could not load folders: $error'),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildStatusTile(BuildContext context, dynamic stats, bool isPaused) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPaused ? Icons.pause_circle : Icons.backup,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isPaused ? 'Backup Paused' : 'Backup Active',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: stats.progress,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.onPrimaryContainer.withAlpha(30),
          ),
          const SizedBox(height: 8),
          Text(
            '${stats.backedUpCount} of ${stats.totalMediaItems} items '
            '(${(stats.progress * 100).toStringAsFixed(1)}%)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  void _showMaxFileSizeDialog(
    BuildContext context,
    WidgetRef ref,
    BackupSettings settings,
  ) {
    final options = [
      (0, 'No limit'),
      (5 * 1024 * 1024, '5 MB'),
      (10 * 1024 * 1024, '10 MB'),
      (50 * 1024 * 1024, '50 MB'),
      (100 * 1024 * 1024, '100 MB'),
      (500 * 1024 * 1024, '500 MB'),
      (1024 * 1024 * 1024, '1 GB'),
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
    BackupSettings settings,
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

  void _showDelayDialog(
    BuildContext context,
    WidgetRef ref,
    BackupSettings settings,
  ) {
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
    if (bytes == 0) return 'No limit';
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
