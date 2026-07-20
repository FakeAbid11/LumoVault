import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/backup_providers.dart';
import '../../../../core/di/gallery_providers.dart';


/// Full-screen photo/video viewer.
///
/// Was a stub before — no image, no swiping, every action a no-op. This
/// shows the actual asset, lets you swipe through [assets], and includes a
/// backup include/exclude toggle so a specific photo can be selected for
/// backup right from the preview.
class MediaViewerScreen extends ConsumerStatefulWidget {
  const MediaViewerScreen({
    required this.assets,
    required this.initialIndex,
    super.key,
  });

  final List<AssetEntity> assets;
  final int initialIndex;

  @override
  ConsumerState<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;

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
    final currentItem = repository.getItemById(_currentAsset.id);
    // Defaults to true (not selected) when there's no record yet — matches
    // the scanner's new opt-in default. An item you've never touched isn't
    // selected for backup, same as one you've explicitly excluded.
    final isExcluded = currentItem?.isExcluded ?? true;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.assets.length}',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isExcluded
                  ? Icons.cloud_off_outlined
                  : Icons.cloud_upload_outlined,
            ),
            tooltip: isExcluded
                ? 'Excluded from backup — tap to include'
                : 'Included in backup — tap to exclude',
            onPressed: () => _toggleBackupInclusion(context, isExcluded),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share',
            onPressed: () {
              // TODO: Wire to share_plus once available.
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.assets.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) =>
            _AssetPreview(asset: widget.assets[index]),
      ),
      bottomNavigationBar: Container(
        color: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isExcluded ? Icons.cloud_off : Icons.cloud_done,
                color: isExcluded ? Colors.grey : Colors.greenAccent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                isExcluded ? 'Not backed up' : 'Selected for backup',
                style: TextStyle(
                  color: isExcluded ? Colors.grey : Colors.greenAccent,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleBackupInclusion(
    BuildContext context,
    bool currentlyExcluded,
  ) async {
    final repository = ref.read(galleryRepositoryProvider);
    final asset = _currentAsset;

    await repository.setBackupExcluded(
      localId: asset.id,
      excluded: !currentlyExcluded,
      asset: asset,
    );

    // Reflect the choice in the backup queue right away so the dashboard
    // updates immediately, instead of only after the next full "Start
    // Backup" scan. Including => enqueue the freshly-built item; excluding
    // => drop any queued task for it.
    final backupNotifier = ref.read(backupEngineProvider.notifier);
    if (currentlyExcluded) {
      final item = repository.getItemById(asset.id);
      if (item != null) backupNotifier.enqueueSelectedItem(item);
    } else {
      backupNotifier.dequeueSelectedItem(asset.id);
    }

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          currentlyExcluded ? 'Included for backup' : 'Excluded from backup',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
    setState(() {});
  }
}

class _AssetPreview extends StatelessWidget {
  const _AssetPreview({required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
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
