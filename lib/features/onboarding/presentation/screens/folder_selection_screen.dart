import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_progress_indicator.dart';

/// Mock folder data for onboarding demonstration.
const _mockFolders = [
  _FolderInfo('Camera', '/storage/emulated/0/DCIM/Camera', 847, 2147483648),
  _FolderInfo(
    'Screenshots',
    '/storage/emulated/0/Pictures/Screenshots',
    124,
    524288000,
  ),
  _FolderInfo(
    'WhatsApp Images',
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Images',
    1023,
    1073741824,
  ),
  _FolderInfo('Download', '/storage/emulated/0/Download', 89, 268435456),
  _FolderInfo('Instagram', '/storage/emulated/0/Instagram', 256, 738197504),
];

class _FolderInfo {
  const _FolderInfo(this.name, this.path, this.count, this.sizeBytes);
  final String name;
  final String path;
  final int count;
  final int sizeBytes;
}

/// Folder selection screen — choose which folders to back up.
///
/// Displays device folders with toggle switches.
class FolderSelectionScreen extends ConsumerWidget {
  const FolderSelectionScreen({super.key});

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final selected = onboarding.selectedFolders;
    final allPaths = _mockFolders.map((f) => f.path).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Folders'),
        actions: [
          TextButton(
            onPressed: () {
              notifier.nextStep();
              context.push('/onboarding/scan');
            },
            child: const Text('Skip'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Choose folders to back up',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Select the folders containing photos and videos you want to back up.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => notifier.selectAllFolders(allPaths),
                      child: const Text('Select All'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => notifier.deselectAllFolders(),
                      child: const Text('Deselect All'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._mockFolders.map((folder) {
                  final isSelected = selected.contains(folder.path);
                  return Card(
                    elevation: 0,
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.folder_outlined,
                          color: isSelected
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      title: Text(folder.name),
                      subtitle: Text(
                        '${folder.count} items • ${_formatSize(folder.sizeBytes)}',
                      ),
                      trailing: Switch(
                        value: isSelected,
                        onChanged: (_) => notifier.toggleFolder(folder.path),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // Progress indicator
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: OnboardingProgressIndicator(
              currentStep: onboarding.currentStep,
            ),
          ),
          // Navigation buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      notifier.previousStep();
                      context.pop();
                    },
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      notifier.nextStep();
                      context.push('/onboarding/scan');
                    },
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
