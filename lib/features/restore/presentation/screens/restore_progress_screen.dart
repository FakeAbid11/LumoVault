import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/restore_providers.dart';
import '../../data/models/restore_progress.dart';

/// Restore progress screen per PRD Section 10.3.
///
/// Shows real-time progress with:
/// - Overall progress bar
/// - Current phase description
/// - Items completed / total
/// - Speed and ETA
/// - Pause/Resume and Cancel buttons
class RestoreProgressScreen extends ConsumerWidget {
  const RestoreProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(restoreProgressProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _showCancelDialog(context, ref);
        }
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  Icon(
                    _getPhaseIcon(progress.phase),
                    size: 64,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Restoring Your Library',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    progress.phaseDescription,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onPrimary.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 48),
                  // Progress bar
                  _buildProgressBar(context, progress),
                  const SizedBox(height: 24),
                  // Stats
                  _buildStats(context, progress),
                  const SizedBox(height: 16),
                  // Current file
                  if (progress.currentFileName != null)
                    _buildCurrentFile(context, progress),
                  const Spacer(),
                  // Action buttons
                  _buildActionButtons(context, ref, progress),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, RestoreProgress progress) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress.overallProgress,
            minHeight: 12,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.onPrimary.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${progress.progressPercent.toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildStats(BuildContext context, RestoreProgress progress) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Items',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onPrimary.withValues(alpha: 0.8),
                ),
              ),
              Text(
                progress.progressDisplay,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (progress.bytesDisplay.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Downloaded',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  progress.bytesDisplay,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
          if (progress.speedDisplay.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Speed',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  progress.speedDisplay,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
          if (progress.failedItems > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Failed',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  '${progress.failedItems}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
          if (progress.skippedItems > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Skipped',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  '${progress.skippedItems}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withValues(alpha: 0.8),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrentFile(BuildContext context, RestoreProgress progress) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.file_present,
            size: 16,
            color: Theme.of(
              context,
            ).colorScheme.onPrimary.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              progress.currentFileName!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    WidgetRef ref,
    RestoreProgress progress,
  ) {
    if (progress.isComplete) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => context.go('/timeline'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.onPrimary,
            foregroundColor: Theme.of(context).colorScheme.primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text(
            'View Your Library',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    if (progress.isFailed || progress.isCancelled) {
      return Column(
        children: [
          if (progress.error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.onError,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      progress.error!.displayMessage,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onError,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                ref.read(restoreProgressProvider.notifier).reset();
                context.go('/onboarding/welcome');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.onPrimary,
                foregroundColor: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'Start Fresh',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _showCancelDialog(context, ref),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              side: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.onPrimary.withValues(alpha: 0.5),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              if (progress.isPaused) {
                ref.read(resumeRestoreProvider)();
              } else {
                ref.read(pauseRestoreProvider)();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.onPrimary,
              foregroundColor: Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(progress.isPaused ? 'Resume' : 'Pause'),
          ),
        ),
      ],
    );
  }

  IconData _getPhaseIcon(RestorePhase phase) {
    switch (phase) {
      case RestorePhase.detecting:
        return Icons.search;
      case RestorePhase.manifestDownload:
        return Icons.description;
      case RestorePhase.metadataDownload:
        return Icons.cloud_download;
      case RestorePhase.databaseRebuild:
        return Icons.storage;
      case RestorePhase.thumbnailDownload:
        return Icons.photo_library;
      case RestorePhase.originalDownload:
        return Icons.high_quality;
      case RestorePhase.completed:
        return Icons.check_circle;
      case RestorePhase.failed:
        return Icons.error;
      case RestorePhase.cancelled:
        return Icons.cancel;
      case RestorePhase.paused:
        return Icons.pause_circle;
    }
  }

  void _showCancelDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Restore?'),
        content: const Text(
          'Are you sure you want to cancel the restore? '
          'You can resume it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continue Restore'),
          ),
          TextButton(
            onPressed: () {
              ref.read(cancelRestoreProvider)();
              Navigator.of(context).pop();
              context.go('/onboarding/welcome');
            },
            child: Text(
              'Cancel',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
