import 'dart:async';

import 'metadata_repository.dart';
import 'telegram_metadata_uploader.dart';

/// Wires the metadata repository's sync layer (manifest + partition files) to
/// the Telegram storage channel.
///
/// This is the missing half of PRD Section 6: the repository already tracks
/// dirty partitions and knows how to serialize them, but nothing ever called
/// [MetadataRepository.syncToTelegram] with real upload callbacks. The
/// coordinator supplies those (via [TelegramMetadataUploader]) and makes sure
/// a manifest exists before syncing — the baseline for the dirty check lives
/// in the manifest, and the pinned manifest message is what a restore reads
/// to detect the backup.
///
/// It also listens for the 'sync_pending' event the debounced change flush
/// emits, so ordinary gallery mutations (favorites, trash, uploads, ...) reach
/// Telegram shortly after they happen, without any UI involvement.
class MetadataSyncCoordinator {
  MetadataSyncCoordinator({
    required this.metadataRepository,
    required this.uploader,
  }) {
    _subscription = metadataRepository.changeStream.listen((event) {
      if (event.operation != 'sync_pending') return;
      unawaited(syncNow());
    });
  }

  final MetadataRepository metadataRepository;
  final TelegramMetadataUploader uploader;

  StreamSubscription<MetadataChangeEvent>? _subscription;
  bool _syncing = false;

  /// Sync dirty partitions and the manifest to Telegram.
  ///
  /// Returns the number of partitions uploaded (manifest-only runs return 0).
  /// Re-entrant calls return 0 immediately — [SyncService] has its own
  /// in-progress guard, but the coordinator's own flag keeps the manifest
  /// bootstrap from being triggered twice concurrently.
  Future<int> syncNow() async {
    if (_syncing) return 0;
    _syncing = true;
    try {
      if (metadataRepository.getCurrentManifest() == null) {
        await metadataRepository.generateManifest(
          deviceHash: await uploader.deviceHash(),
        );
      }
      return await metadataRepository.syncToTelegram(
        uploadPartition: uploader.uploadPartition,
        uploadManifest: uploader.uploadManifest,
      );
    } finally {
      _syncing = false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
