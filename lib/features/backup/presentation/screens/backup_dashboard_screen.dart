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
    final stats = ref.watch(backupStatsProvider);
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
