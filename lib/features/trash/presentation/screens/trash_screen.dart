import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../gallery/data/models/media_item.dart';
import '../../../gallery/presentation/widgets/asset_tile.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Trash screen — view, restore, or permanently delete trashed media.
///
/// Resolves each trashed item's [MediaItem.localId] to a device
/// [AssetEntity] via [AssetEntity.fromId] directly, rather than requiring
/// the asset to be in [deviceAssetsProvider]. This is necessary because
/// items trashed from the media viewer are moved to Android's system trash
/// and no longer appear in the normal device asset listing.
class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  final Set<String> _selected = {};
  bool get _isMultiSelect => _selected.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final trashed = ref.watch(trashedItemsProvider);

    return PopScope(
      canPop: !_isMultiSelect,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
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
                    icon: const Icon(Symbols.restore),
                    tooltip: 'Restore',
                    onPressed: () => _restoreSelected(),
                  ),
                  IconButton(
                    icon: const Icon(Symbols.delete_forever),
                    tooltip: 'Delete permanently',
                    onPressed: () => _confirmDelete(
                      count: _selected.length,
                      onConfirm: () => _deleteSelected(),
                    ),
                  ),
                ],
              )
            : AppBar(
                title: const Text('Trash'),
                actions: [
                  TextButton(
                    onPressed: () {
                      final items = trashed.valueOrNull;
                      if (items == null || items.isEmpty) return;
                      _confirmDelete(
                        count: items.length,
                        emptyAll: true,
                        onConfirm: () => _emptyTrash(items),
                      );
                    },
                    child: const Text('Empty'),
                  ),
                ],
              ),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(trashedItemsProvider);
            await Future<void>.delayed(const Duration(milliseconds: 300));
          },
          child: trashed.when(
            data: (items) => _buildBody(items),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text('$e')),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(List<MediaItem> items) {
    if (items.isEmpty) return _buildEmptyState();

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            'Items are permanently deleted after '
            '${AppConstants.trashRetentionDays} days. '
            'Long-press to select.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: galleryCrossAxisCount(
                ref.watch(settingsGridSizeProvider),
                ref.watch(settingsCompactModeProvider),
              ),
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _TrashedTile(
                item: item,
                isSelected: _selected.contains(item.localId),
                onTap: () {
                  if (_isMultiSelect) {
                    setState(() {
                      if (!_selected.remove(item.localId)) {
                        _selected.add(item.localId);
                      }
                    });
                    return;
                  }
                },
                onLongPress: () {
                  setState(() => _selected.add(item.localId));
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _restoreSelected() async {
    final repository = ref.read(galleryRepositoryProvider);
    final ids = List<String>.from(_selected);
    setState(_selected.clear);
    for (final id in ids) {
      await repository.restoreFromTrash(id);
    }
    ref.invalidate(trashedItemsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${ids.length} restored')));
  }

  Future<void> _deleteSelected() async {
    final repository = ref.read(galleryRepositoryProvider);
    final ids = List<String>.from(_selected);
    setState(_selected.clear);
    await repository.deletePermanentlyBatch(ids);
    ref.invalidate(trashedItemsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${ids.length} permanently deleted')),
    );
  }

  Future<void> _emptyTrash(List<MediaItem> items) async {
    final repository = ref.read(galleryRepositoryProvider);
    await repository.deletePermanentlyBatch(
      items.map((i) => i.localId).toList(),
    );
    ref.invalidate(trashedItemsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Trash emptied')));
  }

  void _confirmDelete({
    required int count,
    required VoidCallback onConfirm,
    bool emptyAll = false,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Symbols.delete_forever,
          color: Theme.of(context).colorScheme.error,
          size: 48,
        ),
        title: Text(emptyAll ? 'Empty trash?' : 'Delete permanently?'),
        content: Text(
          emptyAll
              ? 'All $count items will be permanently deleted. '
                    'This can\'t be undone.'
              : '$count ${count == 1 ? 'item' : 'items'} will be permanently '
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
    return const EmptyState(
      icon: Symbols.delete,
      title: 'Trash is empty',
      message:
          'Items moved to trash will be\npermanently deleted after '
          '${AppConstants.trashRetentionDays} days.',
    );
  }
}

/// A grid tile for a trashed item that resolves its [AssetEntity] via
/// [AssetEntity.fromId] instead of relying on [deviceAssetsProvider].
///
/// Items trashed from the media viewer are in Android's system trash and
/// won't appear in the normal device asset listing, so we resolve them
/// individually. If resolution fails (e.g. the file was purged from system
/// trash), a placeholder icon is shown.
class _TrashedTile extends StatelessWidget {
  const _TrashedTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  final MediaItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssetEntity?>(
      future: AssetEntity.fromId(item.localId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final asset = snapshot.data;
        if (asset == null) {
          return _buildPlaceholder(context);
        }
        return AssetTile(
          asset: asset,
          isSelected: isSelected,
          onTap: onTap,
          onLongPress: onLongPress,
        );
      },
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.image_not_supported,
              size: 32,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              item.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
