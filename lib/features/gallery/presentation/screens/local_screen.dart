import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/di/gallery_providers.dart';

import '../../../../core/permissions/permission_service.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../../../shared/utils/date_grouping.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/fast_scroll_scrubber.dart';
import '../../../../shared/widgets/pinch_zoom_wrapper.dart';
import '../../../../shared/widgets/settings_gear_button.dart';
import '../../data/repositories/gallery_repository.dart';
import '../widgets/asset_tile.dart';
import '../widgets/date_header.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Local screen — shows every photo/video on this device.
///
/// Shows device photos directly (fast, metadata-only listing) with a
/// backup-status badge per item — no scan/hash step gates what's displayed
/// here anymore. Hashing only happens when a backup is actually started.
/// Shows a permission blocking state if media permission is revoked.
/// Items hidden from the timeline or moved to trash are excluded from this
/// grid: those only surface in the Hidden Album and Trash screens, and are
/// never selectable for backup here.
///
/// This was previously called "Timeline" — renamed to "Local" once the
/// Timeline tab became the backed-up-only view (see [TimelineScreen]).
class LocalScreen extends ConsumerStatefulWidget {
  const LocalScreen({super.key});

  @override
  ConsumerState<LocalScreen> createState() => _LocalScreenState();
}

class _LocalScreenState extends ConsumerState<LocalScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    final permissionService = ref.read(permissionServiceProvider);
    final status = await permissionService.checkMediaPermissionStatus();
    if (mounted && status == PermissionStatus.denied) {
      _showPermissionBlockedDialog();
    }
  }

  void _showPermissionBlockedDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(
          Symbols.photo_library,
          color: Theme.of(context).colorScheme.error,
          size: 48,
        ),
        title: const Text('Storage permission required'),
        content: const Text(
          'LumoVault needs access to your photos and videos to display and back them up. '
          'Please grant the permission in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final permissionService = ref.read(permissionServiceProvider);
              await permissionService.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final permissionStatus = ref.watch(mediaPermissionStatusProvider);
    final deviceAssets = ref.watch(deviceAssetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LumoVault'),
        actions: [
          IconButton(
            icon: const Icon(Symbols.search),
            onPressed: () => context.push('/gallery/search'),
            tooltip: 'Search',
          ),
          const SettingsGearButton(),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: permissionStatus.when(
              data: (status) {
                if (status == PermissionStatus.denied ||
                    status == PermissionStatus.permanentlyDenied) {
                  return _buildPermissionDeniedState(status);
                }
                return _buildGalleryContent(deviceAssets);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => _buildErrorState(error.toString()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final currentSort = ref.watch(settingsGallerySortProvider);
    final currentFilter = ref.watch(settingsGalleryFilterProvider);
    final selectedTag = ref.watch(selectedTagFilterProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Sort button
          ActionChip(
            avatar: const Icon(Symbols.sort, size: 18),
            label: Text(_sortLabel(currentSort)),
            onPressed: () => _showSortPicker(currentSort),
          ),
          const SizedBox(width: 8),
          // Filter chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(
                    label: 'All',
                    selected:
                        currentFilter == GalleryFilterType.all &&
                        selectedTag == null,
                    onSelected: () {
                      _setFilter(GalleryFilterType.all);
                      ref.read(selectedTagFilterProvider.notifier).state = null;
                    },
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    label: 'Photos',
                    icon: Symbols.image,
                    selected: currentFilter == GalleryFilterType.photosOnly,
                    onSelected: () => _setFilter(GalleryFilterType.photosOnly),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    label: 'Videos',
                    icon: Symbols.videocam,
                    selected: currentFilter == GalleryFilterType.videosOnly,
                    onSelected: () => _setFilter(GalleryFilterType.videosOnly),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    label: 'Favorites',
                    icon: Symbols.favorite,
                    selected: currentFilter == GalleryFilterType.favoritesOnly,
                    onSelected: () =>
                        _setFilter(GalleryFilterType.favoritesOnly),
                  ),
                  const SizedBox(width: 6),
                  _buildTagFilterChip(selectedTag),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagFilterChip(String? selectedTag) {
    return ActionChip(
      avatar: Icon(
        Symbols.label,
        size: 16,
        color: selectedTag != null
            ? Theme.of(context).colorScheme.primary
            : null,
      ),
      label: Text(selectedTag ?? 'Tags'),
      onPressed: () => _showTagPicker(selectedTag),
    );
  }

  void _showTagPicker(String? currentTag) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.label_off),
              title: const Text('No tag filter'),
              selected: currentTag == null,
              onTap: () {
                Navigator.pop(context);
                ref.read(selectedTagFilterProvider.notifier).state = null;
              },
            ),
            const Divider(height: 1),
            Flexible(
              child: FutureBuilder<List<String>>(
                future: ref.read(allTagsProvider.future),
                builder: (context, snapshot) {
                  final tags = snapshot.data ?? [];
                  if (tags.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No tags yet. Add tags from the viewer.'),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: tags.length,
                    itemBuilder: (context, index) {
                      final tag = tags[index];
                      return ListTile(
                        leading: const Icon(Symbols.label, size: 20),
                        title: Text(tag),
                        trailing: tag == currentTag
                            ? const Icon(Symbols.check)
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          ref.read(selectedTagFilterProvider.notifier).state =
                              tag;
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    IconData? icon,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      avatar: icon != null ? Icon(icon, size: 16) : null,
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
    );
  }

  String _sortLabel(GallerySortOrder order) {
    return switch (order) {
      GallerySortOrder.newestFirst => 'Newest',
      GallerySortOrder.oldestFirst => 'Oldest',
      GallerySortOrder.nameAsc => 'Name',
      GallerySortOrder.sizeDesc => 'Size',
    };
  }

  void _showSortPicker(GallerySortOrder current) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Sort by'),
        children: GallerySortOrder.values.map((order) {
          return SimpleDialogOption(
            onPressed: () {
              Navigator.of(context).pop();
              ref
                  .read(appSettingsProvider.notifier)
                  .updateField((s) => s.copyWith(gallerySortOrder: order));
            },
            child: Row(
              children: [
                if (order == current)
                  const Icon(Symbols.check, size: 20)
                else
                  const SizedBox(width: 20),
                const SizedBox(width: 12),
                Text(_sortLabel(order)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _setFilter(GalleryFilterType filter) {
    ref
        .read(appSettingsProvider.notifier)
        .updateField((s) => s.copyWith(galleryFilterType: filter));
  }

  Widget _buildPermissionDeniedState(PermissionStatus status) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPermanentlyDenied = status == PermissionStatus.permanentlyDenied;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.photo_library, size: 80, color: colorScheme.error),
            const SizedBox(height: 24),
            Text(
              'Storage permission required',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              isPermanentlyDenied
                  ? 'Please enable storage permission in Settings to view and back up your photos.'
                  : 'Grant storage permission to view and back up your photos.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                final permissionService = ref.read(permissionServiceProvider);
                if (isPermanentlyDenied) {
                  await permissionService.openAppSettings();
                } else {
                  final result = await permissionService
                      .requestMediaPermission();
                  if (result.status == PermissionStatus.permanentlyDenied &&
                      mounted) {
                    _showPermissionBlockedDialog();
                  }
                }
                if (!mounted) return;
                ref.invalidate(mediaPermissionStatusProvider);
              },
              icon: Icon(
                isPermanentlyDenied ? Symbols.settings : Symbols.lock_open,
              ),
              label: Text(
                isPermanentlyDenied ? 'Open Settings' : 'Grant Permission',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryContent(AsyncValue<List<AssetEntity>> deviceAssets) {
    return deviceAssets.when(
      data: (assets) {
        final repository = ref.read(galleryRepositoryProvider);
        // Use filtered/sorted assets from the provider
        final visible = ref.watch(filteredSortedAssetsProvider);
        if (visible.isEmpty) return _buildEmptyState();
        return RefreshIndicator(
          onRefresh: () => ref.refresh(deviceAssetsProvider.future),
          child: _buildTimelineGrid(
            visible,
            groupByDate(visible, (a) => a.createDateTime),
            repository,
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorState(error.toString()),
    );
  }

  Widget _buildEmptyState() {
    return EmptyState(
      icon: Symbols.photo_library,
      title: 'No photos found',
      message: 'Photos and videos on this device will\nappear here.',
      action: FilledButton.icon(
        onPressed: () => ref.invalidate(deviceAssetsProvider),
        icon: const Icon(Symbols.refresh),
        label: const Text('Refresh'),
      ),
    );
  }

  Widget _buildTimelineGrid(
    List<AssetEntity> allAssets,
    Map<String, List<AssetEntity>> groupedAssets,
    GalleryRepository repository,
  ) {
    final dateKeys = groupedAssets.keys.toList();
    final crossAxisCount = galleryCrossAxisCount(
      ref.watch(settingsGridSizeProvider),
      ref.watch(settingsCompactModeProvider),
    );

    return PinchZoomWrapper(
      child: FastScrollScrubber(
        scrollController: _scrollController,
        dateResolver: (progress) {
          if (dateKeys.isEmpty) return '';
          final index = (progress * (dateKeys.length - 1)).round().clamp(
            0,
            dateKeys.length - 1,
          );
          return dateKeys[index];
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            for (int i = 0; i < dateKeys.length; i++) ...[
              SliverToBoxAdapter(
                child: DateHeader(
                  dateText: dateKeys[i],
                  itemCount: groupedAssets[dateKeys[i]]?.length,
                ),
              ),
              SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final assets = groupedAssets[dateKeys[i]]!;
                  final asset = assets[index];
                  final item = repository.getItemById(asset.id);
                  // Not selected for backup by default, same as a freshly
                  // scanned item — matches the scanners' opt-in default.
                  final isSelectedForBackup = !(item?.isExcluded ?? true);

                  return AssetTile(
                    asset: asset,
                    status: item?.status,
                    isSelectedForBackup: isSelectedForBackup,
                    isFavorite: item?.isFavorite ?? false,
                    onTap: () {
                      final globalIndex = allAssets.indexOf(asset);
                      context.push(
                        '/gallery/media/${asset.id}',
                        extra: (
                          assets: allAssets,
                          initialIndex: globalIndex,
                          allowDeviceDelete: true,
                        ),
                      );
                    },
                  );
                }, childCount: groupedAssets[dateKeys[i]]?.length ?? 0),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return ErrorState(
      error: error,
      onRetry: () => ref.invalidate(deviceAssetsProvider),
    );
  }
}
