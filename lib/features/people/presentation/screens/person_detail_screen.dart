import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/database/daos/face_dao.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../providers/people_providers.dart';
import 'package:material_symbols_icons/symbols.dart';

/// "New person" result of [showMoveTargetDialog]. Person ids are
/// auto-incremented from 1, so -1 is a safe sentinel — and it MUST stay
/// distinct from a dialog dismissal, which also yields null. When both were
/// null, dismissing the "Move to…" dialog silently moved the selected photos
/// onto a brand-new person with no confirmation and no undo.
@visibleForTesting
const int newPersonSentinel = -1;

/// The "Move to…" chooser: returns an existing person's id,
/// [newPersonSentinel] for "New person", or null when dismissed without
/// choosing.
@visibleForTesting
Future<int?> showMoveTargetDialog(
  BuildContext context,
  List<PersonWithCount> others,
) {
  return showDialog<int?>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Move to…'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(newPersonSentinel),
          child: const ListTile(
            leading: Icon(Symbols.person_add),
            title: Text('New person'),
          ),
        ),
        ...others.map(
          (p) => SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(p.person.id),
            child: ListTile(
              title: Text(
                '${p.person.name ?? "Person"} (${p.photoCount} photos)',
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class PersonDetailScreen extends ConsumerStatefulWidget {
  const PersonDetailScreen({required this.personId, super.key});

  final int personId;

  @override
  ConsumerState<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends ConsumerState<PersonDetailScreen> {
  bool _isEditing = false;
  late TextEditingController _nameController;

  /// Correction mode: long-press a photo (or tap in mode) to select photos
  /// that do not belong to this person, then remove or move them.
  bool _selectionMode = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _loadPersonName();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadPersonName() async {
    final person = await ref.read(personProvider(widget.personId).future);
    if (person != null && mounted) {
      _nameController.text = person.name ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final personAsync = ref.watch(personProvider(widget.personId));
    final mediaIdsAsync = ref.watch(personMediaIdsProvider(widget.personId));
    final thumbnailAsync = ref.watch(personThumbnailProvider(widget.personId));

    return Scaffold(
      appBar: AppBar(
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Symbols.close),
                tooltip: 'Done selecting',
                onPressed: _exitSelection,
              )
            : null,
        title: _selectionMode
            ? Text('${_selected.length} selected')
            : personAsync.when(
                data: (person) => Text(person?.name ?? 'Person'),
                loading: () => const Text('Person'),
                error: (_, __) => const Text('Person'),
              ),
        actions: [
          if (_selectionMode) ...[
            IconButton(
              icon: const Icon(Symbols.person_off),
              tooltip: 'This is not the person',
              onPressed: _selected.isEmpty ? null : _removeSelected,
            ),
            IconButton(
              icon: const Icon(Symbols.drive_file_move),
              tooltip: 'Move to another person',
              onPressed: _selected.isEmpty ? null : _moveSelected,
            ),
          ] else ...[
            IconButton(
              icon: Icon(_isEditing ? Symbols.check : Symbols.edit),
              tooltip: _isEditing ? 'Save name' : 'Edit name',
              onPressed: () {
                if (_isEditing) _saveName();
                setState(() => _isEditing = !_isEditing);
              },
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') {
                  _confirmDelete();
                } else if (v == 'merge') {
                  _showMergeDialog();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'merge',
                  child: ListTile(
                    leading: Icon(Symbols.merge),
                    title: Text('Merge with...'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(
                      Symbols.delete,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Delete Person'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(personProvider(widget.personId));
          ref.invalidate(personMediaIdsProvider(widget.personId));
          ref.invalidate(personThumbnailProvider(widget.personId));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        },
        child: personAsync.when(
          data: (person) {
            if (person == null) {
              return const EmptyState(
                icon: Symbols.person_off,
                title: 'Person not found',
                message: 'This person may have been deleted.',
              );
            }
            final isUnnamed =
                person.name == null || person.name!.trim().isEmpty;

            return Column(
              children: [
                // Header Avatar & Person Details Card
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Cropped face thumbnail avatar
                      ClipOval(
                        child: SizedBox(
                          width: 76,
                          height: 76,
                          child: thumbnailAsync.when(
                            data: (path) {
                              if (path != null && File(path).existsSync()) {
                                return Image.file(
                                  File(path),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _buildLetterAvatar(context, person.name),
                                );
                              }
                              return _buildLetterAvatar(context, person.name);
                            },
                            loading: () => const ShimmerPlaceholder(
                              width: 76,
                              height: 76,
                              borderRadius: 40,
                            ),
                            error: (_, __) =>
                                _buildLetterAvatar(context, person.name),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _isEditing
                            ? TextField(
                                controller: _nameController,
                                autofocus: true,
                                decoration: const InputDecoration(
                                  hintText: 'Enter name',
                                  isDense: true,
                                ),
                                onSubmitted: (_) {
                                  _saveName();
                                  setState(() => _isEditing = false);
                                },
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    person.name ?? 'Unnamed Person',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  mediaIdsAsync.when(
                                    data: (ids) => Text(
                                      '${ids.length} ${ids.length == 1 ? "photo" : "photos"}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                    loading: () => const Text('Loading...'),
                                    error: (_, __) => const Text(''),
                                  ),
                                  if (isUnnamed) ...[
                                    const SizedBox(height: 6),
                                    ActionChip(
                                      avatar: const Icon(
                                        Symbols.edit,
                                        size: 14,
                                      ),
                                      label: const Text('Add name'),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () =>
                                          setState(() => _isEditing = true),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Photo Grid
                Expanded(
                  child: mediaIdsAsync.when(
                    data: (mediaIds) {
                      if (mediaIds.isEmpty) {
                        return const Center(child: Text('No photos found'));
                      }
                      return _PersonPhotoGrid(
                        mediaIds: mediaIds,
                        selectionMode: _selectionMode,
                        selected: _selected,
                        onTapPhoto: (mediaId) {
                          // Long-press outside selection mode: enter it with
                          // this photo already marked.
                          setState(() {
                            _selectionMode = true;
                            _selected.add(mediaId);
                          });
                        },
                        onTogglePhoto: (mediaId) {
                          setState(() {
                            if (!_selected.remove(mediaId)) {
                              _selected.add(mediaId);
                            }
                          });
                        },
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
    );
  }

  Widget _buildLetterAvatar(BuildContext context, String? name) {
    final initial = (name != null && name.trim().isNotEmpty)
        ? name.trim()[0].toUpperCase()
        : 'P';
    return Container(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Center(
        child: Text(
          initial,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _invalidateGroupProviders() {
    ref.invalidate(personProvider(widget.personId));
    ref.invalidate(personMediaIdsProvider(widget.personId));
    ref.invalidate(personThumbnailProvider(widget.personId));
    ref.invalidate(peopleProvider);
  }

  /// "This is not the person" — removes THIS person's faces on the selected
  /// photos and excludes them, so they never re-merge. A photo that also
  /// contains someone else's face correctly stays in that other group.
  Future<void> _removeSelected() async {
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('This is not the person?'),
        content: Text(
          'Remove $count ${count == 1 ? "photo" : "photos"} from this '
          'group? They will not be grouped here again, and photos containing '
          'other people stay in those people\'s groups.',
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final mediaIds = _selected.toList();
    try {
      final removed = await ref
          .read(faceRepositoryProvider)
          .removeFacesFromPerson(widget.personId, mediaIds);
      _exitSelection();
      _invalidateGroupProviders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              removed == 1
                  ? 'Removed 1 photo from this person'
                  : 'Removed $removed photos from this person',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Remove failed: $e')));
      }
    }
  }

  /// "Move to another person…" — reassigns the selected photos' faces to an
  /// existing person or a fresh tile (reversible; unlike removal, the faces
  /// stay eligible for future clustering).
  Future<void> _moveSelected() async {
    final allPeople = ref.read(peopleProvider).valueOrNull ?? const [];
    final others = allPeople
        .where((p) => p.person.id != widget.personId)
        .toList();

    final targetId = await showMoveTargetDialog(context, others);

    // null == dismissed without choosing (barrier / back): abort. The "New
    // person" choice is the sentinel, never null, so it survives to the move.
    if (targetId == null) return;
    if (!context.mounted) return;

    final mediaIds = _selected.toList();
    final existingTargetId = targetId == newPersonSentinel ? null : targetId;
    try {
      final moved = await ref
          .read(faceRepositoryProvider)
          .moveFacesToPerson(widget.personId, mediaIds, existingTargetId);
      _exitSelection();
      _invalidateGroupProviders();
      if (existingTargetId != null) {
        ref.invalidate(personMediaIdsProvider(existingTargetId));
        ref.invalidate(personProvider(existingTargetId));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(moved == 1 ? 'Moved 1 photo' : 'Moved $moved photos'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Move failed: $e')));
      }
    }
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    // An empty submit means "no change", not "erase the name" — passing null
    // to updatePersonName overwrote the stored name with NULL.
    if (name.isEmpty) return;
    final repository = ref.read(faceRepositoryProvider);
    try {
      await repository.updatePersonName(widget.personId, name);
      ref.invalidate(personProvider(widget.personId));
      ref.invalidate(peopleProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save name: $e')));
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Person?'),
        content: const Text(
          'Face groupings will be removed. Photos will not be deleted from your device.',
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

    if (confirmed == true && mounted) {
      await ref.read(faceRepositoryProvider).deletePerson(widget.personId);
      ref.invalidate(peopleProvider);
      ref.invalidate(personProvider(widget.personId));
      ref.invalidate(personMediaIdsProvider(widget.personId));
      if (mounted) context.pop();
    }
  }

  Future<void> _showMergeDialog() async {
    final peopleAsync = ref.read(peopleProvider);
    final allPeople = peopleAsync.valueOrNull;
    if (allPeople == null || allPeople.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No other people to merge with')),
        );
      }
      return;
    }

    final otherPeople = allPeople
        .where((p) => p.person.id != widget.personId)
        .toList();

    final targetId = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Merge into which person?'),
        children: otherPeople
            .map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(p.person.id),
                child: Text(
                  '${p.person.name ?? "Person"} (${p.photoCount} photos)',
                ),
              ),
            )
            .toList(),
      ),
    );

    if (targetId == null || !mounted) return;

    final target = otherPeople.firstWhere((p) => p.person.id == targetId);
    final targetName = target.person.name ?? 'Person';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Merge'),
        content: Text('Merge this person into "$targetName"?'),
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

    if (confirmed == true && mounted) {
      await ref
          .read(faceRepositoryProvider)
          .mergePersons(widget.personId, targetId);
      ref.invalidate(peopleProvider);
      ref.invalidate(personProvider(targetId));
      if (mounted) context.pop();
    }
  }
}

class _PersonPhotoGrid extends StatefulWidget {
  const _PersonPhotoGrid({
    required this.mediaIds,
    required this.selectionMode,
    required this.selected,
    required this.onTapPhoto,
    required this.onTogglePhoto,
  });

  final List<String> mediaIds;
  final bool selectionMode;
  final Set<String> selected;

  /// Called when a photo is long-pressed outside selection mode (enters it,
  /// with that photo marked).
  final void Function(String mediaId) onTapPhoto;

  /// Toggles membership while in selection mode.
  final void Function(String mediaId) onTogglePhoto;

  @override
  State<_PersonPhotoGrid> createState() => _PersonPhotoGridState();
}

class _PersonPhotoGridState extends State<_PersonPhotoGrid> {
  final Map<String, AssetEntity?> _resolvedAssets = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _resolveAllAssets();
  }

  @override
  void didUpdateWidget(covariant _PersonPhotoGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaIds != widget.mediaIds) {
      _resolveAllAssets();
    }
  }

  Future<void> _resolveAllAssets() async {
    setState(() => _isLoading = true);
    for (final id in widget.mediaIds) {
      if (!_resolvedAssets.containsKey(id)) {
        final asset = await AssetEntity.fromId(id);
        if (mounted) {
          _resolvedAssets[id] = asset;
        }
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _openViewer(int initialIndex) {
    final validAssets = <AssetEntity>[];
    int targetIndex = 0;
    for (int i = 0; i < widget.mediaIds.length; i++) {
      final asset = _resolvedAssets[widget.mediaIds[i]];
      if (asset != null) {
        if (i == initialIndex) {
          targetIndex = validAssets.length;
        }
        validAssets.add(asset);
      }
    }

    if (validAssets.isNotEmpty) {
      context.push(
        '/gallery/media/${validAssets[targetIndex].id}',
        extra: (
          assets: validAssets,
          initialIndex: targetIndex,
          allowDeviceDelete: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
      ),
      itemCount: widget.mediaIds.length,
      itemBuilder: (context, index) {
        final mediaId = widget.mediaIds[index];
        final asset = _resolvedAssets[mediaId];

        if (asset == null) {
          if (_isLoading) {
            return const ShimmerPlaceholder(
              width: double.infinity,
              height: double.infinity,
            );
          }
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Symbols.broken_image, size: 28),
          );
        }

        return GestureDetector(
          // selection mode OFF: tap opens the viewer, long-press enters
          // selection with this photo marked.
          // selection mode ON: tap/long-press toggle membership.
          onTap: () {
            if (widget.selectionMode) {
              widget.onTogglePhoto(mediaId);
            } else {
              _openViewer(index);
            }
          },
          onLongPress: () {
            if (!widget.selectionMode) {
              widget.onTapPhoto(mediaId);
            } else {
              widget.onTogglePhoto(mediaId);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<Uint8List?>(
                future: asset.thumbnailDataWithSize(
                  const ThumbnailSize(300, 300),
                ),
                builder: (context, ts) {
                  final bytes = ts.data;
                  if (bytes == null) {
                    return const ShimmerPlaceholder(
                      width: double.infinity,
                      height: double.infinity,
                    );
                  }
                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  );
                },
              ),
              if (widget.selectionMode)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.selected.contains(mediaId)
                          ? Theme.of(context).colorScheme.primary
                          : Colors.black38,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      widget.selected.contains(mediaId)
                          ? Symbols.check_circle
                          : Symbols.radio_button_unchecked,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (widget.selectionMode && widget.selected.contains(mediaId))
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.18),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
