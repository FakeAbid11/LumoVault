import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/gallery_providers.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../providers/people_providers.dart';
import '../widgets/person_tile.dart';

class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  final Set<int> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _startFaceScanningIfNeeded();
  }

  Future<void> _startFaceScanningIfNeeded() async {
    final controller = ref.read(faceScanControllerProvider);
    if (controller.isScanning) return;

    final faceCount = await ref.read(faceCountProvider.future);
    if (!mounted || controller.isScanning) return;

    if (faceCount == 0) {
      controller.start();
    }
  }

  void _exitSelection() {
    setState(() => _selectedIds.clear());
  }

  void _toggleSelection(int personId) {
    setState(() {
      if (_selectedIds.contains(personId)) {
        _selectedIds.remove(personId);
      } else {
        _selectedIds.add(personId);
      }
    });
  }

  void _enterSelection(int personId) {
    setState(() {
      _selectedIds.clear();
      _selectedIds.add(personId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final peopleAsync = ref.watch(peopleProvider);
    final scanProgress = ref.watch(faceScanProgressProvider);
    final deviceAssets = ref.watch(deviceAssetsProvider);

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelection();
      },
      child: Scaffold(
        appBar: _buildAppBar(scanProgress),
        body: _buildBody(context, ref, peopleAsync, scanProgress, deviceAssets),
        bottomNavigationBar: _selectionMode
            ? _buildActionBar(context, ref)
            : null,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(FaceScanProgress scanProgress) {
    if (_selectionMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _exitSelection,
        ),
        title: Text('${_selectedIds.length} selected'),
        actions: [
          IconButton(
            icon: const Icon(Icons.merge),
            tooltip: 'Merge selected',
            onPressed: _selectedIds.length >= 2
                ? () => _showMergeDialog()
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete selected',
            onPressed: () => _showDeleteDialog(),
          ),
        ],
      );
    }

    return AppBar(
      title: const Text('People'),
      actions: [
        if (scanProgress.isScanning)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: scanProgress.progress,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<dynamic>> peopleAsync,
    FaceScanProgress scanProgress,
    AsyncValue<List<AssetEntity>> deviceAssets,
  ) {
    return Column(
      children: [
        // Scanning banner
        if (scanProgress.isScanning)
          Material(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: scanProgress.progress,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Scanning for faces (${scanProgress.current} / ${scanProgress.total})...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // People grid or empty/error state.
        Expanded(
          child: peopleAsync.when(
            data: (people) {
              if (people.isEmpty && !scanProgress.isScanning) {
                return _buildEmptyState(context, ref, deviceAssets);
              }
              if (people.isEmpty) {
                return _buildScanningState(scanProgress);
              }
              return _buildPeopleGrid(context, ref, people);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) =>
                _buildErrorState(context, error.toString()),
          ),
        ),
      ],
    );
  }

  Widget _buildScanningState(FaceScanProgress scanProgress) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: CircularProgressIndicator(
              value: scanProgress.progress,
              strokeWidth: 4,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Scanning for faces...',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '${scanProgress.current} / ${scanProgress.total} photos',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<AssetEntity>> deviceAssets,
  ) {
    return EmptyState(
      icon: Icons.people_outline,
      title: 'No people found',
      message:
          'Faces in your photos will be grouped here.\nTap below to start scanning.',
      action: FilledButton.icon(
        onPressed: () => ref.read(faceScanControllerProvider).start(),
        icon: const Icon(Icons.person_search),
        label: const Text('Scan for Faces'),
      ),
    );
  }

  Widget _buildPeopleGrid(
    BuildContext context,
    WidgetRef ref,
    List<dynamic> people,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(peopleProvider);
        ref.invalidate(faceCountProvider);
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.8,
        ),
        itemCount: people.length,
        itemBuilder: (context, index) {
          final personWithCount = people[index];
          final personId = personWithCount.person.id;
          return PersonTile(
            personWithCount: personWithCount,
            selected: _selectedIds.contains(personId),
            onTap: () {
              if (_selectionMode) {
                _toggleSelection(personId);
              } else {
                context.push('/people/$personId');
              }
            },
            onLongPress: () => _enterSelection(personId),
          );
        },
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 80,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                ref.invalidate(peopleProvider);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _selectedIds.length >= 2
                    ? () => _showMergeDialog()
                    : null,
                icon: const Icon(Icons.merge),
                label: Text('Merge (${_selectedIds.length})'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => _showDeleteDialog(),
                icon: const Icon(Icons.delete_outline),
                label: Text('Delete (${_selectedIds.length})'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Merge ──────────────────────────────────────────────────────────────────

  Future<void> _showMergeDialog() async {
    if (_selectedIds.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least 2 people to merge')),
        );
      }
      return;
    }

    final peopleAsync = ref.read(peopleProvider);
    final allPeople = peopleAsync.valueOrNull;
    if (allPeople == null) return;

    final selectedPeople = allPeople
        .where((p) => _selectedIds.contains(p.person.id))
        .toList();

    final targetId = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Merge into which person?'),
        children: selectedPeople
            .map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(p.person.id),
                child: Text(
                  '${p.person.name ?? 'Person'}  (${p.photoCount} photos)',
                ),
              ),
            )
            .toList(),
      ),
    );

    if (targetId == null || !mounted) return;

    final target = selectedPeople.firstWhere((p) => p.person.id == targetId);
    final targetName = target.person.name ?? 'Person';
    final sourceCount = _selectedIds.length - 1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge People?'),
        content: Text(
          'Merge $sourceCount ${sourceCount == 1 ? 'person' : 'people'} '
          'into "$targetName"? All photos will be combined. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final sourceIds = _selectedIds.where((id) => id != targetId).toList();
    await ref
        .read(faceRepositoryProvider)
        .bulkMergePersons(sourceIds, targetId);
    ref.invalidate(peopleProvider);
    ref.invalidate(faceCountProvider);
    _exitSelection();
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<void> _showDeleteDialog() async {
    if (_selectedIds.isEmpty) return;

    final count = _selectedIds.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete People?'),
        content: Text(
          'Delete $count ${count == 1 ? 'person' : 'people'}? '
          'All face groupings will be removed. '
          'The photos themselves will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await ref
        .read(faceRepositoryProvider)
        .bulkDeletePersons(_selectedIds.toList());
    ref.invalidate(peopleProvider);
    ref.invalidate(faceCountProvider);
    _exitSelection();
  }
}
