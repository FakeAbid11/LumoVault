import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/backup_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../backup/engine/backup_engine.dart';
import '../../data/models/media_item.dart';
import '../../data/models/upload_task.dart';
import '../widgets/inline_video_player.dart';
import 'location_picker_screen.dart';

/// Full-screen photo/video viewer.
///
/// Was a stub before — no image, no swiping, every action a no-op. This
/// shows the actual asset, lets you swipe through [assets], and backs up a
/// specific photo on demand straight from the preview.
class MediaViewerScreen extends ConsumerStatefulWidget {
  const MediaViewerScreen({
    required this.assets,
    required this.initialIndex,
    this.allowDeviceDelete = false,
    super.key,
  });

  final List<AssetEntity> assets;
  final int initialIndex;

  /// Whether to offer "Delete from phone" in the bottom bar.
  ///
  /// Only the Local tab passes `true`: there the asset is a file physically on
  /// this device, so trashing it is meaningful. Every other entry point
  /// (Timeline, Map, Search, Trash, Archive, Hidden) leaves this `false`.
  final bool allowDeviceDelete;

  @override
  ConsumerState<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  /// Asset ids whose backup this screen kicked off and is still awaiting.
  /// Keyed by id rather than a single bool so swiping to another photo
  /// mid-upload doesn't show that photo as busy.
  final Set<String> _inFlight = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  AssetEntity get _currentAsset => widget.assets[_currentIndex];

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(galleryRepositoryProvider);
    final asset = _currentAsset;
    final currentItem = repository.getItemById(asset.id);
    final isBackedUp = currentItem?.status == MediaStatus.uploaded;
    // Live queue task for this asset, so the button reflects a backup already
    // running for it (started here, from a tile, or by a full backup run).
    final task = ref.watch(uploadTaskForItemProvider(asset.id));
    final isUploading =
        _inFlight.contains(asset.id) || task?.status == UploadStatus.uploading;
    final isQueued = task?.status == UploadStatus.queued;
    final hasLocation = currentItem?.hasLocation ?? false;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.assets.length}',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.assets.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) =>
            _AssetPreview(asset: widget.assets[index]),
      ),
      // Actions live at the bottom, thumb-reachable, like most gallery apps.
      // The backup action only appears while there's something to do — back
      // up, queued, or uploading. Once an item is backed up the action drops
      // out entirely rather than sitting there as a redundant "Backed up"
      // label: that state is already obvious from where the item shows up
      // (e.g. the Timeline lists only backed-up items).
      bottomNavigationBar: Container(
        color: Colors.black,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            child: Row(
              children: [
                if (!isBackedUp)
                  Expanded(
                    child: _BackupAction(
                      isUploading: isUploading,
                      isQueued: isQueued,
                      progress: task?.progress ?? 0,
                      onPressed: isUploading
                          ? null
                          : () => _backUpCurrentAsset(),
                    ),
                  ),
                Expanded(
                  child: _BottomAction(
                    icon: hasLocation
                        ? Icons.location_on
                        : Icons.location_on_outlined,
                    label: hasLocation ? 'Location' : 'Location',
                    color: hasLocation ? Colors.blueAccent : Colors.white,
                    onPressed: () => _openLocationPicker(),
                  ),
                ),
                Expanded(
                  child: _BottomAction(
                    icon: Icons.share_outlined,
                    label: 'Share',
                    onPressed: () => _shareCurrentAsset(),
                  ),
                ),
                // No "Download" action here: this viewer only ever shows
                // on-device assets, so saving a copy back to the gallery would
                // just duplicate a file that's already local. Downloading is
                // meaningful only for cloud-only items — see the separate
                // TelegramMediaViewerScreen, which keeps its Save action.
                //
                // Trash, on the other hand, is shown only for the Local tab
                // (allowDeviceDelete): it routes the file to Android's own
                // MediaStore trash — a 30-day, OS-owned recovery window — and
                // never touches the Telegram backup. See _trashFromDevice.
                if (widget.allowDeviceDelete)
                  Expanded(
                    child: _BottomAction(
                      icon: Icons.delete_outline,
                      label: 'Trash',
                      color: Colors.redAccent,
                      onPressed: () => _trashFromDevice(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _shareCurrentAsset() async {
    final asset = _currentAsset;
    // originFile is the real file bytes on disk — the same path backup uses.
    // Thumbnails would share a downscaled copy, so share the original.
    final file = await asset.originFile;
    if (!mounted) return;
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't load file to share")),
      );
      return;
    }
    await Share.shareXFiles([XFile(file.path)]);
  }

  /// Move the on-screen asset to the phone's trash — Local tab only.
  ///
  /// Uses Android's MediaStore trash (`createTrashRequest`, Android 11+/API 30):
  /// Android shows its own confirmation, then moves the file to the system
  /// trash and permanently deletes it after 30 days. It's recoverable from the
  /// phone's Trash until then. This removes only the on-device copy — a
  /// Telegram backup, if any, is deliberately left untouched, since "delete
  /// from phone" is not the same as removing the cloud backup.
  Future<void> _trashFromDevice() async {
    final asset = _currentAsset;
    final noun = asset.type == AssetType.video ? 'video' : 'photo';
    final repository = ref.read(galleryRepositoryProvider);
    final isBackedUp =
        repository.getItemById(asset.id)?.status == MediaStatus.uploaded;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.delete_outline,
          color: Colors.redAccent,
          size: 40,
        ),
        title: Text('Move this $noun to trash?'),
        content: Text(
          isBackedUp
              ? 'It moves to your phone’s trash and is permanently deleted '
                    'after 30 days. Your backup stays safe in Telegram.'
              : 'It isn’t backed up yet. It moves to your phone’s trash and is '
                    'permanently deleted after 30 days — restore it from your '
                    'phone’s trash before then.',
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
      // Android shows the user its own trash-confirmation dialog and returns
      // the ids it actually trashed — empty if the user cancels there.
      final trashed = await PhotoManager.editor.android.moveToTrash([asset]);
      if (!mounted) return;

      // Empty result = the user backed out of the system dialog (or nothing
      // was trashed). Leave the viewer as-is.
      if (!trashed.contains(asset.id)) return;

      // Mark the item as trashed in the app database so the Trash screen
      // shows it. PhotoManager.moveToTrash handles the OS-level trash;
      // this handles the app-level tracking.
      await repository.moveToTrash(asset.id);

      if (!mounted) return;
      // The asset is gone from the device gallery now. Refresh the providers
      // that list device assets so the deleted item drops out of the grid and
      // the map, then close the viewer — the asset it was showing is gone.
      ref.invalidate(deviceAssetsProvider);
      ref.invalidate(mapPhotosProvider);
      ref.invalidate(trashedItemsProvider);
      _notify(context, 'Moved to your phone’s trash · deletes in 30 days');
      context.pop();
    } on PlatformException {
      // moveToTrash is Android 11+ (API 30) only — older versions have no
      // MediaStore trash, so there's no 30-day-recovery delete to offer.
      if (!mounted) return;
      _notify(context, 'Deleting to trash needs Android 11 or newer');
    } catch (_) {
      if (!mounted) return;
      _notify(context, 'Couldn’t delete this $noun');
    }
  }

  /// Open the map picker to set or edit this photo's GPS location.
  Future<void> _openLocationPicker() async {
    final asset = _currentAsset;
    final repository = ref.read(galleryRepositoryProvider);
    final currentItem = repository.getItemById(asset.id);

    final result = await context.push<LocationPickerResult>(
      '/gallery/pick-location',
      extra: {
        'latitude': currentItem?.latitude,
        'longitude': currentItem?.longitude,
      },
    );

    if (!mounted || result == null) return;

    if (result.isRemove) {
      await repository.setLocation(asset.id);
    } else if (result.isConfirm) {
      await repository.setLocation(
        asset.id,
        latitude: result.latitude,
        longitude: result.longitude,
      );
    } else {
      return; // Back button — no change
    }

    if (!mounted) return;
    ref.invalidate(mapPhotosProvider);
    ref.invalidate(mediaItemProvider(asset.id));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.isRemove ? 'Location removed' : 'Location saved'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Back up the photo on screen, here and now.
  ///
  /// The button used to only flip an include/exclude flag, which meant the
  /// upload didn't happen until the user separately went to the backup screen
  /// and pressed Start Backup. This uploads this one file directly.
  Future<void> _backUpCurrentAsset({bool allowMobileData = false}) async {
    final asset = _currentAsset;
    final repository = ref.read(galleryRepositoryProvider);

    setState(() => _inFlight.add(asset.id));
    try {
      // Asking to back a photo up implies including it. This also builds the
      // MediaItem record on demand (via the incremental scanner) for an asset
      // that has never been scanned, which is what makes the button work on a
      // fresh install before any backup run.
      await repository.setBackupExcluded(
        localId: asset.id,
        excluded: false,
        asset: asset,
      );

      final item = repository.getItemById(asset.id);
      if (item == null) {
        if (!mounted) return;
        _notify(context, "Couldn't read this file to back it up");
        return;
      }

      final result = await ref
          .read(backupEngineProvider.notifier)
          .backupItemNow(item, allowMobileData: allowMobileData);

      if (!mounted) return;

      switch (result.outcome) {
        case SingleBackupOutcome.uploaded:
          _notify(context, 'Backed up to Telegram');
        case SingleBackupOutcome.alreadyBackedUp:
          _notify(context, 'Already backed up');
        case SingleBackupOutcome.queued:
          _notify(context, 'Queued — a backup is already running');
        case SingleBackupOutcome.skipped:
          _notify(context, result.message ?? 'Skipped by your backup settings');
        case SingleBackupOutcome.needsMobileDataConfirmation:
          _notify(
            context,
            'Wi-Fi only is on and you’re on mobile data',
            action: SnackBarAction(
              label: 'Back up anyway',
              onPressed: () => _backUpCurrentAsset(allowMobileData: true),
            ),
            duration: const Duration(seconds: 6),
          );
        case SingleBackupOutcome.failed:
          _notify(context, result.message ?? 'Backup failed');
      }
    } finally {
      if (mounted) setState(() => _inFlight.remove(asset.id));
    }
  }

  void _notify(
    BuildContext context,
    String message, {
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), action: action, duration: duration),
    );
  }
}

/// The backup button in the bottom bar: a labeled icon that turns into a
/// progress ring while this photo is uploading, and otherwise shows the
/// queued state or an actionable "Back up". Only built for items that aren't
/// backed up yet — [MediaViewerScreen.build] omits it once an item is backed
/// up, so there is no terminal "Backed up" state here.
class _BackupAction extends StatelessWidget {
  const _BackupAction({
    required this.isUploading,
    required this.isQueued,
    required this.progress,
    required this.onPressed,
  });

  final bool isUploading;
  final bool isQueued;
  final double progress;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (isUploading) {
      // Tapping again mid-upload does nothing useful, so the button is
      // disabled and the ring stands in for the icon.
      return _BottomAction(
        icon: Icons.cloud_sync,
        iconWidget: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.syncing,
          ),
        ),
        label: 'Backing up ${(progress * 100).round()}%',
        color: AppColors.syncing,
        onPressed: null,
      );
    }

    final IconData icon;
    final String label;
    final Color color;
    if (isQueued) {
      icon = Icons.cloud_queue;
      label = 'Queued';
      color = AppColors.syncing;
    } else {
      icon = Icons.backup_outlined;
      label = 'Back up';
      color = Colors.white;
    }

    return _BottomAction(
      icon: icon,
      label: label,
      color: color,
      onPressed: onPressed,
    );
  }
}

/// A vertical icon-over-label button for the media viewer's bottom action bar.
class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconWidget,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Overrides [icon] when a non-Icon glyph is needed (e.g. a progress ring).
  final Widget? iconWidget;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget ?? Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetPreview extends StatelessWidget {
  const _AssetPreview({required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    if (asset.type == AssetType.video) return _buildVideo(context);
    return _buildImage(context);
  }

  Widget _buildVideo(BuildContext context) {
    return FutureBuilder<File?>(
      // The real file on disk — the same bytes backup and share use — is what
      // video_player needs. Thumbnails are only decodable as still images.
      future: asset.file,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          );
        }
        final file = snapshot.data;
        if (file == null) {
          return const Center(
            child: Icon(Icons.broken_image, color: Colors.white38, size: 64),
          );
        }
        return InlineVideoPlayer(file: file);
      },
    );
  }

  Widget _buildImage(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      // A large-but-bounded size renders quickly (photo_manager's cached
      // thumbnail pipeline) rather than needing the slow, timeout-prone
      // originFile() path just to preview something — that one's reserved
      // for backup, where the real file bytes are actually needed.
      future: asset.thumbnailDataWithSize(const ThumbnailSize(1600, 1600)),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(
            child: Icon(Icons.broken_image, color: Colors.white38, size: 64),
          );
        }
        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
        );
      },
    );
  }
}
