import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/di/backup_providers.dart';
import '../../../core/di/gallery_providers.dart';
import '../../../core/di/production_providers.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/storage/isolate_run_lock.dart';
import '../../../core/storage/thumbnail_cache.dart';
import '../../metadata/data/repositories/metadata_validator.dart';
import '../../metadata/presentation/providers/metadata_providers.dart';
import '../data/models/backup_settings.dart';
import 'backup_engine.dart';

/// WorkManager task names.
const String kMediaScannerTask = 'com.lumovault.media_scanner';
const String kUploadWorkerTask = 'com.lumovault.upload_worker';
const String kBackupSchedulerTask = 'com.lumovault.backup_scheduler';
const String kMetadataRepairTask = 'com.lumovault.metadata_repair';
const String kThumbnailRebuildTask = 'com.lumovault.thumbnail_rebuild';

/// Name of the cross-isolate lock guarding the backup path.
const String kBackupRunLockName = 'backup_run';

/// Scheduling surface used by [BackgroundBackupSync] and [BackgroundTaskRunner].
///
/// An interface rather than the singleton directly, so the scheduling policy
/// can be tested without a WorkManager host.
abstract class BackupTaskScheduler {
  Future<void> initialize();
  Future<void> registerAllTasks({required BackupSettings settings});
  Future<void> registerMediaScanner();
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
  @override
  Future<void> registerAllTasks({required BackupSettings settings}) async {
    if (!_initialized) await initialize();

    if (settings.isAutoBackupEnabled) {
      await registerMediaScanner();
      await registerUploadWorker(wifiOnly: settings.wifiOnly);
      await registerBackupScheduler(settings: settings);
    } else {
      await cancelTask(kMediaScannerTask);
      await cancelTask(kUploadWorkerTask);
      await cancelTask(kBackupSchedulerTask);
      debugPrint('[BackgroundBackupService] Auto-backup off, backup tasks off');
    }

    await registerMetadataRepair();
    await registerThumbnailRebuild();
  }

  /// Register the periodic media scanner task.
  ///
  /// Per PRD: runs every 15 minutes with network constraint.
  @override
  Future<void> registerMediaScanner() async {
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
    );
    debugPrint('[BackgroundBackupService] Registered media scanner');
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
      if (scan) {
        await container.read(galleryRepositoryProvider).hydrate();
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

/// Progress-notification manager for long-running uploads.
///
/// Per PRD Section 3.5, shows a notification during active uploads.
///
/// IMPORTANT — this is NOT an Android foreground service, despite the name.
/// It only posts an ordinary progress notification via [NotificationService].
/// Promoting the WorkManager job to a foreground service requires the worker
/// to call `setForegroundAsync(ForegroundInfo(...))` on the native side, and
/// that call appears nowhere in `packages/workmanager_android` — so the job
/// gets no extra runtime and is still subject to the standard ~10-minute
/// WorkManager execution limit and to Doze/App Standby.
///
/// Consequence: a large first backup can be killed mid-run on a long batch.
/// The queue is persisted ([TransferQueuePersistence]) so work resumes on the
/// next run rather than being lost, but the run itself is not protected.
/// Fixing this properly means patching the vendored worker to call
/// `setForegroundAsync` with a `dataSync` foreground service type, which
/// needs an Android SDK and on-device verification.
class ForegroundServiceManager {
  static bool _running = false;

  /// Whether the foreground service is currently running.
  static bool get isRunning => _running;

  static NotificationService? _notifications;

  /// Start the foreground service with a progress notification.
  static Future<void> startService({
    required NotificationService notifications,
    required String title,
    required String body,
    int? progress,
    int? maxProgress,
  }) async {
    _notifications = notifications;

    if (_running) {
      await updateNotification(
        notifications: notifications,
        title: title,
        body: body,
        progress: progress,
        maxProgress: maxProgress,
      );
      return;
    }

    _running = true;
    debugPrint('[ForegroundService] Started: $title - $body');
    await updateNotification(
      notifications: notifications,
      title: title,
      body: body,
      progress: progress,
      maxProgress: maxProgress,
    );
  }

  /// Update the foreground service notification.
  static Future<void> updateNotification({
    required NotificationService notifications,
    required String title,
    required String body,
    int? progress,
    int? maxProgress,
  }) async {
    if (!_running) return;
    await notifications.showBackupProgress(
      current: progress ?? 0,
      total: maxProgress ?? 0,
      fileName: body,
    );
  }

  /// Stop the foreground service and clear its notification.
  static Future<void> stopService() async {
    if (!_running) return;
    _running = false;
    await _notifications?.cancel(
      NotificationService.backupProgressNotificationId,
    );
    _notifications = null;
    debugPrint('[ForegroundService] Stopped');
  }
}
