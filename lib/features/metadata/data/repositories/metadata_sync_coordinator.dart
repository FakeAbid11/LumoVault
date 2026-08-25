import 'dart:async';

import 'package:flutter/foundation.dart';

import 'metadata_repository.dart';
import 'telegram_metadata_downloader.dart';
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
    this.downloader,
  }) {
    _subscription = metadataRepository.changeStream.listen((event) {
      if (event.operation != 'sync_pending') return;
      unawaited(syncNow());
    });
  }

  final MetadataRepository metadataRepository;
  final TelegramMetadataUploader uploader;

  /// Pull side of two-way sync. Optional so existing push-only construction
  /// sites (and tests) keep working; [pullNow] is a no-op when it is null.
  final TelegramMetadataDownloader? downloader;

  StreamSubscription<MetadataChangeEvent>? _subscription;

  /// One re-entrancy guard shared by both the push ([syncNow]) and pull
  /// ([pullNow]) paths. They both mutate the repository's unlocked partition
  /// map, so letting a pull-reconcile interleave with a push-serialize would
  /// race on that shared state. A single mutex means at most one of them
  /// touches the partition set at a time; the other returns 0 immediately.
  bool _busy = false;

  /// The sync currently in flight, if any.
  ///
  /// Syncs started by the change-stream listener above are fire-and-forget —
  /// no caller holds their future — so without this there is no way to tell
  /// when a gallery mutation has actually reached the channel. See [settle].
  Future<int>? _inFlight;

  /// Sync dirty partitions and the manifest to Telegram.
  ///
  /// Returns the number of partitions uploaded (manifest-only runs return 0).
  /// Re-entrant calls (a push or pull already running) return 0 immediately.
  ///
  /// Not `async`: the guard has to flip before the first suspension point so
  /// two calls in the same microtask turn can't both get past it.
  Future<int> syncNow() {
    if (_busy) return Future.value(0);
    _busy = true;
    return _inFlight = _guardedSync();
  }

  /// Push wrapped in the shared guard: releases [_busy] when done.
  Future<int> _guardedSync() async {
    try {
      return await _runSync();
    } finally {
      _busy = false;
    }
  }

  /// The actual push, with no guard handling of its own so [pullNow] can drive
  /// it while already holding [_busy].
  Future<int> _runSync() async {
    if (metadataRepository.getCurrentManifest() == null) {
      await metadataRepository.generateManifest(
        deviceHash: await uploader.deviceHash(),
      );
    }
    return await metadataRepository.syncToTelegram(
      uploadPartition: uploader.uploadPartition,
      uploadManifest: uploader.uploadManifest,
    );
  }

  /// Completes once no sync is in flight.
  ///
  /// Call after [dispose] to drain work the debounced flush had already
  /// started: the uploader writes each document to a temp directory before
  /// sending it, so tearing that directory down while a sync is still running
  /// leaves it cleaning up files that are already gone.
  ///
  /// Loops because a sync can be started while an earlier one is being
  /// awaited. Errors are swallowed here — whoever called [syncNow], or the
  /// fire-and-forget listener, owns them; [settle] only reports quiescence.
  Future<void> settle() async {
    var run = _inFlight;
    while (run != null) {
      await run.then<void>((_) {}, onError: (_) {});
      if (identical(run, _inFlight)) _inFlight = null;
      run = _inFlight;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Pull the remote metadata layer and reconcile it into local state, then
  /// push back anything the merge left dirty (partitions where the local copy
  /// won, or local-only items the remote didn't have) so the two devices
  /// converge in one pass.
  ///
  /// Re-entrant calls return 0 immediately. A null [downloader] (push-only
  /// construction) makes this a no-op. Safe to call at bootstrap and whenever
  /// the live channel listener sees a change.
  Future<int> pullNow() {
    final dl = downloader;
    if (dl == null) return Future.value(0);
    if (_busy) return Future.value(0);
    _busy = true;
    return _inFlight = _guardedPull(dl);
  }

  Future<int> _guardedPull(TelegramMetadataDownloader dl) async {
    try {
      // Fresh scan of channel history each pull so newly-uploaded documents
      // are seen (the index is cached for the duration of one pull).
      dl.invalidate();
      final applied = await metadataRepository.reconcileFromTelegram(
        downloadManifest: dl.downloadManifest,
        downloadPartition: dl.downloadPartition,
      );

      // Reconcile may have left partitions dirty (local-wins / local-only).
      // Push them so the remote converges on our winners too. Driven inline
      // (not fire-and-forget) while still holding the shared guard, so the
      // push completes before another pull/push can start and the caller's
      // returned future actually reflects a settled two-way sync.
      if (metadataRepository.getDirtyPartitions().isNotEmpty) {
        await _runSync();
      }
      return applied;
    } catch (e) {
      debugPrint('[MetadataSyncCoordinator] Pull failed: $e');
      return 0;
    } finally {
      _busy = false;
    }
  }
}
