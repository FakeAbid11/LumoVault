import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/backup_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../core/di/geocoding_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../backup/engine/backup_engine.dart';
import '../../../../shared/widgets/swipe_dismiss_wrapper.dart';
import '../../data/models/media_item.dart';
import '../../data/models/upload_task.dart';
import '../widgets/exif_details_sheet.dart';
import '../widgets/inline_video_player.dart';
import 'location_picker_screen.dart';
import 'package:material_symbols_icons/symbols.dart';

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

  bool _isChromeVisible = true;

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

  bool _isZoomed = false;

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

    final geoLabel = hasLocation
        ? ref.watch(
            reverseGeocodeProvider((
              currentItem!.latitude!,
              currentItem.longitude!,
            )),
          )
        : null;
    final locationLabel = geoLabel?.valueOrNull?.displayName;
    final displayLocationLabel =
        (locationLabel != null && locationLabel.isNotEmpty)
        ? locationLabel
        : (hasLocation ? 'Location' : 'Add Location');

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Tap target + image body
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => setState(() => _isChromeVisible = !_isChromeVisible),
            child: SwipeDismissWrapper(
              enabled: !_isZoomed,
              onSwipeUp: _showExifDetails,
              child: PageView.builder(
                controller: _pageController,
                physics: _isZoomed
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                itemCount: widget.assets.length,
                onPageChanged: (index) {
                  if (_currentIndex != index) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _currentIndex = index;
                      _isZoomed = false;
                    });
                  }
                },
                itemBuilder: (context, index) => _AssetPreview(
                  asset: widget.assets[index],
                  onZoomChanged: (zoomed) {
                    if (_isZoomed != zoomed) {
                      setState(() => _isZoomed = zoomed);
                    }
                  },
                ),
              ),
            ),
          ),

          // Animated AppBar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _isChromeVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: AnimatedSlide(
                offset: _isChromeVisible ? Offset.zero : const Offset(0, -0.2),
                duration: const Duration(milliseconds: 250),
                child: AppBar(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  title: Text(
                    '${_currentIndex + 1} / ${widget.assets.length}',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Symbols.info),
                      tooltip: 'Info & EXIF',
                      onPressed: _showExifDetails,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Animated bottom bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _isChromeVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: AnimatedSlide(
                offset: _isChromeVisible ? Offset.zero : const Offset(0, 0.2),
                duration: const Duration(milliseconds: 250),
                child: Container(
                  color: Colors.black,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 24,
                      ),
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
                              icon: Symbols.location_on,
                              label: displayLocationLabel,
                              color: hasLocation
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                              onPressed: () => _openLocationPicker(),
                            ),
                          ),
                          Expanded(
                            child: _BottomAction(
                              icon: Symbols.share,
                              label: 'Share',
                              onPressed: () => _shareCurrentAsset(),
                            ),
                          ),
                          if (widget.allowDeviceDelete)
                            Expanded(
                              child: _BottomAction(
                                icon: Symbols.delete,
                                label: 'Trash',
                                color: Theme.of(context).colorScheme.error,
                                onPressed: () => _trashFromDevice(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
          _notify(context, friendlySkipMessage(result.message));
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

  void _showExifDetails() {
    final asset = _currentAsset;
    final item = ref.read(galleryRepositoryProvider).getItemById(asset.id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ExifDetailsSheet(
        asset: asset,
        item: item,
        onLocationChanged: () {
          ref.invalidate(mapPhotosProvider);
          ref.invalidate(mediaItemProvider(asset.id));
        },
      ),
    );
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
        icon: Symbols.cloud_sync,
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
      icon = Symbols.cloud_queue;
      label = 'Queued';
      color = AppColors.syncing;
    } else {
      icon = Symbols.backup;
      label = 'Back up';
      color = Theme.of(context).colorScheme.onSurface;
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
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Overrides [icon] when a non-Icon glyph is needed (e.g. a progress ring).
  final Widget? iconWidget;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget ?? Icon(icon, color: effectiveColor, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: effectiveColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetPreview extends StatefulWidget {
  const _AssetPreview({required this.asset, this.onZoomChanged});

  final AssetEntity asset;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<_AssetPreview> createState() => _AssetPreviewState();
}

class _AssetPreviewState extends State<_AssetPreview>
    with SingleTickerProviderStateMixin {
  late final Future<Uint8List?> _thumbnailFuture;
  late final Future<File?> _fileFuture;
  late final bool _isVideo;

  /// Cheap poster for the decode window: photo_manager serves the grid's
  /// cached 300px thumbnail almost instantly, so the viewer opens on the
  /// photo instead of a bare spinner on black while the 1600px decode runs.
  Uint8List? _posterBytes;

  /// Progressive hi-res zoom layer. The base decode is 1600px so the photo
  /// opens instantly; past [_hiresZoomTrigger] a bounded 2800px decode runs
  /// once and swaps in with gapless playback, so deep pinch-zoom stays sharp
  /// instead of going soft. Uses thumbnailDataWithSize (platform-decoded,
  /// cache-friendly) rather than originBytes — full-resolution bytes of a
  /// 40MP+ photo would spike memory by hundreds of MB. The layer is dropped
  /// when the user returns to fit-scale so paging through photos doesn't pin
  /// large bitmaps in memory.
  static const double _hiresZoomTrigger = 1.8;

  Uint8List? _hiresBytes;
  bool _hiresStarted = false;

  /// Runs on every transformation tick (from the zoom target's build —
  /// field mutation only, no setState; the decode completion below triggers
  /// the real rebuild when it lands).
  void _updateHiresLayer(double scale) {
    if (_hiresBytes != null && scale <= 1.05) {
      // Back at fit-scale: release the hi-res bitmap and allow a future
      // zoom-in to fetch it again.
      _hiresBytes = null;
      _hiresStarted = false;
      return;
    }
    if (_hiresStarted || scale <= _hiresZoomTrigger) return;
    _hiresStarted = true;
    widget.asset.thumbnailDataWithSize(const ThumbnailSize(2800, 2800)).then((
      bytes,
    ) {
      if (mounted && bytes != null) {
        setState(() => _hiresBytes = bytes);
      }
    }, onError: (Object _) {});
  }

  final TransformationController _transformationController =
      TransformationController();
  late final AnimationController _zoomAnimationController;
  Animation<Matrix4>? _zoomAnimation;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _isVideo = widget.asset.type == AssetType.video;
    if (_isVideo) {
      _fileFuture = widget.asset.file;
    } else {
      _thumbnailFuture = widget.asset.thumbnailDataWithSize(
        const ThumbnailSize(1600, 1600),
      );
      // Best-effort: a failed poster read must not block the main decode.
      widget.asset.thumbnailData.then((bytes) {
        if (mounted && bytes != null) {
          setState(() => _posterBytes = bytes);
        }
      }, onError: (Object _) {});
    }
    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _transformationController.addListener(_onTransformationChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    _zoomAnimationController.dispose();
    super.dispose();
  }

  void _onTransformationChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final isZoomed = scale > 1.05;
    if (isZoomed != _isZoomed) {
      _isZoomed = isZoomed;
      widget.onZoomChanged?.call(isZoomed);
    }
  }

  void _handleDoubleTap(TapDownDetails details) {
    if (_zoomAnimationController.isAnimating) return;

    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final Matrix4 endMatrix;

    if (currentScale > 1.05) {
      endMatrix = Matrix4.identity();
    } else {
      final position = details.localPosition;
      final x = -position.dx * (2.5 - 1.0);
      final y = -position.dy * (2.5 - 1.0);
      endMatrix = Matrix4.diagonal3Values(2.5, 2.5, 1.0)
        ..setTranslationRaw(x, y, 0.0);
    }

    _zoomAnimation =
        Matrix4Tween(
          begin: _transformationController.value,
          end: endMatrix,
        ).animate(
          CurvedAnimation(
            parent: _zoomAnimationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _zoomAnimationController.forward(from: 0.0).then((_) {
      _transformationController.value = endMatrix;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isVideo) return _buildVideo(context);
    return _buildImage(context);
  }

  Widget _buildVideo(BuildContext context) {
    return FutureBuilder<File?>(
      future: _fileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          );
        }
        final file = snapshot.data;
        if (file == null) {
          return const Center(
            child: Icon(Symbols.broken_image, color: Colors.white38, size: 64),
          );
        }
        return InlineVideoPlayer(file: file);
      },
    );
  }

  Widget _buildImage(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _thumbnailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Paint the cached poster while the full-resolution decode runs —
          // a black frame here read as "the app broke" on slower devices.
          if (_posterBytes != null) {
            return Image.memory(
              _posterBytes!,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            );
          }
          return const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(
            child: Icon(Symbols.broken_image, color: Colors.white38, size: 64),
          );
        }
        return GestureDetector(
          onDoubleTapDown: _handleDoubleTap,
          onDoubleTap: () {},
          child: AnimatedBuilder(
            animation: _zoomAnimationController,
            builder: (context, child) {
              if (_zoomAnimationController.isAnimating &&
                  _zoomAnimation != null) {
                _transformationController.value = _zoomAnimation!.value;
              }
              return ValueListenableBuilder<Matrix4>(
                valueListenable: _transformationController,
                builder: (context, value, _) {
                  final scale = value.getMaxScaleOnAxis();
                  _updateHiresLayer(scale);
                  return InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 1.0,
                    maxScale: 4.5,
                    // Pan only while zoomed: at scale 1.0 there's nothing to
                    // pan, and an active pan recognizer steals the horizontal
                    // drags the PageView needs for photo-to-photo swiping.
                    // Derived from the live matrix (not a flag) so it can't
                    // drift out of sync with the actual zoom state.
                    panEnabled: scale > 1.05,
                    scaleEnabled: true,
                    clipBehavior: Clip.none,
                    child: Center(
                      // No Hero here: tiles dropped their heroes because
                      // Local/Timeline/Search kept mounted heroes for the same
                      // asset id under the IndexedStack shell, and duplicate
                      // tags corrupt hero flights in release builds.
                      // Double-tap handling lives on the wrapper above.
                      child: Image.memory(
                        _hiresBytes ?? bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

/// Maps a raw scheduler skip reason to a message a person can act on.
///
/// The scheduler's folder-gate text leaks internal identifiers (a raw OS
/// bucket id like "-1313584517") and jargon ("included list"). The viewer's
/// Back-Up button is the one place a user hits that refusal directly, so
/// translate it into what to do about it; anything unrecognized passes
/// through unchanged.
String friendlySkipMessage(String? message) {
  if (message == null) return 'Skipped by your backup settings';
  if (message.contains('is not in your backup folders') ||
      message.contains('is not in included list')) {
    return 'This folder isn\'t in your backup folders — enable it under '
        'Backup settings > Folders';
  }
  if (message.contains('is excluded')) {
    return 'This folder is on your backup exclusion list';
  }
  return message;
}
