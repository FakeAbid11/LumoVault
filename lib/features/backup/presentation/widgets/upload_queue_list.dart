import 'package:flutter/material.dart';

import '../../../gallery/data/models/upload_task.dart';

/// Upload queue list widget showing pending/in-progress/failed items.
///
/// Per PRD Section 8.3 wireframes, shows recent activity with per-item
/// retry/cancel actions.
class UploadQueueList extends StatelessWidget {
  const UploadQueueList({
    super.key,
    required this.tasks,
    required this.onRetry,
    required this.onCancel,
    this.showAll = false,
  });

  final List<UploadTask> tasks;
  final void Function(String taskId) onRetry;
  final void Function(String taskId) onCancel;
  final bool showAll;

  @override
  Widget build(BuildContext context) {
    final displayTasks = showAll ? tasks : tasks.take(20).toList();

    if (displayTasks.isEmpty) {
      return _buildEmptyState(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'UPLOAD QUEUE',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        // shrinkWrap + NeverScrollableScrollPhysics, not Expanded: this
        // widget is embedded inside backup_dashboard_screen's own
        // ListView, which gives unbounded height to its children. An
        // Expanded here threw "RenderFlex children have non-zero flex but
        // incoming height constraints are unbounded" the moment the list
        // went from empty (which took the Center-widget branch above and
        // never hit this) to non-empty — crashing the whole screen blank
        // as soon as anything was actually queued for backup.
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayTasks.length,
          itemBuilder: (context, index) {
            final task = displayTasks[index];
            return _UploadQueueItem(
              task: task,
              onRetry: () => onRetry(task.id),
              onCancel: () => onCancel(task.id),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_queue,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No uploads in queue',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'New media will be queued automatically',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadQueueItem extends StatelessWidget {
  const _UploadQueueItem({
    required this.task,
    required this.onRetry,
    required this.onCancel,
  });

  final UploadTask task;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _buildStatusIcon(context),
      title: Text(
        task.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      subtitle: _buildSubtitle(context),
      trailing: _buildActions(context),
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (task.status) {
      case UploadStatus.queued:
        return Icon(
          Icons.schedule,
          color: colorScheme.onSurfaceVariant,
          size: 24,
        );
      case UploadStatus.uploading:
        return SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            value: task.progress,
            strokeWidth: 2.5,
            color: colorScheme.primary,
          ),
        );
      case UploadStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green, size: 24);
      case UploadStatus.failed:
        return Icon(Icons.error_outline, color: colorScheme.error, size: 24);
      case UploadStatus.paused:
        return Icon(
          Icons.pause_circle_outline,
          color: colorScheme.onSurfaceVariant,
          size: 24,
        );
    }
  }

  Widget? _buildSubtitle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (task.status) {
      case UploadStatus.uploading:
        return Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 4,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(task.progress * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      case UploadStatus.failed:
        return Text(
          task.error?.displayMessage ?? 'Upload failed',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case UploadStatus.completed:
        return Text(
          _formatBytes(task.fileSize),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.green),
        );
      case UploadStatus.queued:
      case UploadStatus.paused:
        return Text(
          _formatBytes(task.fileSize),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        );
    }
  }

  Widget? _buildActions(BuildContext context) {
    switch (task.status) {
      case UploadStatus.failed:
        if (task.canRetry) {
          return IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: onRetry,
            tooltip: 'Retry',
          );
        }
        return IconButton(
          icon: const Icon(Icons.close),
          onPressed: onCancel,
          tooltip: 'Remove',
        );
      case UploadStatus.queued:
      case UploadStatus.paused:
        return IconButton(
          icon: const Icon(Icons.close),
          onPressed: onCancel,
          tooltip: 'Cancel',
        );
      default:
        return null;
    }
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
