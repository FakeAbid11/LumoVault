import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/channel_scan_providers.dart';
import '../../../../core/di/tdlib_providers.dart';
import '../../../../core/storage/storage_channel_service.dart';
import '../../../restore/presentation/providers/restore_providers.dart';
import '../../data/models/media_item.dart';
import '../../data/models/transfer_error.dart';
import '../../data/repositories/telegram_download_service.dart';

/// Full-screen viewer for Telegram-only items (backed-up copies with no
/// local file).
///
/// Mirrors [MediaViewerScreen]'s swipe-through-pages pattern, but resolves
/// bytes on demand: images download the original file via TDLib with live
/// progress and a retry affordance; videos show their cached thumbnail with
/// a play badge (originals are downloaded through the restore flow). The
/// app-bar info action opens [TelegramItemDetailSheet] for backup details.
class TelegramMediaViewerScreen extends ConsumerStatefulWidget {
  const TelegramMediaViewerScreen({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  final List<MediaItem> items;
  final int initialIndex;

  @override
  ConsumerState<TelegramMediaViewerScreen> createState() =>
      _TelegramMediaViewerScreenState();
}

class _TelegramMediaViewerScreenState
    extends ConsumerState<TelegramMediaViewerScreen> {
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

  @override
  Widget build(BuildContext context) {
    final currentItem = widget.items[_currentIndex];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.items.length}',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Backup details',
            onPressed: () => showModalBottomSheet(
              context: context,
              builder: (context) => TelegramItemDetailSheet(item: currentItem),
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.items.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) =>
            _TelegramPreview(item: widget.items[index]),
      ),
    );
  }
}

class _TelegramPreview extends ConsumerStatefulWidget {
  const _TelegramPreview({required this.item});

  final MediaItem item;

  @override
  ConsumerState<_TelegramPreview> createState() => _TelegramPreviewState();
}

class _TelegramPreviewState extends ConsumerState<_TelegramPreview> {
  late final DownloadService _downloadService;
  late String _taskId;
  Future<DownloadResult>? _downloadFuture;
  StreamSubscription<DownloadProgress>? _progressSubscription;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _downloadService = ref.read(downloadServiceProvider);
    _taskId = _newTaskId();
    if (!widget.item.isVideo) {
      _downloadFuture = _startDownload();
      _progressSubscription = _downloadService.progressStream.listen((p) {
        if (p.taskId == _taskId && mounted) {
          setState(() => _progress = p.progress);
        }
      });
    }
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  String _newTaskId() =>
      'viewer_${widget.item.localId}_${DateTime.now().millisecondsSinceEpoch}';

  Future<DownloadResult> _startDownload() async {
    final messageId = int.tryParse(widget.item.telegramMessageId ?? '');
    if (messageId == null) {
      throw StateError('No Telegram message id for ${widget.item.localId}');
    }

    final storageChannelService = ref.read(storageChannelServiceProvider);
    var channelId = storageChannelService.cachedChannelId;
    if (channelId == null) {
      final result = await storageChannelService.findExistingChannel();
      if (result is! StorageChannelFound) {
        throw StateError('Storage channel not found');
      }
      channelId = result.channelId;
    }

    return _downloadService.downloadFile(
      taskId: _taskId,
      messageId: messageId,
      channelId: channelId,
      mode: DownloadMode.original,
    );
  }

  Future<void> _retry() async {
    await _downloadService.cancelDownload(_taskId);
    setState(() {
      _progress = 0;
      _taskId = _newTaskId();
      _downloadFuture = _startDownload();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.isVideo) return _buildVideoPreview(context);
    return _buildImagePreview(context);
  }

  Widget _buildImagePreview(BuildContext context) {
    return FutureBuilder<DownloadResult>(
      future: _downloadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildDownloading(context);
        }
        final filePath = snapshot.data?.filePath ?? '';
        if (snapshot.hasError || filePath.isEmpty) {
          return _buildError(context, snapshot.error);
        }
        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(child: Image.file(File(filePath), fit: BoxFit.contain)),
        );
      },
    );
  }

  Widget _buildDownloading(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              value: _progress,
              color: Colors.white70,
              backgroundColor: Colors.white24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _progress > 0
                ? '${(_progress * 100).round()}%'
                : 'Downloading original…',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, Object? error) {
    String message;
    if (error is TransferError) {
      message = error.message;
    } else if (error != null) {
      message = error.toString();
    } else {
      message = 'Could not download this photo';
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white38, size: 64),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPreview(BuildContext context) {
    final fetcher = ref.read(telegramThumbnailFetcherProvider);
    return FutureBuilder<Uint8List?>(
      future: fetcher.fetch(widget.item),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              Image.memory(bytes, fit: BoxFit.contain)
            else
              Container(
                color: Colors.black,
                child: const Center(
                  child: Icon(Icons.videocam, color: Colors.white38, size: 64),
                ),
              ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${_formatDuration(widget.item.durationMs)} · '
                    'Stored in Telegram',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(int? durationMs) {
    if (durationMs == null) return '0:00';
    final seconds = (durationMs / 1000).floor();
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

/// Bottom sheet with backup details for a Telegram-only item.
///
/// Shared between the timeline (long-press/tap affordances) and
/// [TelegramMediaViewerScreen]'s info action.
class TelegramItemDetailSheet extends StatelessWidget {
  const TelegramItemDetailSheet({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.cloud_done,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Backed up to Telegram',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _detailRow(context, 'File name', item.fileName),
            _detailRow(context, 'Size', _formatFileSize(item.fileSize)),
            _detailRow(
              context,
              'Created',
              item.createdAt.toString().split('.').first,
            ),
            if (item.isVideo && item.durationMs != null)
              _detailRow(context, 'Duration', _formatDuration(item.durationMs)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDuration(int? durationMs) {
    if (durationMs == null) return '0:00';
    final seconds = (durationMs / 1000).floor();
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
