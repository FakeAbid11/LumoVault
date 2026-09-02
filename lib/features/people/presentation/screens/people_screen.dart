import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/utils/snackbars.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/settings_gear_button.dart';
import '../providers/people_providers.dart';
import '../widgets/person_tile.dart';
import 'package:material_symbols_icons/symbols.dart';

class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  final Set<int> _selectedIds = {};

  /// Explicitly entered via the app bar's Select action; long-pressing a
  /// tile also implies it. Kept separate from [_selectedIds] so Select can
  /// open an empty multi-select instead of preselecting someone.
  bool _selectMode = false;

  /// A destructive mutation (merge/delete) is in flight — buttons are
  /// disabled while true so the operation can't be fired twice.
  bool _isMutating = false;

  bool get _selectionMode => _selectMode || _selectedIds.isNotEmpty;

  void _exitSelection() {
    setState(() {
      _selectMode = false;
      _selectedIds.clear();
    });
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

  void _enterSelection([int? personId]) {
    setState(() {
      _selectMode = true;
      _selectedIds.clear();
      if (personId != null) {
        _selectedIds.add(personId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final peopleAsync = ref.watch(peopleProvider);
    final scanProgress = ref.watch(faceScanProgressProvider);
    final unscannedAsync = ref.watch(hasUnscannedPhotosProvider);

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelection();
      },
      child: Scaffold(
        appBar: _buildAppBar(scanProgress, peopleAsync),
        body: Stack(
          children: [
            _buildBody(context, ref, peopleAsync, scanProgress, unscannedAsync),
            if (_selectionMode)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildActionBar(context, ref),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    FaceScanProgress scanProgress,
    AsyncValue<List<dynamic>> peopleAsync,
  ) {
    if (_selectionMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Symbols.close),
          tooltip: 'Exit selection',
          onPressed: _exitSelection,
        ),
        title: Text('${_selectedIds.length} selected'),
        actions: [
          IconButton(
            icon: const Icon(Symbols.merge),
            tooltip: 'Merge selected',
            onPressed: !_isMutating && _selectedIds.length >= 2
                ? () => _showMergeDialog()
                : null,
          ),
          IconButton(
            icon: const Icon(Symbols.delete),
            tooltip: 'Delete selected',
            onPressed: _isMutating ? null : () => _showDeleteDialog(),
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
        // Visible entry point for multi-select — long-press alone is
        // undiscoverable (and unreachable via switch access/screen readers).
        if (peopleAsync.valueOrNull?.isNotEmpty ?? false)
          TextButton(onPressed: _enterSelection, child: const Text('Select')),
        const SettingsGearButton(),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<dynamic>> peopleAsync,
    FaceScanProgress scanProgress,
    AsyncValue<bool> unscannedAsync,
  ) {
    return Column(
      children: [
        // Scanning banner
        if (scanProgress.isScanning)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        value: scanProgress.progress,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Scanning for faces (${scanProgress.current} / ${scanProgress.total})...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // People grid or empty/error state.
        Expanded(
          child: peopleAsync.when(
            data: (people) {
              if (people.isEmpty && !scanProgress.isScanning) {
                return _buildEmptyState(context, ref, unscannedAsync);
              }
              if (people.isEmpty) {
                return _buildScanningState(scanProgress);
              }
              return _buildPeopleGrid(
                context,
                ref,
                people,
                unscannedAsync,
                scanProgress,
              );
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
    AsyncValue<bool> unscannedAsync,
  ) {
    final hasUnscanned = unscannedAsync.valueOrNull ?? false;
    return EmptyState(
      icon: Symbols.people,
      title: 'No people found',
      message: hasUnscanned
          ? 'Faces in your photos will be grouped here.\nTap below to start scanning.'
          : 'Scan your photos to discover and group people.',
      action: FilledButton.icon(
        onPressed: () => ref.read(faceScanControllerProvider).start(),
        icon: const Icon(Symbols.person_search),
        label: const Text('Scan for Faces'),
      ),
    );
  }

  Widget _buildPeopleGrid(
    BuildContext context,
    WidgetRef ref,
    List<dynamic> people,
    AsyncValue<bool> unscannedAsync,
    FaceScanProgress scanProgress,
  ) {
    final hasUnscanned = unscannedAsync.valueOrNull ?? false;
    return Column(
      children: [
        if (hasUnscanned && !scanProgress.isScanning)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
              child: ListTile(
                leading: const Icon(Symbols.person_add),
                title: const Text('New photos to scan'),
                subtitle: const Text('Tap to find new faces'),
                trailing: FilledButton.tonal(
                  onPressed: () => ref.read(faceScanControllerProvider).start(),
                  child: const Text('Scan'),
                ),
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(peopleProvider);
              ref.invalidate(faceCountProvider);
              ref.invalidate(hasUnscannedPhotosProvider);
            },
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
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
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, String error) {
    return ErrorState(
      error: error,
      onRetry: () {
        ref.invalidate(peopleProvider);
      },
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
                icon: const Icon(Symbols.merge),
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
                icon: const Icon(Symbols.delete),
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
        showLumoSnackBar(context, 'Select at least 2 people to merge');
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
    setState(() => _isMutating = true);
    try {
      await ref
          .read(faceRepositoryProvider)
          .bulkMergePersons(sourceIds, targetId);
      ref.invalidate(peopleProvider);
      ref.invalidate(faceCountProvider);
      if (mounted) _exitSelection();
    } catch (_) {
      if (mounted) {
        showLumoSnackBar(context, 'Couldn’t merge — please try again');
      }
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
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

    setState(() => _isMutating = true);
    try {
      await ref
          .read(faceRepositoryProvider)
          .bulkDeletePersons(_selectedIds.toList());
      ref.invalidate(peopleProvider);
      ref.invalidate(faceCountProvider);
      if (mounted) _exitSelection();
    } catch (_) {
      if (mounted) {
        showLumoSnackBar(context, 'Couldn’t delete — please try again');
      }
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }
}
