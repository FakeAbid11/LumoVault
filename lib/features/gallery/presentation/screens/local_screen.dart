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
import '../../../../shared/widgets/fast_scroll_scrubber.dart';
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
  final Set<String> _multiSelected = {};
  bool get _isMultiSelectMode => _multiSelected.isNotEmpty;
  final ScrollController _scrollController = ScrollController();
  double _lastPinchScale = 1.0;

  bool _areAllVisibleSelected(AsyncValue<List<AssetEntity>> deviceAssets) {
    final assets = deviceAssets.valueOrNull;
    if (assets == null || assets.isEmpty) return false;
    final repository = ref.read(galleryRepositoryProvider);
    for (final asset in assets) {
      final item = repository.getItemById(asset.id);
      if (item?.isHidden == true || item?.isTrashed == true) continue;
      if (!_multiSelected.contains(asset.id)) return false;
    }
    return true;
  }

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

  void _handlePinchScale(double scale) {
    if ((scale - _lastPinchScale).abs() < 0.25) return;
    _lastPinchScale = scale;

    final currentGrid = ref.read(settingsGridSizeProvider);
    if (scale > 1.25) {
      // Zoom in -> larger thumbnails, fewer columns
      if (currentGrid == GridSize.small) {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(gridSize: GridSize.medium));
        HapticFeedback.lightImpact();
      } else if (currentGrid == GridSize.medium) {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(gridSize: GridSize.large));
        HapticFeedback.lightImpact();
      }
    } else if (scale < 0.75) {
      // Zoom out -> smaller thumbnails, more columns
      if (currentGrid == GridSize.large) {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(gridSize: GridSize.medium));
        HapticFeedback.lightImpact();
      } else if (currentGrid == GridSize.medium) {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(gridSize: GridSize.small));
        HapticFeedback.lightImpact();
      }
    }
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
      appBar: _isMultiSelectMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Symbols.close),
                onPressed: () => setState(_multiSelected.clear),
                tooltip: 'Cancel selection',
              ),
              title: Text('${_multiSelected.length} selected'),
              actions: [
                TextButton(
                  onPressed: () {
                    final assets = deviceAssets.valueOrNull;
                    if (assets == null) return;
                    final repository = ref.read(galleryRepositoryProvider);
                    final visibleCount = assets.where((asset) {
                      final item = repository.getItemById(asset.id);
                      return !(item?.isHidden ?? false) &&
                          !(item?.isTrashed ?? false);
                    }).length;
                    setState(() {
                      if (_multiSelected.length == visibleCount) {
                        _multiSelected.clear();
                      } else {
                        final allIds = assets
                            .where((asset) {
                              final item = repository.getItemById(asset.id);
                              return !(item?.isHidden ?? false) &&
                                  !(item?.isTrashed ?? false);
                            })
                            .map((a) => a.id);
                        _multiSelected.addAll(allIds);
                      }
                    });
                  },
                  child: Text(
                    _areAllVisibleSelected(deviceAssets)
                        ? 'Deselect all'
                        : 'Select all',
                  ),
                ),
              ],
            )
          : AppBar(
              title: const Text('LumoVault'),
              actions: [
                IconButton(
                  icon: const Icon(Symbols.search),
                  onPressed: () => context.push('/gallery/search'),
                  tooltip: 'Search',
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Symbols.more_vert),
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
                        leading: Icon(Symbols.settings),
                        title: Text('Settings'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'restore',
                      child: ListTile(
                        leading: Icon(Symbols.restore),
                        title: Text('Restore'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'refresh',
                      child: ListTile(
                        leading: Icon(Symbols.refresh),
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
              icon: const Icon(Symbols.cloud_upload),
              label: const Text('Backup'),
            ),
      body: Stack(
        children: [
          permissionStatus.when(
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
          if (_isMultiSelectMode)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _SelectionBar(
                selectedCount: _multiSelected.length,
                onBackup: () => _selectForBackup(deviceAssets),
                onTrash: () => _trashSelected(deviceAssets),
              ),
            ),
        ],
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
            Symbols.photo_library,
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
            icon: const Icon(Symbols.refresh),
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

    return GestureDetector(
      onScaleUpdate: (details) {
        if (details.pointerCount >= 2) {
          _handlePinchScale(details.scale);
        }
      },
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
                    isSelected: _multiSelected.contains(asset.id),
                    onTap: () {
                      if (_isMultiSelectMode) {
                        HapticFeedback.selectionClick();
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
                      HapticFeedback.mediumImpact();
                      setState(() => _multiSelected.add(asset.id));
                    },
                  );
                }, childCount: groupedAssets[dateKeys[i]]?.length ?? 0),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
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

    try {
      // One system dialog covers the whole batch; the returned ids are the
      // ones actually trashed (empty if the user cancels there).
      final trashed = await PhotoManager.editor.android.moveToTrash(selected);
      if (!mounted) return;
      if (trashed.isEmpty) return;

      // Mark each trashed item in the app database so the Trash screen
      // shows them. PhotoManager.moveToTrash handles the OS-level trash.
      for (final id in trashed) {
        await repository.moveToTrash(id);
      }

      ref.invalidate(deviceAssetsProvider);
      ref.invalidate(mapPhotosProvider);
      ref.invalidate(trashedItemsProvider);
      setState(_multiSelected.clear);
      if (!mounted) return;
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
              Symbols.error,
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
              icon: const Icon(Symbols.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selectedCount,
    required this.onBackup,
    required this.onTrash,
  });

  final int selectedCount;
  final VoidCallback onBackup;
  final VoidCallback onTrash;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _SelectionActionButton(
                  icon: Symbols.cloud_upload,
                  label: 'Backup',
                  onTap: onBackup,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SelectionActionButton(
                  icon: Symbols.delete,
                  label: 'Trash',
                  color: Theme.of(context).colorScheme.error,
                  onTap: onTrash,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionActionButton extends StatelessWidget {
  const _SelectionActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: effectiveColor, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: effectiveColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
