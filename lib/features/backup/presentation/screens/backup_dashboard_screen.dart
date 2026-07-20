import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/backup_providers.dart';
import '../../engine/backup_engine.dart';
import '../widgets/backup_progress_card.dart';
import '../widgets/upload_queue_list.dart';

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
    final stats = ref.read(backupEngineProvider.notifier).stats;
    final tasks = ref.watch(uploadQueueTasksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup Dashboard'),
        actions: [
          if (engineState == BackupEngineState.uploading)
            IconButton(
              icon: const Icon(Icons.pause),
              onPressed: () {
                ref.read(backupEngineProvider.notifier).pauseBackup();
              },
              tooltip: 'Pause Backup',
            ),
          if (engineState == BackupEngineState.paused)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () {
                ref.read(backupEngineProvider.notifier).resumeBackup();
              },
              tooltip: 'Resume Backup',
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings/backup/settings'),
            tooltip: 'Backup Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (engineState == BackupEngineState.idle ||
                    engineState == BackupEngineState.error)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: FilledButton.icon(
                      onPressed: () async {
                        final notifier = ref.read(
                          backupEngineProvider.notifier,
                        );
                        await notifier.scanAndEnqueue();
                        await notifier.startBackup();
                      },
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Start Backup'),
                    ),
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
                const SizedBox(height: 16),
                UploadQueueList(
                  tasks: tasks,
                  onRetry: (taskId) {
                    ref.read(backupEngineProvider.notifier).cancelTask(taskId);
                  },
                  onCancel: (taskId) {
                    ref.read(backupEngineProvider.notifier).cancelTask(taskId);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
