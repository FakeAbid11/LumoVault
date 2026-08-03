import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/gallery_providers.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_progress_indicator.dart';

/// Folder selection screen — choose which folders to back up.
///
/// Displays device folders with toggle switches.
class FolderSelectionScreen extends ConsumerStatefulWidget {
  const FolderSelectionScreen({super.key});

  @override
  ConsumerState<FolderSelectionScreen> createState() =>
      _FolderSelectionScreenState();
}

class _FolderSelectionScreenState extends ConsumerState<FolderSelectionScreen> {
  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    try {
      // Invalidate first so a previously failed provider (whose error is
      // cached) is re-fetched on retry instead of re-throwing the same
      // stale failure forever.
      ref.invalidate(deviceFoldersProvider);
      final folders = await ref.read(deviceFoldersProvider.future);
      if (!mounted) return;
      ref.read(onboardingProvider.notifier).setDeviceFolders(folders);
      // Auto-select all folders by default.
      ref
          .read(onboardingProvider.notifier)
          .selectAllFolders(folders.map((f) => f.path).toList());
    } catch (e) {
      debugPrint('[FolderSelectionScreen] Failed to load folders: $e');
      // The failure is already surfaced by the .when(error:) branch in
      // build — swallowing here just prevents an unhandled async exception
      // on top of the visible error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final selected = onboarding.selectedFolders;
    final foldersAsync = ref.watch(deviceFoldersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Folders'),
        actions: [
          TextButton(
            onPressed: () {
              notifier.nextStep();
              context.push('/onboarding/telegram');
            },
            child: const Text('Skip'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: foldersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.folder_off, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Could not load folders',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Grant storage permission in Settings to continue.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadFolders,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (folders) {
                if (folders.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.folder_off, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            'No folders found',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No photo or video folders were detected on this device.',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final allPaths = folders.map((f) => f.path).toList();
                return ListView(
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
                    ...folders.map((folder) {
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
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.folder_outlined,
                              color: isSelected
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          title: Text(folder.name),
                          subtitle: Text('${folder.totalItems} items'),
                          trailing: Switch(
                            value: isSelected,
                            onChanged: (_) =>
                                notifier.toggleFolder(folder.path),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
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
                      context.push('/onboarding/telegram');
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
