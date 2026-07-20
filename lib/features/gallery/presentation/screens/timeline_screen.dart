import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/di/backup_providers.dart';
import '../../../../core/di/gallery_providers.dart';

import '../../../../core/permissions/permission_service.dart';
import '../widgets/asset_tile.dart';
import '../widgets/date_header.dart';

/// Timeline screen — the main gallery view.
///
/// Shows device photos directly (fast, metadata-only listing) with a
/// backup-status badge per item — no scan/hash step gates what's displayed
/// here anymore. Hashing only happens when a backup is actually started.
/// Shows a permission blocking state if media permission is revoked.
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  final Set<String> _multiSelected = {};
  bool get _isMultiSelectMode => _multiSelected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
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
          Icons.photo_library_outlined,
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
      appBar: _isMultiSelectMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(_multiSelected.clear),
                tooltip: 'Cancel selection',
              ),
              title: Text('${_multiSelected.length} selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.cloud_upload),
                  tooltip: 'Select for backup',
                  onPressed: () => _selectForBackup(deviceAssets),
                ),
              ],
            )
          : AppBar(
              title: const Text('LumoVault'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {},
                  tooltip: 'Search',
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () {},
                  tooltip: 'More options',
                ),
              ],
            ),
      floatingActionButton: _isMultiSelectMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/settings/backup'),
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Backup'),
            ),
      body: permissionStatus.when(
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
    );
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
            Icon(
              Icons.photo_library_outlined,
              size: 80,
              color: colorScheme.error,
            ),
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
                ref.invalidate(mediaPermissionStatusProvider);
              },
              icon: Icon(
                isPermanentlyDenied ? Icons.settings : Icons.lock_open,
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
        if (assets.isEmpty) return _buildEmptyState();
        return RefreshIndicator(
          onRefresh: () => ref.refresh(deviceAssetsProvider.future),
          child: _buildTimelineGrid(assets, _groupByDate(assets)),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorState(error.toString()),
    );
  }

  Map<String, List<AssetEntity>> _groupByDate(List<AssetEntity> assets) {
    final grouped = <String, List<AssetEntity>>{};
    for (final asset in assets) {
      final key = _dateKey(asset.createDateTime);
      grouped.putIfAbsent(key, () => []).add(asset);
    }
    return grouped;
  }

  String _dateKey(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(date.year, date.month, date.day);

    if (itemDate == today) return 'Today';
    if (itemDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }
    return '${date.month}/${date.day}/${date.year}';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'No photos found',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Photos and videos on this device will\nappear here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => ref.invalidate(deviceAssetsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineGrid(
    List<AssetEntity> allAssets,
    Map<String, List<AssetEntity>> groupedAssets,
  ) {
    final dateKeys = groupedAssets.keys.toList();
    final repository = ref.watch(galleryRepositoryProvider);

    return CustomScrollView(
      slivers: [
        for (int i = 0; i < dateKeys.length; i++) ...[
          SliverToBoxAdapter(
            child: DateHeader(
              dateText: dateKeys[i],
              itemCount: groupedAssets[dateKeys[i]]?.length,
            ),
          ),
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
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
                isSelected: _multiSelected.contains(asset.id),
                onTap: () {
                  if (_isMultiSelectMode) {
                    setState(() {
                      if (!_multiSelected.remove(asset.id)) {
                        _multiSelected.add(asset.id);
                      }
                    });
                    return;
                  }
                  final globalIndex = allAssets.indexOf(asset);
                  context.push(
                    '/gallery/media/${asset.id}',
                    extra: (assets: allAssets, initialIndex: globalIndex),
                  );
                },
                onLongPress: () {
                  setState(() => _multiSelected.add(asset.id));
                },
              );
            }, childCount: groupedAssets[dateKeys[i]]?.length ?? 0),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  Future<void> _selectForBackup(
    AsyncValue<List<AssetEntity>> deviceAssetsValue,
  ) async {
    final assets = deviceAssetsValue.valueOrNull;
    if (assets == null) return;

    final repository = ref.read(galleryRepositoryProvider);
    final byId = {for (final asset in assets) asset.id: asset};

    final ids = List<String>.from(_multiSelected);
    setState(_multiSelected.clear);

    final backupNotifier = ref.read(backupEngineProvider.notifier);
    for (final id in ids) {
      final asset = byId[id];
      if (asset == null) continue;
      await repository.setBackupExcluded(
        localId: id,
        excluded: false,
        asset: asset,
      );
      // Enqueue right away so these show up on the backup dashboard
      // immediately, not just after the next full "Start Backup" scan.
      final item = repository.getItemById(id);
      if (item != null) backupNotifier.enqueueSelectedItem(item);
    }


    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${ids.length} selected for backup')),
    );
    setState(() {});
  }

  Widget _buildErrorState(String error) {
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
              onPressed: () => ref.invalidate(deviceAssetsProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
