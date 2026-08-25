import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/storage/storage_channel_service.dart';
import 'package:lumovault/core/tdlib/tdlib_client.dart';
import 'package:lumovault/features/backup/data/models/backup_settings.dart';
import 'package:lumovault/features/backup/engine/backup_engine.dart';
import 'package:lumovault/features/backup/engine/backup_scheduler.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/models/transfer_error.dart';
import 'package:lumovault/features/gallery/data/models/upload_task.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';
import 'package:lumovault/features/gallery/data/repositories/telegram_upload_service.dart';
import 'package:photo_manager/photo_manager.dart';

/// Behavioural coverage for [BackupEngine] — the upload orchestration path.
///
/// The engine had no tests at all: every prior backup test covered
/// [BackupScheduler] (pure functions) or [UploadQueue] in isolation, so
/// nothing exercised the engine's own decisions — batch sizing, retry
/// classification, channel resolution, or the crash-window ordering between
/// `markUploaded` and completing a queue entry.
///
/// [StorageChannelService] is used concretely rather than faked: it isn't
/// abstract, but `setCachedChannelId` short-circuits `_resolveChannelId`
/// before any TDLib call, so no real client is needed. Tests that need the
/// resolution failure path leave the cache unset and use a client-less
/// instance, whose lookup fails without touching the network.
void main() {
  // MediaItem/UploadTask are plain models, but GalleryRepository pulls in
  // photo_manager; binding initialization keeps that import safe.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupEngine batch sizing', () {
    test('uses the configured uploadBatchSize, not the queue default', () {
      final engine = _engine(
        settings: const BackupSettings(uploadBatchSize: 3),
      );
      addTearDown(engine.dispose);

      expect(engine.queue.batchSize, 3);
    });

    test('updateSettings propagates a changed uploadBatchSize', () {
      final engine = _engine(
        settings: const BackupSettings(uploadBatchSize: 3),
      );
      addTearDown(engine.dispose);

      engine.updateSettings(const BackupSettings(uploadBatchSize: 25));

      expect(engine.queue.batchSize, 25);
    });

    test(
      'a non-positive uploadBatchSize is floored to 1, not left to stall',
      () {
        // A batch size of 0 makes getNextBatch return nothing, which would stop
        // the backup dead rather than just slowing it down.
        final engine = _engine(
          settings: const BackupSettings(uploadBatchSize: 0),
        );
        addTearDown(engine.dispose);

        expect(engine.queue.batchSize, 1);

        engine.updateSettings(const BackupSettings(uploadBatchSize: -5));
        expect(engine.queue.batchSize, 1);
      },
    );
  });

  group('BackupEngine upload path', () {
    test(
      'a successful upload marks the item uploaded and completes the task',
      () async {
        final repo = _repo([_item('a')]);
        final uploads = _FakeUploadService();
        final engine = _engine(repo: repo, uploads: uploads);
        addTearDown(engine.dispose);

        engine.addToQueue(repo.mediaItems.single);
        await engine.startBackup();

        expect(engine.queue.completedCount, 1);
        expect(engine.queue.failedCount, 0);
        expect(repo.mediaItems.single.status, MediaStatus.uploaded);
        expect(repo.mediaItems.single.telegramMessageId, isNotNull);
      },
    );

    test('the local record is written before the task is completed', () async {
      // Completed tasks are dropped from the persisted queue, so completing
      // first opens a crash window where the file is in Telegram but the DB
      // still says pending — the next scan would re-upload and duplicate it.
      final repo = _repo([_item('a')]);
      final engine = _engine(repo: repo, uploads: _FakeUploadService());
      addTearDown(engine.dispose);

      MediaStatus? statusWhenCompleted;
      repo.onMarkUploaded = () {
        statusWhenCompleted = repo.mediaItems.single.status;
      };

      engine.addToQueue(repo.mediaItems.single);
      await engine.startBackup();

      // markUploaded ran while the task was still uploading, not after it
      // had already been flipped to completed.
      expect(statusWhenCompleted, isNot(MediaStatus.uploaded));
      expect(engine.queue.completedCount, 1);
    });

    test(
      'an upload that succeeds but fails to persist locally stays failed',
      () async {
        final repo = _repo([_item('a')])..markUploadedThrows = true;
        final engine = _engine(repo: repo, uploads: _FakeUploadService());
        addTearDown(engine.dispose);

        engine.addToQueue(repo.mediaItems.single);
        await engine.startBackup();

        // The bytes reached Telegram, but the mapping was lost — surfacing this
        // as failed keeps it user-retryable instead of silently orphaning it.
        expect(engine.queue.failedCount, 1);
        expect(engine.queue.completedCount, 0);
      },
    );

    test('a non-retryable TransferError fails the task immediately', () async {
      final repo = _repo([_item('a')]);
      final uploads = _FakeUploadService()
        ..error = TransferError(
          category: TransferErrorCategory.unknown,
          message: 'nope',
          retryable: false,
          occurredAt: DateTime.now(),
        );
      final engine = _engine(repo: repo, uploads: uploads);
      addTearDown(engine.dispose);

      engine.addToQueue(repo.mediaItems.single);
      await engine.startBackup();

      expect(engine.queue.failedCount, 1);
      expect(uploads.attempts, 1);
    });

    test(
      'an unexpected non-TransferError failure fails the task, not the run',
      () async {
        // A plugin crash used to propagate out of _processQueue and leave the
        // engine stuck in `uploading` with every remaining task frozen.
        final repo = _repo([_item('a'), _item('b')]);
        final uploads = _FakeUploadService()
          ..throwOnFirstCall = StateError('plugin exploded');
        final engine = _engine(repo: repo, uploads: uploads);
        addTearDown(engine.dispose);

        for (final item in repo.mediaItems) {
          engine.addToQueue(item);
        }
        await engine.startBackup();

        expect(engine.queue.failedCount, 1);
        expect(engine.queue.completedCount, 1);
        expect(engine.state, BackupEngineState.idle);
      },
    );

    test('a channel-resolution failure is classified retryable', () async {
      final repo = _repo([_item('a')]);
      // No cached channel id and an uninitialized client: resolution fails.
      final engine = _engine(
        repo: repo,
        uploads: _FakeUploadService(),
        cacheChannelId: false,
      );
      addTearDown(engine.dispose);

      engine.enqueueSelectedItem(repo.mediaItems.single);

      // Exhaust the retry budget up front. Otherwise the engine sleeps
      // through three real backoffs (5s + 5s + 10s) before settling, which
      // would make this single test dominate the suite's runtime. The
      // classification is what's under test, not the sleeping.
      final queued = engine.queue.queuedTasks.single;
      engine.queue.updateTask(
        queued.copyWith(retryCount: UploadTask.maxAttempts),
      );

      await engine.startBackup();

      final task = engine.queue.allTasks.single;
      expect(task.status, UploadStatus.failed);
      // Retryable-but-budget-exhausted, not a permanent classification.
      expect(task.error?.retryable, isTrue);
      expect(engine.queue.completedCount, 0);
    });

    test(
      'a retryable failure defers its own retry without stalling siblings',
      () async {
        // Regression: the retry backoff used to be an inline
        // `await Future.delayed(backoff)` inside the batch loop, so one flaky
        // upload froze every healthy upload behind it for the whole backoff.
        // Now the failed task is stamped with a future nextAttemptAt and the
        // loop moves straight on, so the sibling uploads immediately.
        final repo = _repo([_item('a'), _item('b')]);
        final uploads = _FakeUploadService()
          ..throwOnFirstCall = TransferError(
            category: TransferErrorCategory.network,
            message: 'transient',
            retryable: true,
            occurredAt: DateTime.now(),
          );
        final engine = _engine(repo: repo, uploads: uploads);
        addTearDown(engine.dispose);

        for (final item in repo.mediaItems) {
          engine.addToQueue(item);
        }

        // 'a' sorts before 'b', so 'a' is attempted first and fails
        // retryably. If the loop still slept inline this call would hang for
        // the full backoff; instead it returns promptly with 'b' done.
        await engine.startBackup().timeout(const Duration(seconds: 2));

        // The sibling uploaded despite 'a' failing.
        expect(uploads.uploadedFileNames, contains('b.jpg'));
        expect(engine.queue.completedCount, 1);

        // 'a' is re-queued for a future attempt, not failed or retried inline.
        final deferred = engine.queue.queuedTasks
            .where((t) => t.mediaItemId == 'a')
            .toList();
        expect(deferred, hasLength(1));
        expect(deferred.single.nextAttemptAt, isNotNull);
        expect(deferred.single.nextAttemptAt!.isAfter(DateTime.now()), isTrue);
        // getNextBatch skips the deferred task while its backoff is unelapsed.
        expect(engine.queue.getNextBatch(), isEmpty);
      },
    );

    test('every queued item uploads even when the batch size is 1', () async {
      // Exercises the _processQueue recursion across batch boundaries.
      final repo = _repo([_item('a'), _item('b'), _item('c')]);
      final engine = _engine(
        repo: repo,
        uploads: _FakeUploadService(),
        settings: const BackupSettings(uploadBatchSize: 1),
      );
      addTearDown(engine.dispose);

      for (final item in repo.mediaItems) {
        engine.addToQueue(item);
      }
      await engine.startBackup();

      expect(engine.queue.completedCount, 3);
      expect(engine.queue.pendingCount, 0);
    });

    test(
      'progress events from the upload service reach the queued task',
      () async {
        final repo = _repo([_item('a')]);
        final uploads = _FakeUploadService()..emitProgress = 0.5;
        final engine = _engine(repo: repo, uploads: uploads);
        addTearDown(engine.dispose);

        final seen = <double>[];
        final sub = engine.statsStream.listen((s) => seen.add(s.progress));
        addTearDown(sub.cancel);

        engine.addToQueue(repo.mediaItems.single);
        await engine.startBackup();
        await pumpEventQueue();

        expect(seen, isNotEmpty);
        expect(engine.queue.completedCount, 1);
      },
    );
  });

  group('BackupEngine queue mutation', () {
    test('addToQueue skips excluded, hidden, trashed and uploaded items', () {
      final engine = _engine();
      addTearDown(engine.dispose);

      // isExcluded (the flag the scanners actually set) — note that
      // MediaStatus.excluded is never written anywhere in lib/, so the flag
      // is the real signal here.
      engine.addToQueue(_item('x', isExcluded: true));
      engine.addToQueue(_item('y', isHidden: true));
      engine.addToQueue(_item('z', isTrashed: true));
      engine.addToQueue(_item('w', status: MediaStatus.uploaded));

      expect(engine.queue.totalCount, 0);
    });

    test('dequeueSelectedItem drops the task so it will not upload', () {
      final engine = _engine();
      addTearDown(engine.dispose);
      final item = _item('a');

      engine.enqueueSelectedItem(item);
      expect(engine.queue.pendingCount, 1);

      engine.dequeueSelectedItem(item.localId);
      expect(engine.queue.pendingCount, 0);
    });

    test('pause stops the run mid-queue', () async {
      final repo = _repo([_item('a'), _item('b'), _item('c')]);
      final uploads = _FakeUploadService();
      final engine = _engine(repo: repo, uploads: uploads);
      addTearDown(engine.dispose);

      uploads.onUpload = (_) => engine.pauseBackup();

      for (final item in repo.mediaItems) {
        engine.addToQueue(item);
      }
      await engine.startBackup();

      expect(engine.state, BackupEngineState.paused);
      expect(uploads.attempts, 1);
    });
  });

  group('BackupEngine teardown', () {
    test('dispose is idempotent', () {
      final engine = _engine();

      engine.dispose();
      expect(engine.dispose, returnsNormally);
      expect(engine.isDisposed, isTrue);
    });

    test('a post-dispose queue mutation does not throw on closed streams', () {
      // An in-flight upload continuation can resolve after teardown and reach
      // _updateStats, which adds to the (now closed) stats controller.
      final engine = _engine();
      engine.dispose();

      expect(() => engine.addToQueue(_item('a')), returnsNormally);
      expect(() => engine.clearFinished(), returnsNormally);
    });
  });

  group('BackupEngine.backupItemNow', () {
    test('uploads just the tapped item, leaving the rest queued', () async {
      // Two other items are already waiting. A single-item backup must not turn
      // into a full queue drain — that's the whole point of the viewer button.
      final repo = _repo([_item('a'), _item('b'), _item('c')]);
      final uploads = _FakeUploadService();
      final engine = _engine(repo: repo, uploads: uploads);
      addTearDown(engine.dispose);
      await engine.ready;

      engine.addToQueue(_item('b'));
      engine.addToQueue(_item('c'));

      final result = await engine.backupItemNow(_item('a'));

      expect(result.outcome, SingleBackupOutcome.uploaded);
      expect(uploads.attempts, 1);
      expect(uploads.uploadedFileNames, ['a.jpg']);
      // 'b' and 'c' were never touched.
      expect(engine.queue.pendingCount, 2);
      // And the engine is back to idle, not stuck advertising `uploading`.
      expect(engine.state, BackupEngineState.idle);
    });

    test('marks the item uploaded in the gallery', () async {
      final repo = _repo([_item('a')]);
      final engine = _engine(repo: repo);
      addTearDown(engine.dispose);
      await engine.ready;

      await engine.backupItemNow(_item('a'));

      final stored = repo.mediaItems.firstWhere((i) => i.localId == 'a');
      expect(stored.status, MediaStatus.uploaded);
      expect(stored.telegramMessageId, isNotNull);
    });

    test('an already-uploaded item is a no-op', () async {
      final uploads = _FakeUploadService();
      final engine = _engine(uploads: uploads);
      addTearDown(engine.dispose);
      await engine.ready;

      final result = await engine.backupItemNow(
        _item('a', status: MediaStatus.uploaded),
      );

      expect(result.outcome, SingleBackupOutcome.alreadyBackedUp);
      expect(uploads.attempts, 0);
    });

    test('an item excluded by the user is skipped with a reason', () async {
      final uploads = _FakeUploadService();
      final engine = _engine(uploads: uploads);
      addTearDown(engine.dispose);
      await engine.ready;

      final result = await engine.backupItemNow(_item('a', isExcluded: true));

      expect(result.outcome, SingleBackupOutcome.skipped);
      expect(result.message, isNotNull);
      expect(uploads.attempts, 0);
    });

    test('wifi-only on mobile data asks before spending data', () async {
      final uploads = _FakeUploadService();
      final engine = _engine(uploads: uploads);
      addTearDown(engine.dispose);
      await engine.ready;
      engine.updateEnvironment(
        const BackupEnvironment(isWifiConnected: false, isCharging: true),
      );

      final blocked = await engine.backupItemNow(_item('a'));
      expect(blocked.outcome, SingleBackupOutcome.needsMobileDataConfirmation);
      expect(uploads.attempts, 0);

      // Confirming goes through.
      final confirmed = await engine.backupItemNow(
        _item('a'),
        allowMobileData: true,
      );
      expect(confirmed.outcome, SingleBackupOutcome.uploaded);
      expect(uploads.attempts, 1);
    });

    test('the auto-backup toggle does not block an explicit tap', () async {
      // Auto backup off means "don't back up behind my back", not "refuse when
      // I press the button" — the button would otherwise be silently dead.
      final uploads = _FakeUploadService();
      final engine = _engine(
        uploads: uploads,
        settings: const BackupSettings(isAutoBackupEnabled: false),
      );
      addTearDown(engine.dispose);
      await engine.ready;

      final result = await engine.backupItemNow(_item('a'));

      expect(result.outcome, SingleBackupOutcome.uploaded);
      expect(uploads.attempts, 1);
    });

    test('a failed upload reports the failure', () async {
      final uploads = _FakeUploadService()
        ..error = TransferError(
          category: TransferErrorCategory.unknown,
          message: 'nope',
          retryable: false,
          occurredAt: DateTime.now(),
        );
      final engine = _engine(uploads: uploads);
      addTearDown(engine.dispose);
      await engine.ready;

      final result = await engine.backupItemNow(_item('a'));

      expect(result.outcome, SingleBackupOutcome.failed);
      expect(result.message, 'nope');
      expect(engine.state, BackupEngineState.idle);
    });

    test('while a backup is paused, the item is queued instead', () async {
      // Same guard that protects against racing an in-progress full run:
      // don't start a second upload path, hand the item to the existing one.
      // Its user-initiated priority puts it at the front of the next batch.
      final uploads = _FakeUploadService();
      final engine = _engine(uploads: uploads);
      addTearDown(engine.dispose);
      await engine.ready;
      engine.pauseBackup();

      final result = await engine.backupItemNow(_item('z'));

      expect(result.outcome, SingleBackupOutcome.queued);
      expect(uploads.attempts, 0);
      expect(engine.queue.getTaskForMediaItem('z'), isNotNull);
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

BackupEngine _engine({
  _FakeGalleryRepository? repo,
  _FakeUploadService? uploads,
  BackupSettings settings = const BackupSettings(),
  bool cacheChannelId = true,
}) {
  // TdLibClient is a singleton whose methods are never reached here: caching
  // a channel id short-circuits _resolveChannelId before any request. The
  // cacheChannelId: false case deliberately lets resolution fail.
  final channels = StorageChannelService(client: TdLibClient.instance);
  if (cacheChannelId) channels.setCachedChannelId(-100123);

  final engine = BackupEngine(
    galleryRepository: repo ?? _repo(const []),
    uploadService: uploads ?? _FakeUploadService(),
    // uploadDelayMs: 0 — the real 2000ms default would add two seconds of
    // wall-clock per upload to every test in this file.
    settings: settings.copyWith(uploadDelayMs: 0),
    storageChannelService: channels,
  );

  // BackupSettings defaults wifiOnly: true while BackupEnvironment defaults
  // isWifiConnected: false, so without this the scheduler refuses every run
  // and the upload tests would pass vacuously against an untouched queue.
  engine.updateEnvironment(
    const BackupEnvironment(isWifiConnected: true, isCharging: true),
  );
  return engine;
}

_FakeGalleryRepository _repo(List<MediaItem> items) =>
    _FakeGalleryRepository(items);

MediaItem _item(
  String id, {
  MediaStatus status = MediaStatus.pending,
  bool isHidden = false,
  bool isTrashed = false,
  bool isExcluded = false,
}) {
  final now = DateTime.now();
  return MediaItem(
    localId: id,
    fileHash: 'hash_$id',
    filePath: '/media/$id.jpg',
    fileName: '$id.jpg',
    mimeType: 'image/jpeg',
    fileSize: 1024,
    width: 100,
    height: 100,
    createdAt: now,
    modifiedAt: now,
    scannedAt: now,
    status: status,
    isHidden: isHidden,
    isTrashed: isTrashed,
    isExcluded: isExcluded,
  );
}

/// In-memory [GalleryRepository] substitute.
///
/// Subclasses rather than implements so the engine's narrow usage
/// (`totalCount`, `mediaItems`, `markUploaded`, `getTimelineItems`) is
/// overridden without having to stub the whole surface.
class _FakeGalleryRepository extends GalleryRepository {
  _FakeGalleryRepository(List<MediaItem> items)
    : _items = List<MediaItem>.of(items),
      super(scannerService: _NoopScanner());

  final List<MediaItem> _items;

  /// Set to true to simulate the DB write failing after a successful upload.
  bool markUploadedThrows = false;

  /// Invoked at the moment `markUploaded` runs, to observe ordering.
  void Function()? onMarkUploaded;

  @override
  UnmodifiableListView<MediaItem> get mediaItems =>
      UnmodifiableListView(_items);

  @override
  int get totalCount => _items.length;

  @override
  List<MediaItem> getTimelineItems({
    DateTime? startDate,
    DateTime? endDate,
    bool? isFavorite,
    bool? isHidden,
    bool? isArchived,
    bool? isTrashed,
  }) => List<MediaItem>.of(_items);

  @override
  Future<void> markUploaded({
    required String localId,
    String? telegramMessageId,
    String? telegramFileId,
  }) async {
    onMarkUploaded?.call();
    if (markUploadedThrows) throw StateError('db write failed');

    final i = _items.indexWhere((e) => e.localId == localId);
    if (i == -1) return;
    _items[i] = _items[i].copyWith(
      status: MediaStatus.uploaded,
      uploadedAt: DateTime.now(),
      telegramMessageId: telegramMessageId,
      telegramFileId: telegramFileId,
    );
  }
}

class _FakeUploadService implements UploadService {
  final _controller = StreamController<UploadProgress>.broadcast();

  int attempts = 0;

  /// File names passed to [uploadFile], in order — lets a test assert exactly
  /// which items went up, not just how many.
  final List<String> uploadedFileNames = [];

  /// A [TransferError] to throw on every attempt.
  TransferError? error;

  /// A non-TransferError to throw on the first attempt only.
  Object? throwOnFirstCall;

  /// Emit a progress event at this fraction before completing.
  double? emitProgress;

  /// Side effect to run when an upload starts (e.g. pausing the engine).
  void Function(UploadTask task)? onUpload;

  @override
  Stream<UploadProgress> get progressStream => _controller.stream;

  @override
  Future<UploadResult> uploadFile({
    required UploadTask task,
    required int channelId,
    bool includeCaption = true,
  }) async {
    attempts++;
    uploadedFileNames.add(task.fileName);
    onUpload?.call(task);

    final first = throwOnFirstCall;
    if (first != null && attempts == 1) {
      throwOnFirstCall = null;
      throw first;
    }

    final err = error;
    if (err != null) throw err;

    final fraction = emitProgress;
    if (fraction != null) {
      _controller.add(
        UploadProgress(
          taskId: task.id,
          progress: fraction,
          bytesUploaded: (task.fileSize * fraction).round(),
          totalBytes: task.fileSize,
        ),
      );
      await pumpEventQueue();
    }

    return UploadResult(
      taskId: task.id,
      messageId: 1000 + attempts,
      fileId: 2000 + attempts,
    );
  }

  @override
  Future<void> cancelUpload(String taskId) async {}

  @override
  void dispose() => _controller.close();
}

class _NoopScanner implements MediaScannerService {
  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<ScanResult> scanDevice({
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
  }) async => const ScanResult(
    mediaItems: [],
    folders: [],
    totalScanned: 0,
    newItems: 0,
    updatedItems: 0,
    duration: Duration.zero,
  );

  @override
  Future<List<AssetEntity>> listAllAssets({
    void Function(int loaded)? onProgress,
  }) async => const [];

  @override
  Future<Uint8List?> getThumbnail(String assetId) async => null;

  @override
  Future<File?> getFullFile(String assetId) async => null;

  @override
  Future<List<DeviceFolder>> getDeviceFolders() async => const [];
}
