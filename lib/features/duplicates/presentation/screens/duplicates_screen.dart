import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/gallery_providers.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../gallery/data/models/media_item.dart';
import '../../../gallery/presentation/widgets/asset_tile.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Find Duplicates screen — shows groups of photos with identical content
/// (same SHA-256 hash) and lets the user select and delete extras.
class DuplicatesScreen extends ConsumerStatefulWidget {
  const DuplicatesScreen({super.key});

  @override
  ConsumerState<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends ConsumerState<DuplicatesScreen> {
  final Set<String> _selected = {};
  bool get _isMultiSelect => _selected.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(duplicateGroupsProvider);
    final totalGroups = groups.length;
    final totalDuplicates = groups.values.fold<int>(
      0,
      (sum, items) => sum + items.length - 1,
    );
    final reclaimableBytes = groups.values.fold<int>(0, (sum, items) {
      if (items.length < 2) return sum;
      final sizePerItem = items.first.fileSize;
      return sum + sizePerItem * (items.length - 1);
    });

    return Scaffold(
      appBar: _isMultiSelect
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Symbols.close),
                onPressed: () => setState(_selected.clear),
                tooltip: 'Cancel selection',
              ),
              title: Text('${_selected.length} selected'),
              actions: [
                IconButton(
                  icon: const Icon(Symbols.delete_forever),
                  tooltip: 'Delete selected',
                  onPressed: () => _confirmDelete(
                    count: _selected.length,
                    onConfirm: () => _deleteSelected(),
                  ),
                ),
              ],
            )
          : AppBar(title: const Text('Find Duplicates')),
      body: groups.isEmpty
          ? _buildEmptyState()
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Text(
                    '$totalGroups group${totalGroups == 1 ? '' : 's'} · '
                    '$totalDuplicates duplicate${totalDuplicates == 1 ? '' : 's'} · '
                    '${formatBytes(reclaimableBytes)} reclaimable',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 32),
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final hash = groups.keys.elementAt(index);
                      final items = groups[hash]!;
                      return _DuplicateGroup(
                        hash: hash,
                        items: items,
                        selected: _selected,
                        onToggle: (localId) {
                          setState(() {
                            if (!_selected.remove(localId)) {
                              _selected.add(localId);
                            }
                          });
                        },
                        onSelectAll: () {
                          setState(() {
                            final allSelected = items.every(
                              (i) => _selected.contains(i.localId),
                            );
                            if (allSelected) {
                              for (final i in items) {
                                _selected.remove(i.localId);
                              }
                            } else {
                              for (final i in items) {
                                _selected.add(i.localId);
                              }
                            }
                          });
                        },
                        onKeepNewest: () {
                          final toDelete = items.skip(1).toList();
                          _confirmDelete(
                            count: toDelete.length,
                            onConfirm: () => _deleteItems(toDelete),
                          );
                        },
                        onKeepOldest: () {
                          final toDelete = items.reversed.skip(1).toList();
                          _confirmDelete(
                            count: toDelete.length,
                            onConfirm: () => _deleteItems(toDelete),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _deleteSelected() async {
    final repository = ref.read(galleryRepositoryProvider);
    final ids = List<String>.from(_selected);
    setState(_selected.clear);
    await repository.deletePermanentlyBatch(ids);
    ref.invalidate(duplicateGroupsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${ids.length} permanently deleted')),
    );
  }

  Future<void> _deleteItems(List<MediaItem> items) async {
    final repository = ref.read(galleryRepositoryProvider);
    await repository.deletePermanentlyBatch(
      items.map((i) => i.localId).toList(),
    );
    ref.invalidate(duplicateGroupsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${items.length} permanently deleted')),
    );
  }

  void _confirmDelete({required int count, required VoidCallback onConfirm}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Symbols.delete_forever,
          color: Theme.of(context).colorScheme.error,
          size: 48,
        ),
        title: const Text('Delete permanently?'),
        content: Text(
          '$count ${count == 1 ? 'item' : 'items'} will be permanently '
          'deleted. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.of(context).pop();
              onConfirm();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Symbols.check_circle,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'No duplicates found',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'All your photos have unique content.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DuplicateGroup extends StatelessWidget {
  const _DuplicateGroup({
    required this.hash,
    required this.items,
    required this.selected,
    required this.onToggle,
    required this.onSelectAll,
    required this.onKeepNewest,
    required this.onKeepOldest,
  });

  final String hash;
  final List<MediaItem> items;
  final Set<String> selected;
  final void Function(String localId) onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onKeepNewest;
  final VoidCallback onKeepOldest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reclaimable = items.first.fileSize * (items.length - 1);
    final allSelected = items.every((i) => selected.contains(i.localId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${items.length} copies · ${formatBytes(reclaimable)} reclaimable',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      items.first.fileName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'select_all':
                      onSelectAll();
                    case 'keep_newest':
                      onKeepNewest();
                    case 'keep_oldest':
                      onKeepOldest();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'select_all',
                    child: Text(allSelected ? 'Deselect all' : 'Select all'),
                  ),
                  const PopupMenuItem(
                    value: 'keep_newest',
                    child: Text('Keep newest'),
                  ),
                  const PopupMenuItem(
                    value: 'keep_oldest',
                    child: Text('Keep oldest'),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return _DuplicateTile(
                item: item,
                isSelected: selected.contains(item.localId),
                onTap: () => onToggle(item.localId),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DuplicateTile extends StatelessWidget {
  const _DuplicateTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final MediaItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssetEntity?>(
      future: AssetEntity.fromId(item.localId),
      builder: (context, snapshot) {
        final asset = snapshot.data;
        if (asset == null) {
          return Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Symbols.image_not_supported,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }
        return GestureDetector(
          onTap: onTap,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AssetTile(
                  asset: asset,
                  isSelected: isSelected,
                  onTap: onTap,
                ),
              ),
              if (isSelected)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Symbols.check,
                      color: Colors.white,
                      size: 16,
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
