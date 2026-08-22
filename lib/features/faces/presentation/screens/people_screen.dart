import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lumovault/features/faces/data/repositories/face_repository.dart';

import '../providers/face_providers.dart';
import '../widgets/face_analysis_banner.dart';
import '../widgets/face_group_card.dart';

/// The "People" tab — displays face groups as a grid of circular thumbnails.
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(faceGroupsProvider);
    final statsAsync = ref.watch(faceStatsProvider);
    final isAnalyzing = ref.watch(faceAnalysisRunningProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          // "Detect" button to trigger analysis.
          IconButton(
            icon: const Icon(Icons.face_retouching_natural),
            tooltip: 'Detect faces',
            onPressed: isAnalyzing ? null : () => _runAnalysis(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress banner while detection is running.
          if (isAnalyzing) const FaceAnalysisBanner(),

          // Stats header.
          statsAsync.when(
            data: (stats) => stats.faceCount == 0
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Text(
                          '${stats.groupCount} people',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '· ${stats.faceCount} faces detected',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // Grid of face groups.
          Expanded(
            child: groupsAsync.when(
              data: (groups) {
                if (groups.isEmpty) {
                  return _EmptyState(
                    onDetect: () => _runAnalysis(context, ref),
                    isAnalyzing: isAnalyzing,
                  );
                }
                return _FaceGroupGrid(groups: groups);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error loading people: $e')),
            ),
          ),
        ],
      ),
    );
  }

  void _runAnalysis(BuildContext context, WidgetRef ref) {
    runFaceAnalysis(ref);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Face detection started…'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _FaceGroupGrid extends StatelessWidget {
  const _FaceGroupGrid({required this.groups});

  final List<FaceGroup> groups;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return FaceGroupCard(
          group: group,
          onTap: () => context.push('/people/${group.id}'),
          onLongPress: () => _showGroupOptions(context, group),
        );
      },
    );
  }

  void _showGroupOptions(BuildContext context, FaceGroup group) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(context, group);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete group',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, group);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, FaceGroup group) {
    final controller = TextEditingController(text: group.name ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename person'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter a name'),
          onSubmitted: (_) => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              final name = controller.text.trim();
              ProviderScope.containerOf(context)
                  .read(faceRepositoryProvider)
                  .renameGroup(group.id, name.isEmpty ? null : name);
              ProviderScope.containerOf(context).invalidate(faceGroupsProvider);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, FaceGroup group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text(
          'Faces in "${group.displayName}" will become ungrouped. '
          'They won\'t be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(context);
              ProviderScope.containerOf(
                context,
              ).read(faceRepositoryProvider).deleteGroup(group.id);
              ProviderScope.containerOf(context).invalidate(faceGroupsProvider);
              ProviderScope.containerOf(context).invalidate(faceStatsProvider);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onDetect, required this.isAnalyzing});

  final VoidCallback onDetect;
  final bool isAnalyzing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.face_outlined,
              size: 80,
              color: colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 24),
            Text(
              'No people found yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Detect faces in your photos to group\nthem by person.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: isAnalyzing ? null : onDetect,
              icon: isAnalyzing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.face_retouching_natural),
              label: Text(isAnalyzing ? 'Detecting…' : 'Detect faces'),
            ),
          ],
        ),
      ),
    );
  }
}
