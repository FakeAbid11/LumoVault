import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/di/backup_providers.dart';
import '../../../../core/di/gallery_providers.dart';

import '../../../../core/permissions/permission_service.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../data/models/media_item.dart';
import '../widgets/asset_tile.dart';
import '../widgets/date_header.dart';

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
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Move to trash',
                  onPressed: () => _trashSelected(deviceAssets),
                ),
              ],
            )
          : AppBar(
              title: const Text('LumoVault'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => context.push('/gallery/search'),
                  tooltip: 'Search',
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'More options',
                  onSelected: (value) {
                    switch (value) {
                      case 'settings':
                        // Settings is a bottom-nav branch — switch tabs.
                        context.go('/settings');
                      case 'restore':
                        context.push('/restore');
                      case 'refresh':
                        ref.invalidate(deviceAssetsProvider);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'settings',
                      child: ListTile(
                        leading: Icon(Icons.settings),
                        title: Text('Settings'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'restore',
                      child: ListTile(
                        leading: Icon(Icons.restore),
                        title: Text('Restore'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'refresh',
                      child: ListTile(
                        leading: Icon(Icons.refresh),
                        title: Text('Refresh'),
                      ),
                    ),
                  ],
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
                if (!mounted) return;
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
        // Hidden/trashed items only surface in their own screens — keep them
        // out of the backup selection grid entirely.
        final repository = ref.read(galleryRepositoryProvider);
        final visible = assets.where((asset) {
          final item = repository.getItemById(asset.id);
          return !(item?.isHidden ?? false) && !(item?.isTrashed ?? false);
        }).toList();
        if (visible.isEmpty) return _buildEmptyState();
        return RefreshIndicator(
          onRefresh: () => ref.refresh(deviceAssetsProvider.future),
          child: _buildTimelineGrid(visible, _groupByDate(visible)),
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
    final crossAxisCount = galleryCrossAxisCount(
      ref.watch(settingsGridSizeProvider),
      ref.watch(settingsCompactModeProvider),
    );

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
                    extra: (
                      assets: allAssets,
                      initialIndex: globalIndex,
                      allowDeviceDelete: true,
                    ),
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

  /// Move the selected assets to the phone's trash.
  ///
  /// The Local-tab counterpart to the media viewer's single-item Trash action.
  /// Uses Android's MediaStore trash (`createTrashRequest`, Android 11+/API 30),
  /// which shows one system confirmation for the whole batch, then moves the
  /// files to the phone's trash for permanent deletion after 30 days —
  /// recoverable from the phone's Trash until then. Only on-device copies are
  /// removed; Telegram backups are left untouched.
  Future<void> _trashSelected(
    AsyncValue<List<AssetEntity>> deviceAssetsValue,
  ) async {
    final assets = deviceAssetsValue.valueOrNull;
    if (assets == null) return;

    final byId = {for (final asset in assets) asset.id: asset};
    final selected = <AssetEntity>[
      for (final id in _multiSelected)
        if (byId[id] != null) byId[id]!,
    ];
    if (selected.isEmpty) return;

    final repository = ref.read(galleryRepositoryProvider);
    final notBackedUp = selected
        .where(
          (a) => repository.getItemById(a.id)?.status != MediaStatus.uploaded,
        )
        .length;
    final count = selected.length;
    final noun = count == 1 ? 'item' : 'items';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.delete_outline,
          color: Colors.redAccent,
          size: 40,
        ),
        title: Text('Move $count $noun to trash?'),
        content: Text(
          notBackedUp == 0
              ? 'They move to your phone’s trash and are permanently deleted '
                    'after 30 days. Your backups stay safe in Telegram.'
              : '$notBackedUp of these aren’t backed up yet. Everything moves '
                    'to your phone’s trash and is permanently deleted after 30 '
                    'days — restore from your phone’s trash before then.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Move to trash'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      // One system dialog covers the whole batch; the returned ids are the
      // ones actually trashed (empty if the user cancels there).
      final trashed = await PhotoManager.editor.android.moveToTrash(selected);
      if (!mounted) return;
      if (trashed.isEmpty) return;

      ref.invalidate(deviceAssetsProvider);
      ref.invalidate(mapPhotosProvider);
      setState(_multiSelected.clear);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${trashed.length} moved to trash · deletes in 30 days',
          ),
        ),
      );
    } on PlatformException {
      // moveToTrash is Android 11+ (API 30) only — older versions have no
      // MediaStore trash, so there's no 30-day-recovery delete to offer.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Moving to trash needs Android 11 or newer'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn’t move these to trash')),
      );
    }
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
