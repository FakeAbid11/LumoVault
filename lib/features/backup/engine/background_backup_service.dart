import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/di/backup_providers.dart';
import '../../../core/di/database_providers.dart';
import '../../../core/di/gallery_providers.dart';
import '../../../core/di/production_providers.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/storage/isolate_run_lock.dart';
import '../../../core/storage/thumbnail_cache.dart';
import '../../metadata/data/repositories/metadata_validator.dart';
import '../../metadata/presentation/providers/metadata_providers.dart';
import '../../people/data/repositories/face_repository.dart';
import '../../people/data/repositories/face_scan_lock.dart';
import '../../people/presentation/providers/people_providers.dart';
import '../../settings/presentation/providers/settings_providers.dart';
import '../data/models/backup_settings.dart';
import 'backup_engine.dart';

/// WorkManager task names.
const String kMediaScannerTask = 'com.lumovault.media_scanner';
const String kUploadWorkerTask = 'com.lumovault.upload_worker';
const String kBackupSchedulerTask = 'com.lumovault.backup_scheduler';
const String kMetadataRepairTask = 'com.lumovault.metadata_repair';
const String kThumbnailRebuildTask = 'com.lumovault.thumbnail_rebuild';
const String kFaceScanTask = 'com.lumovault.face_scanner';

/// Name of the cross-isolate lock guarding the backup path.
const String kBackupRunLockName = 'backup_run';

/// `inputData` keys read by the native worker
/// (`packages/workmanager_android/.../BackgroundWorker.kt`) to promote a
/// long-running task to a `dataSync` Android foreground service via
/// `setForegroundAsync`. Only set on the two long-running backup tasks — the
/// short scanner/maintenance tasks run as ordinary background work.
///
/// The channel/notification identity below is deliberately the same one
/// [NotificationService] uses for backup progress, so the native foreground
/// notification and the Dart progress updates are a single notification, not
/// two.
const String kFgFlagKey = 'lumo_foreground';
const String kFgChannelIdKey = 'lumo_fg_channel_id';
const String kFgNotificationIdKey = 'lumo_fg_notification_id';
const String kFgTitleKey = 'lumo_fg_title';
const String kFgTextKey = 'lumo_fg_text';

/// The notification channel id backup-progress notifications post to. Must
/// match the `backup_progress` channel spec in [NotificationService.channels].
const String kBackupProgressChannelId = 'backup_progress';

/// The `inputData` map that promotes a task to a foreground service. Built once
/// and shared by both long-running task registrations.
final Map<String, dynamic> _foregroundInputData = {
  kFgFlagKey: true,
  kFgChannelIdKey: kBackupProgressChannelId,
  kFgNotificationIdKey: NotificationService.backupProgressNotificationId,
  kFgTitleKey: 'Backing up',
  kFgTextKey: 'Preparing…',
};

/// Same promotion for the face-scan task, with its own notification identity
/// so a running backup and a running face scan never replace each other.
final Map<String, dynamic> _faceScanForegroundInputData = {
  kFgFlagKey: true,
  kFgChannelIdKey: 'face_scan',
  kFgNotificationIdKey: NotificationService.faceScanNotificationId,
  kFgTitleKey: 'Scanning faces',
  kFgTextKey: 'Preparing…',
};

/// Scheduling surface used by [BackgroundBackupSync] and [BackgroundTaskRunner].
///
/// An interface rather than the singleton directly, so the scheduling policy
/// can be tested without a WorkManager host.
abstract class BackupTaskScheduler {
  Future<void> initialize();
  Future<void> registerAllTasks({
    required BackupSettings settings,
    bool promoteScannerToForeground = false,
  });
  Future<void> registerMediaScanner({bool promoteToForeground = false});
  Future<void> registerUploadWorker({bool wifiOnly, bool chargingOnly});
  Future<void> registerBackupScheduler({required BackupSettings settings});
  Future<void> registerMetadataRepair();
  Future<void> registerThumbnailRebuild();
  Future<void> cancelAll();
  Future<void> cancelTask(String taskName);
}

/// Background backup service managing WorkManager tasks.
///
/// Per PRD Section 3.5:
/// - MediaScanner: periodic task every 15 minutes
/// - UploadWorker: one-time task triggered by media scanner
/// - Foreground service for long-running uploads
/// - MetadataRepair: periodic integrity check
/// - ThumbnailRebuild: periodic cache maintenance
class BackgroundBackupService implements BackupTaskScheduler {
  BackgroundBackupService._();

  static final BackgroundBackupService _instance = BackgroundBackupService._();
  static BackgroundBackupService get instance => _instance;

  final Workmanager _workmanager = Workmanager();
  bool _initialized = false;

  /// Initialize WorkManager and register background tasks.
  @override
  Future<void> initialize() async {
    if (_initialized) return;

    await _workmanager.initialize(callbackDispatcher);

    _initialized = true;
    debugPrint('[BackgroundBackupService] Initialized');
  }

  /// Register all background tasks based on settings.
  ///
  /// Auto-backup off means the scan/upload/scheduler trio must not run at all —
  /// registering them anyway would keep backing up in the background after the
  /// user switched it off. Maintenance tasks stay registered regardless.
  ///
  /// [promoteScannerToForeground] promotes the media scanner to a dataSync
  /// foreground service, preventing MIUI/HyperOS from killing it.
  @override
  Future<void> registerAllTasks({
    required BackupSettings settings,
    bool promoteScannerToForeground = false,
  }) async {
    if (!_initialized) await initialize();

    if (settings.isAutoBackupEnabled) {
      await registerMediaScanner(
        promoteToForeground: promoteScannerToForeground,
      );
      await registerUploadWorker(wifiOnly: settings.wifiOnly);
      await registerBackupScheduler(settings: settings);
    } else {
      await cancelTask(kMediaScannerTask);
      await cancelTask(kUploadWorkerTask);
      await cancelTask(kBackupSchedulerTask);
      debugPrint('[BackgroundBackupService] Auto-backup off, backup tasks off');
    }

    await registerFaceScan();
    await registerMetadataRepair();
    await registerThumbnailRebuild();
  }

  /// Register the periodic media scanner task.
  ///
  /// Per PRD: runs every 15 minutes with network constraint.
  /// When [promoteToForeground] is true (MIUI devices), the scanner is
  /// promoted to a dataSync foreground service so MIUI can't kill it.
  @override
  Future<void> registerMediaScanner({bool promoteToForeground = false}) async {
    await _workmanager.registerPeriodicTask(
      kMediaScannerTask,
      kMediaScannerTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      // Without this, re-registering on every launch resets the period and a
      // 15-minute task effectively never fires on a frequently-opened app.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      initialDelay: const Duration(minutes: 1),
      inputData: promoteToForeground ? _foregroundInputData : null,
    );
    debugPrint(
      '[BackgroundBackupService] Registered media scanner'
      '${promoteToForeground ? ' (foreground)' : ''}',
    );
  }

  /// Register the upload worker as a one-time task.
  ///
  /// Per PRD: constraints are Wi-Fi, not low battery.
  @override
  Future<void> registerUploadWorker({
    bool wifiOnly = true,
    bool chargingOnly = false,
  }) async {
    await _workmanager.registerOneOffTask(
      kUploadWorkerTask,
      kUploadWorkerTask,
      constraints: Constraints(
        networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
        requiresBatteryNotLow: true,
        requiresCharging: chargingOnly,
      ),
      // A long-running upload run: promote it to a dataSync foreground service
      // on the native side so it is exempt from the ~10-minute WorkManager cap
      // and Doze (see BackgroundWorker.kt).
      inputData: _foregroundInputData,
      // The scanner enqueues this whenever it finds new media; keeping the
      // already-scheduled run avoids cancelling one that is about to fire.
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      initialDelay: const Duration(seconds: 30),
    );
    debugPrint('[BackgroundBackupService] Registered upload worker');
  }

  /// Register the backup scheduler (combines scan + upload).
  @override
  Future<void> registerBackupScheduler({
    required BackupSettings settings,
  }) async {
    await _workmanager.registerPeriodicTask(
      kBackupSchedulerTask,
      kBackupSchedulerTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: settings.wifiOnly
            ? NetworkType.unmetered
            : NetworkType.connected,
        requiresBatteryNotLow: true,
        requiresCharging: settings.chargingOnly,
      ),
      // The full periodic run can back up a large batch: promote it to a
      // dataSync foreground service on the native side (see BackgroundWorker.kt).
      inputData: _foregroundInputData,
      // Constraints here are derived from user settings, so an existing
      // registration must be replaced when those settings change.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
      initialDelay: const Duration(minutes: 1),
    );
    debugPrint('[BackgroundBackupService] Registered backup scheduler');
  }

  /// Register periodic metadata integrity repair.
  @override
  Future<void> registerMetadataRepair() async {
    await _workmanager.registerPeriodicTask(
      kMetadataRepairTask,
      kMetadataRepairTask,
      frequency: const Duration(hours: 6),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      initialDelay: const Duration(minutes: 30),
    );
    debugPrint('[BackgroundBackupService] Registered metadata repair');
  }

  /// Register periodic thumbnail cache maintenance.
  @override
  Future<void> registerThumbnailRebuild() async {
    await _workmanager.registerPeriodicTask(
      kThumbnailRebuildTask,
      kThumbnailRebuildTask,
      frequency: const Duration(hours: 12),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      initialDelay: const Duration(hours: 1),
    );
    debugPrint('[BackgroundBackupService] Registered thumbnail rebuild');
  }

  /// Register periodic face scanning for new photos.
  ///
  /// Runs every 30 minutes. Only scans photos not yet processed —
  /// already-scanned photos are skipped via the face_scans table.
  /// Promoted to a dataSync foreground service so MIUI/HyperOS cannot freeze
  /// or kill a scan that takes longer than the background execution window.
  Future<void> registerFaceScan() async {
    await _workmanager.registerPeriodicTask(
      kFaceScanTask,
      kFaceScanTask,
      frequency: const Duration(minutes: 30),
      inputData: _faceScanForegroundInputData,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      initialDelay: const Duration(minutes: 5),
    );
    debugPrint('[BackgroundBackupService] Registered face scan');
  }

  /// Register a one-off face scan.
  ///
  /// Used to hand a running in-app scan off to the background when the user
  /// leaves the app (see [FaceScanBackgroundHandoff]): Android freezes the UI
  /// isolate within seconds of backgrounding, so the remaining unscanned
  /// photos must be picked up by a WorkManager run instead. A distinct
  /// unique name from the periodic task so the two can coexist pending —
  /// the face-scan lock makes a double run harmless.
  Future<void> registerFaceScanOneOff() async {
    if (!_initialized) await initialize();
    await _workmanager.registerOneOffTask(
      '$kFaceScanTask.once',
      kFaceScanTask,
      inputData: _faceScanForegroundInputData,
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      initialDelay: const Duration(seconds: 10),
    );
    debugPrint('[BackgroundBackupService] Registered one-off face scan');
  }

  /// Cancel all registered background tasks.
  @override
  Future<void> cancelAll() async {
    await _workmanager.cancelAll();
    debugPrint('[BackgroundBackupService] Cancelled all tasks');
  }

  /// Cancel a specific task.
  @override
  Future<void> cancelTask(String taskName) async {
    await _workmanager.cancelByUniqueName(taskName);
    debugPrint('[BackgroundBackupService] Cancelled task: $taskName');
  }

  /// Check if WorkManager is initialized.
  bool get isInitialized => _initialized;
}

/// WorkManager callback dispatcher.
///
/// This runs in a **separate isolate** when WorkManager triggers a task, so
/// nothing from the UI isolate is reachable: every task builds its own
/// [ProviderContainer] via [BackgroundTaskRunner] and tears it down again.
@pragma('vm:entry-point')
void callbackDispatcher() {
  // The background isolate is a fresh VM: install the log gate here too so
  // tagged logs honor Debug Mode before any task settings are read.
  AppLogger.install();
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[BackgroundBackup] Executing task: $task');
    return BackgroundTaskRunner().run(task);
  });
}

/// Executes a single WorkManager task in the background isolate.
///
/// Split out from [callbackDispatcher] so the logic is reachable from tests —
/// the dispatcher itself can only run under a real WorkManager host.
class BackgroundTaskRunner {
  BackgroundTaskRunner({
    ProviderContainer Function()? containerFactory,
    IsolateRunLock? runLock,
  }) : _containerFactory = containerFactory ?? ProviderContainer.new,
       _runLock = runLock ?? IsolateRunLock(name: kBackupRunLockName);

  final ProviderContainer Function() _containerFactory;
  final IsolateRunLock _runLock;

  /// Overrides the face-scan lock for tests. Lazily created in production so
  /// the lock file is only touched when a face task actually runs.
  IsolateRunLock? _faceScanLockOverride;

  /// Test-only seam: force the face-scan lock used by [run].
  // ignore: avoid_setters_without_getters
  set faceScanLockForTesting(IsolateRunLock lock) =>
      _faceScanLockOverride = lock;

  IsolateRunLock get _faceScanLock =>
      _faceScanLockOverride ?? IsolateRunLock(name: kFaceScanLockName);

  /// Dispatch [task]. Returns false to tell WorkManager to retry per the
  /// task's backoff policy.
  Future<bool> run(String task) async {
    switch (task) {
      case kMediaScannerTask:
        return _guard(task, _handleMediaScanner);
      case kUploadWorkerTask:
        return _guard(task, _handleUploadWorker);
      case kBackupSchedulerTask:
        return _guard(task, _handleBackupScheduler);
      case kMetadataRepairTask:
        return _guard(task, _handleMetadataRepair);
      case kThumbnailRebuildTask:
        return _guard(task, _handleThumbnailRebuild);
      case kFaceScanTask:
        return _guard(task, _handleFaceScan);
      default:
        debugPrint('[BackgroundBackup] Unknown task: $task');
        // An unknown name is a code bug, not a transient failure — retrying
        // would just burn battery forever, so report success and drop it.
        return true;
    }
  }

  /// Scan for new media and, if anything turned up, ask for an upload run.
  Future<bool> _handleMediaScanner() async {
    return _withContainer((container) async {
      final settings = container.read(backupSettingsProvider);
      if (!settings.isAutoBackupEnabled) {
        debugPrint('[BackgroundBackup] Auto-backup disabled, skipping scan');
        return true;
      }

      final engine = container.read(backupEngineProvider.notifier);
      await container.read(galleryRepositoryProvider).hydrate();
      await engine.scanAndEnqueue();

      final pending = engine.stats.pendingCount;
      debugPrint('[BackgroundBackup] Scan found $pending pending item(s)');

      if (pending > 0) {
        await BackgroundBackupService.instance.registerUploadWorker(
          wifiOnly: settings.wifiOnly,
          chargingOnly: settings.chargingOnly,
        );
      }
      return true;
    });
  }

  /// Upload whatever is already queued, without scanning first.
  Future<bool> _handleUploadWorker() {
    return _withBackupLock((container) => _runBackup(container, scan: false));
  }

  /// The full periodic run: scan, then upload.
  Future<bool> _handleBackupScheduler() {
    return _withBackupLock((container) => _runBackup(container, scan: true));
  }

  /// Validate metadata and apply the fixes that are safe to automate.
  Future<bool> _handleMetadataRepair() async {
    return _withContainer((container) async {
      final gallery = container.read(galleryRepositoryProvider);
      await gallery.hydrate();

      final validator = MetadataValidator(
        mediaItems: gallery.getTimelineItems(),
        searchTerms: const [],
      );
      final result = await validator.validate();
      final fixed = await validator.autoFix(result.issues);

      debugPrint(
        '[BackgroundBackup] Metadata repair: ${result.issues.length} '
        'issue(s), $fixed fixed',
      );
      return true;
    });
  }

  /// Trim the thumbnail cache back under its size budget.
  Future<bool> _handleThumbnailRebuild() async {
    final cache = ThumbnailCache.instance;
    await cache.initialize();
    await cache.evictIfOverSize();
    debugPrint(
      '[BackgroundBackup] Thumbnail cache now '
      '${await cache.getDiskCacheCount()} entr(ies)',
    );
    return true;
  }

  /// Scan new device photos for faces and cluster them into people.
  ///
  /// Only processes photos not yet in the face_scans table — the incremental
  /// scan naturally skips already-scanned ones.
  ///
  /// Runs under the face-scan foreground service (native promotion via
  /// [_faceScanForegroundInputData]): on MIUI/HyperOS an unpromoted background
  /// task is frozen or killed within seconds, which is exactly the
  /// "people grouping never runs in the background" report. Progress goes to
  /// the face_scan notification, clustering refreshes per batch, and the
  /// cross-isolate [kFaceScanLockName] lock keeps this from racing the
  /// in-app scan. A failure returns false so WorkManager retries on its
  /// backoff policy instead of silently dropping the backlog.
  Future<bool> _handleFaceScan() async {
    final faceLock = _faceScanLock;
    if (!await faceLock.tryAcquire()) {
      debugPrint(
        '[BackgroundBackup] Face scan skipped: another isolate is scanning',
      );
      return true;
    }
    try {
      return await _withContainer((container) async {
        final faceDao = container.read(appDatabaseProvider).faceDao;
        final faceDetectionService = container.read(
          faceDetectionServiceProvider,
        );
        final faceClusteringService = container.read(
          faceClusteringServiceProvider,
        );
        final repository = FaceRepository(
          faceDao: faceDao,
          faceDetectionService: faceDetectionService,
          faceClusteringService: faceClusteringService,
        );

        // Wait for face detection models to initialize.
        await faceDetectionService.ensureInitialized();

        final scannerService = container.read(mediaScannerServiceProvider);
        final assets = await scannerService.listAllAssets();
        if (assets.isEmpty) return true;

        final scannedIds = await faceDao.scannedMediaItemIds();
        final toScan = assets.where((a) => !scannedIds.contains(a.id)).toList();
        if (toScan.isEmpty) {
          debugPrint('[BackgroundBackup] Face scan: nothing new to scan');
          return true;
        }

        final notifications = container.read(notificationServiceProvider);
        await notifications.initialize();

        debugPrint('[BackgroundBackup] Face scan: ${toScan.length} new photos');
        await ForegroundServiceManager.startService(
          notifications: notifications,
          title: 'Scanning faces',
          body: 'Preparing…',
          notificationId: NotificationService.faceScanNotificationId,
        );

        var facesFound = 0;
        try {
          final perPhoto = await repository.scanMediaItems(
            toScan,
            onProgress: (current, total) {
              if (current % 10 != 0 && current != total) return;
              unawaited(
                ForegroundServiceManager.updateNotification(
                  notifications: notifications,
                  title: 'Scanning faces',
                  body: '$current of $total photos',
                  progress: current,
                  maxProgress: total,
                  notificationId: NotificationService.faceScanNotificationId,
                ),
              );
              unawaited(faceLock.heartbeat());
            },
            // Runs every FaceRepository.scanBatchSize (50) photos: cluster
            // what has been found so far so people appear progressively.
            onBatchComplete: () => repository.clusterFaces(),
          );
          for (final count in perPhoto.values) {
            facesFound += count;
          }
          await repository.clusterFaces();
        } finally {
          await ForegroundServiceManager.stopService(
            notificationId: NotificationService.faceScanNotificationId,
          );
        }

        debugPrint(
          '[BackgroundBackup] Face scan complete: $facesFound face(s)',
        );
        // Not a task failure — the scan itself succeeded; per-photo errors are
        // already recorded so they are not retried forever.
        if (facesFound > 0) {
          await notifications.showFaceScanCompleted(
            photosScanned: toScan.length,
            facesFound: facesFound,
          );
        }
        return true;
      });
    } catch (e, stackTrace) {
      debugPrint('[BackgroundBackup] Face scan failed: $e');
      debugPrint('$stackTrace');
      // Retryable: an init/OOM/transient failure should not silently drop the
      // remaining backlog — WorkManager reruns the task on its backoff.
      return false;
    } finally {
      await faceLock.release();
    }
  }

  /// Drive the engine, reporting progress and the outcome via notifications.
  Future<bool> _runBackup(
    ProviderContainer container, {
    required bool scan,
  }) async {
    final settings = container.read(backupSettingsProvider);
    if (!settings.isAutoBackupEnabled) {
      debugPrint('[BackgroundBackup] Auto-backup disabled, skipping backup');
      return true;
    }

    final notifications = container.read(notificationServiceProvider);
    await notifications.initialize();

    final engine = container.read(backupEngineProvider.notifier).engine;

    StreamSubscription<BackupStats>? progress;
    try {
      // Hydrate before ANY run, not only scanning ones. The upload-worker
      // path (scan: false) uploads from the persisted queue, and without
      // hydration `markUploaded` silently no-ops against this isolate's
      // empty in-memory model: the drift row stays `pending`, the metadata
      // layer never learns of the upload, and the next scan re-enqueues and
      // re-uploads the same file into the channel.
      await container.read(galleryRepositoryProvider).hydrate();

      // WorkManager already enforced the network/battery constraints before
      // this task was allowed to run, but this isolate's fresh environment
      // still holds the `isWifiConnected: false` default until its
      // fire-and-forget connectivity seed resolves — startBackup() would
      // then refuse a perfectly valid run ("Waiting for Wi-Fi connection.").
      // Seed synchronously so the scheduler re-check sees reality.
      await container
          .read(backupEnvironmentProvider.notifier)
          .seedFromPlatform();

      if (scan) {
        await engine.scanAndEnqueue();
      }

      if (engine.stats.pendingCount == 0) {
        debugPrint('[BackgroundBackup] Nothing queued, finishing');
        return true;
      }

      await ForegroundServiceManager.startService(
        notifications: notifications,
        title: 'Backing up',
        body: 'Preparing…',
      );

      var lastCompleted = -1;
      progress = engine.statsStream.listen((stats) {
        // statsStream fires on every byte of progress; only re-post when the
        // completed count actually moves, or the notification thrashes.
        if (stats.backedUpCount == lastCompleted) return;
        lastCompleted = stats.backedUpCount;
        unawaited(
          ForegroundServiceManager.updateNotification(
            notifications: notifications,
            title: 'Backing up',
            body: 'Uploading…',
            progress: stats.backedUpCount,
            maxProgress: stats.queueTotal,
          ),
        );
        unawaited(_runLock.heartbeat());
      });

      await engine.startBackup();

      // Push dirty metadata partitions and the manifest to the channel. This
      // isolate has no metadata sync listener (the coordinator is only read at
      // bootstrap in the UI isolate), so the end-of-run sync is what keeps the
      // channel's metadata files in step with what was just uploaded.
      try {
        await container.read(metadataSyncCoordinatorProvider).syncNow();
        // The coordinator's partition/manifest stores persist on a debounce;
        // flush them now so a tear-down right after this run can't lose them.
        await container.read(partitionServiceProvider).saveNow();
        await container.read(manifestServiceProvider).saveNow();
      } catch (e, stackTrace) {
        debugPrint('[BackgroundBackup] Metadata sync failed: $e');
        debugPrint('$stackTrace');
      }

      final stats = engine.stats;
      await ForegroundServiceManager.stopService();

      if (stats.failedCount > 0) {
        await notifications.showBackupFailed(
          reason: 'Some items could not be uploaded. They will be retried.',
          failedCount: stats.failedCount,
        );
        // Not a task failure: the engine already tracks per-item retries, and
        // returning false would re-run the whole batch on WorkManager's
        // backoff on top of that.
        return true;
      }

      if (stats.backedUpCount > 0) {
        await notifications.showBackupCompleted(
          totalFiles: stats.backedUpCount,
          totalBytes: stats.backedUpBytes,
        );
      }
      return true;
    } finally {
      await progress?.cancel();
      await ForegroundServiceManager.stopService();
      // NOT engine.dispose(). The engine belongs to the container — it came
      // from container.read(backupEngineProvider.notifier), and
      // _withContainer's own finally disposes the container, which disposes
      // BackupEngineNotifier, which disposes this same engine. Disposing it
      // here made that a double-dispose, and worse, it cleared the in-memory
      // queue while the container still held a live reference: any
      // _updateStats() reaching the engine after this point would both throw
      // on the closed stats controller and persist an EMPTY queue over the
      // real one, discarding every still-pending upload.
    }
  }

  /// Run [body] with a fresh container, holding the cross-isolate backup lock.
  Future<bool> _withBackupLock(
    Future<bool> Function(ProviderContainer container) body,
  ) async {
    if (!await _runLock.tryAcquire()) {
      debugPrint('[BackgroundBackup] Backup already running elsewhere');
      // Another isolate owns the run. Reporting success avoids stacking
      // retries behind work that is already in flight.
      return true;
    }
    try {
      return await _guard('backup', () => _withContainer(body));
    } finally {
      await _runLock.release();
    }
  }

  Future<bool> _withContainer(
    Future<bool> Function(ProviderContainer container) body,
  ) async {
    final container = _containerFactory();
    try {
      // Honor the persisted Debug Mode toggle on the background isolate too,
      // which has its own memory space and never ran the UI settings notifier.
      final settings = await container
          .read(settingsRepositoryProvider)
          .getSettings();
      AppLogger.verboseEnabled = settings.debugMode;
      return await body(container);
    } finally {
      container.dispose();
    }
  }

  /// A thrown task must never crash the background isolate; returning false
  /// lets WorkManager retry on the task's backoff policy instead.
  Future<bool> _guard(String label, Future<bool> Function() body) async {
    try {
      return await body();
    } catch (e, stackTrace) {
      debugPrint('[BackgroundBackup] Task $label failed: $e');
      debugPrint('$stackTrace');
      return false;
    }
  }
}

/// Manages the ongoing progress notification for a running backup.
///
/// The actual Android foreground service is started on the **native** side:
/// the two long-running tasks ([kUploadWorkerTask], [kBackupSchedulerTask]) are
/// registered with [_foregroundInputData], and the vendored worker
/// (`packages/workmanager_android/.../BackgroundWorker.kt`) calls
/// `setForegroundAsync(ForegroundInfo(..., FOREGROUND_SERVICE_TYPE_DATA_SYNC))`
/// before running the Dart task. That promotion is what exempts the run from
/// the ~10-minute WorkManager execution limit and from Doze/App Standby.
///
/// This class owns the notification *content*: the native side posts the
/// initial ongoing notification (id [NotificationService.backupProgressNotificationId],
/// channel `backup_progress`), and the methods here update that **same**
/// notification with live progress — so there is exactly one notification, not
/// two. If the native promotion fails (it is non-fatal and logged), the run
/// still proceeds under the standard background limits and this notification
/// still shows progress.
class ForegroundServiceManager {
  static final Set<int> _runningIds = {};

  static final Map<int, NotificationService> _notificationsById = {};

  /// Whether a foreground-service notification for [notificationId] is up.
  static bool isRunningFor(int notificationId) =>
      _runningIds.contains(notificationId);

  /// Start the foreground service with a progress notification.
  static Future<void> startService({
    required NotificationService notifications,
    required String title,
    required String body,
    int? progress,
    int? maxProgress,
    int notificationId = NotificationService.backupProgressNotificationId,
  }) async {
    _notificationsById[notificationId] = notifications;

    if (isRunningFor(notificationId)) {
      await updateNotification(
        notifications: notifications,
        title: title,
        body: body,
        progress: progress,
        maxProgress: maxProgress,
        notificationId: notificationId,
      );
      return;
    }

    _runningIds.add(notificationId);
    debugPrint('[ForegroundService] Started: $title - $body');
    await updateNotification(
      notifications: notifications,
      title: title,
      body: body,
      progress: progress,
      maxProgress: maxProgress,
      notificationId: notificationId,
    );
  }

  /// Update the foreground service notification.
  static Future<void> updateNotification({
    required NotificationService notifications,
    required String title,
    required String body,
    int? progress,
    int? maxProgress,
    int notificationId = NotificationService.backupProgressNotificationId,
  }) async {
    if (!isRunningFor(notificationId)) return;
    await notifications.showProgressNotification(
      notificationId: notificationId,
      title: title,
      body: body,
      current: progress ?? 0,
      total: maxProgress ?? 0,
    );
  }

  /// Stop the foreground service and clear its notification.
  static Future<void> stopService({
    int notificationId = NotificationService.backupProgressNotificationId,
  }) async {
    if (!_runningIds.remove(notificationId)) return;
    await _notificationsById.remove(notificationId)?.cancel(notificationId);
    debugPrint('[ForegroundService] Stopped');
  }
}
