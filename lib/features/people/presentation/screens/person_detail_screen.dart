import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../providers/people_providers.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: personAsync.when(
          data: (person) => Text(person?.name ?? 'Person'),
          loading: () => const Text('Person'),
          error: (_, __) => const Text('Person'),
        ),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.check : Icons.edit),
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
                  leading: Icon(Icons.merge),
                  title: Text('Merge with...'),
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Delete Person'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: personAsync.when(
        data: (person) {
          if (person == null) {
            return const Center(child: Text('Person not found'));
          }
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: Text(
                        (person.name ?? 'P')[0].toUpperCase(),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
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
                                border: OutlineInputBorder(),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  person.name ?? 'Unnamed Person',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
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
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: mediaIdsAsync.when(
                  data: (mediaIds) {
                    if (mediaIds.isEmpty) {
                      return const Center(child: Text('No photos found'));
                    }
                    return GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 2,
                            mainAxisSpacing: 2,
                          ),
                      itemCount: mediaIds.length,
                      itemBuilder: (context, index) =>
                          _buildPhotoTile(context, mediaIds[index]),
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
    );
  }

  Widget _buildPhotoTile(BuildContext context, String mediaId) {
    return FutureBuilder<AssetEntity?>(
      future: AssetEntity.fromId(mediaId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          );
        }
        final asset = snapshot.data;
        if (asset == null) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.image_not_supported, size: 32),
          );
        }
        return GestureDetector(
          onTap: () => context.push(
            '/gallery/media/${asset.id}',
            extra: (assets: [asset], initialIndex: 0),
          ),
          child: FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(const ThumbnailSize(300, 300)),
            builder: (context, ts) {
              if (ts.connectionState != ConnectionState.done) {
                return Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                );
              }
              final bytes = ts.data;
              if (bytes == null) {
                return Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.image, size: 32),
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

  Future<void> _showMergeDialog() async {
    final peopleAsync = ref.read(peopleProvider);
    final people = peopleAsync.valueOrNull;
    if (people == null || people.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Need at least 2 people to merge')),
        );
      }
      return;
    }

    final targetId = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Merge into which person?'),
        children: people
            .where((p) => p.person.id != widget.personId)
            .map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(p.person.id),
                child: Text(p.person.name ?? 'Person'),
              ),
            )
            .toList(),
      ),
    );

    if (targetId == null || !mounted) return;

    // Confirm merge
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge People?'),
        content: const Text(
          'This will combine all photos from both people into one. This cannot be undone.',
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

    if (confirmed == true && mounted) {
      await ref
          .read(faceRepositoryProvider)
          .mergePersons(widget.personId, targetId);
      ref.invalidate(peopleProvider);
      if (mounted) context.pop();
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Person?'),
        content: const Text(
          'This will unassign all photos from this person. The photos themselves will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
}
