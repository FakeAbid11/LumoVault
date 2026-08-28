import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../providers/people_providers.dart';
import 'package:material_symbols_icons/symbols.dart';

class PersonDetailScreen extends ConsumerStatefulWidget {
  const PersonDetailScreen({required this.personId, super.key});

  final int personId;

  @override
  ConsumerState<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends ConsumerState<PersonDetailScreen> {
  bool _isEditing = false;
  late TextEditingController _nameController;

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
        title: personAsync.when(
          data: (person) => Text(person?.name ?? 'Person'),
          loading: () => const Text('Person'),
          error: (_, __) => const Text('Person'),
        ),
        actions: [
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
                  leading: Icon(Symbols.delete, color: Theme.of(context).colorScheme.error),
                  title: const Text('Delete Person'),
                ),
              ),
            ],
          ),
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
                      return _PersonPhotoGrid(mediaIds: mediaIds);
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

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    final repository = ref.read(faceRepositoryProvider);
    await repository.updatePersonName(
      widget.personId,
      name.isEmpty ? null : name,
    );
    ref.invalidate(personProvider(widget.personId));
    ref.invalidate(peopleProvider);
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
  const _PersonPhotoGrid({required this.mediaIds});

  final List<String> mediaIds;

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
          onTap: () => _openViewer(index),
          child: FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(const ThumbnailSize(300, 300)),
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
        );
      },
    );
  }
}
