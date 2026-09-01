import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/backup_providers.dart';
import '../../engine/backup_engine.dart';
import '../widgets/backup_progress_card.dart';
import '../widgets/upload_queue_list.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Backup dashboard screen — backup status and progress.
///
/// Per PRD Section 8.3 wireframes:
/// - Storage usage bar
/// - Backup status with progress
/// - Pause / Resume / Retry buttons
/// - Recent activity list
class BackupDashboardScreen extends ConsumerWidget {
  const BackupDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engineState = ref.watch(backupEngineProvider);
    final stats = ref.watch(backupStatsProvider);
    final tasks = ref.watch(uploadQueueTasksProvider);
    final backupSettings = ref.watch(backupSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup Dashboard'),
        actions: [
          if (engineState == BackupEngineState.uploading)
            IconButton(
              icon: const Icon(Symbols.pause),
              onPressed: () {
                ref.read(backupEngineProvider.notifier).pauseBackup();
              },
              tooltip: 'Pause Backup',
            ),
          if (engineState == BackupEngineState.paused)
            IconButton(
              icon: const Icon(Symbols.play_arrow),
              onPressed: () {
                ref.read(backupEngineProvider.notifier).resumeBackup();
              },
              tooltip: 'Resume Backup',
            ),
          IconButton(
            icon: const Icon(Symbols.settings),
            onPressed: () => context.push('/settings/backup/settings'),
            tooltip: 'Backup Settings',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(backupStatsProvider);
          await Future<void>.delayed(const Duration(milliseconds: 300));
        },
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Empty backup scope = silent no-op: the engine skips
                  // scanning entirely when no folders are selected. Surface
                  // it instead of letting "0 pending, nothing happening"
                  // look like a broken backup.
                  if (backupSettings.includedFolders.isEmpty)
                    _NoFoldersBanner(
                      onChooseFolders: () =>
                          context.push('/settings/backup/settings'),
                    ),
                  BackupProgressCard(
                    stats: stats,
                    engineState: engineState,
                    onPause: () {
                      ref.read(backupEngineProvider.notifier).pauseBackup();
                    },
                    onResume: () {
                      ref.read(backupEngineProvider.notifier).resumeBackup();
                    },
                    onRetryFailed: () {
                      ref.read(backupEngineProvider.notifier).retryFailed();
                    },
                  ),
                  const SizedBox(height: 24),
                  if (tasks.isNotEmpty) ...[
                    _SectionLabel(label: 'Queue', count: tasks.length),
                    const SizedBox(height: 8),
                  ],
                  UploadQueueList(
                    tasks: tasks,
                    onRetry: (taskId) {
                      ref.read(backupEngineProvider.notifier).retryTask(taskId);
                    },
                    onCancel: (taskId) {
                      ref
                          .read(backupEngineProvider.notifier)
                          .cancelTask(taskId);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when no backup folders are selected: the engine treats an empty
/// scope as a no-op, so without this the dashboard reads like a stuck backup.
class _NoFoldersBanner extends StatelessWidget {
  const _NoFoldersBanner({required this.onChooseFolders});

  final VoidCallback onChooseFolders;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.tertiaryContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.folder_off, color: scheme.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Backup is off — no folders selected',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choose which folders to back up to start protecting your '
              'photos and videos.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onTertiaryContainer.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onChooseFolders,
              icon: const Icon(Symbols.folder, size: 18),
              label: const Text('Choose folders'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small titled section label with an optional trailing count badge.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.count});

  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
