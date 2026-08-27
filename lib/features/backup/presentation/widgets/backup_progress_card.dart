import 'package:flutter/material.dart';

import '../../engine/backup_engine.dart';
import '../../../../core/theme/status_color.dart';
import '../../../../core/utils/format_utils.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Backup progress card showing current backup status per PRD Section 8.3.
///
/// Displays:
/// - Status: Uploading (3 of 147)
/// - Progress bar with percentage
/// - Speed / ETA (if available)
/// - Pause / Resume / Retry buttons
class BackupProgressCard extends StatelessWidget {
  const BackupProgressCard({
    super.key,
    required this.stats,
    required this.engineState,
    required this.onPause,
    required this.onResume,
    required this.onRetryFailed,
  });

  final BackupStats stats;
  final BackupEngineState engineState;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRetryFailed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusHeader(context),
            const SizedBox(height: 12),
            _buildProgressBar(context),
            const SizedBox(height: 12),
            _buildStatsRow(context),
            const SizedBox(height: 12),
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    IconData icon;
    String statusText;
    Color iconColor;

    switch (engineState) {
      case BackupEngineState.idle:
        icon = Symbols.cloud_done;
        statusText = stats.pendingCount == 0
            ? 'All backed up'
            : 'Ready to backup (${stats.pendingCount} pending)';
        iconColor = colorScheme.primary;
      case BackupEngineState.scanning:
        icon = Symbols.sync;
        statusText = 'Scanning media...';
        iconColor = colorScheme.tertiary;
      case BackupEngineState.uploading:
        icon = Symbols.cloud_upload;
        statusText = 'Uploading (${stats.progressDisplay})';
        iconColor = colorScheme.primary;
      case BackupEngineState.paused:
        icon = Symbols.pause_circle;
        statusText = 'Backup paused';
        iconColor = colorScheme.error;
      case BackupEngineState.error:
        icon = Symbols.error;
        statusText = 'Backup error';
        iconColor = colorScheme.error;
    }

    return Row(
      children: [
        Icon(icon, color: iconColor, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(statusText, style: Theme.of(context).textTheme.titleMedium),
              if (stats.lastBackupAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Last backup: ${_formatDateTime(stats.lastBackupAt!)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${stats.progressPercent.toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '${formatBytes(stats.backedUpBytes)} / ${formatBytes(stats.totalBytes)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: stats.progress,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
          backgroundColor: colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(
            engineState == BackupEngineState.paused
                ? colorScheme.error
                : colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(
          context,
          label: 'Pending',
          value: stats.pendingCount.toString(),
          color: colorScheme.tertiary,
        ),
        _buildStatItem(
          context,
          label: 'Uploading',
          value: stats.uploadingCount.toString(),
          color: colorScheme.primary,
        ),
        _buildStatItem(
          context,
          label: 'Completed',
          value: stats.backedUpCount.toString(),
          color: successColor,
        ),
        _buildStatItem(
          context,
          label: 'Failed',
          value: stats.failedCount.toString(),
          color: colorScheme.error,
        ),
      ],
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    // Backup initiation lives in auto-backup and the media viewer's per-photo
    // button; this card only surfaces controls for a run that's already in
    // flight (pause/resume) and recovery for failures (retry).
    final buttons = <Widget>[
      if (engineState == BackupEngineState.uploading)
        OutlinedButton.icon(
          onPressed: onPause,
          icon: const Icon(Symbols.pause),
          label: const Text('Pause'),
        )
      else if (engineState == BackupEngineState.paused)
        FilledButton.icon(
          onPressed: onResume,
          icon: const Icon(Symbols.play_arrow),
          label: const Text('Resume'),
        ),
      if (stats.failedCount > 0)
        OutlinedButton.icon(
          onPressed: onRetryFailed,
          icon: const Icon(Symbols.refresh),
          label: const Text('Retry Failed'),
        ),
    ];

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} hr ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
