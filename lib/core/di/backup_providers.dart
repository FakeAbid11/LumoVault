import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../features/backup/data/models/backup_settings.dart';
import '../../features/backup/engine/background_backup_service.dart';
import '../../features/backup/engine/backup_engine.dart';
import '../../features/backup/engine/backup_scheduler.dart';
import '../../features/gallery/data/models/media_item.dart';
import '../../features/gallery/data/models/upload_task.dart';
import '../../features/gallery/data/repositories/gallery_repository.dart';
import '../../features/gallery/data/repositories/telegram_upload_service.dart';
import '../../features/settings/data/models/app_settings.dart';
import '../../features/settings/presentation/providers/settings_providers.dart';
import '../storage/storage_channel_service.dart';
import '../storage/transfer_queue_persistence.dart';
import 'gallery_providers.dart';
import 'production_providers.dart';
import 'providers.dart';
import 'tdlib_providers.dart';
import 'transfer_providers.dart';

/// Backup settings state provider.
///
/// Backed by the persisted [AppSettings] (via [appSettingsProvider]) so that
/// backup preferences — folder exclusions, wifi-only, batch size, etc. —
/// survive cold starts. This replaces the previous in-memory-only state.
final backupSettingsProvider =
    StateNotifierProvider<BackupSettingsNotifier, BackupSettings>((ref) {
      return BackupSettingsNotifier(ref);
    });

class BackupSettingsNotifier extends StateNotifier<BackupSettings> {
  BackupSettingsNotifier(this._ref) : super(const BackupSettings()) {
    // Seed from the persisted app settings, then keep this notifier's state
    // in sync whenever app settings change (including external edits).
    _syncFromAppSettings(_ref.read(appSettingsProvider));
    _subscription = _ref.listen<AppSettings>(appSettingsProvider, (
      AppSettings? _,
      AppSettings next,
    ) {
      _syncFromAppSettings(next);
    });
  }

  final Ref _ref;
  ProviderSubscription<AppSettings>? _subscription;

  void _syncFromAppSettings(AppSettings s) {
    state = BackupSettings(
      isAutoBackupEnabled: s.autoBackupEnabled,
      wifiOnly: s.wifiOnly,
      chargingOnly: s.chargingOnly,
      maxFileSize: s.maxFileSizeBytes > 0 ? s.maxFileSizeBytes : null,
      backupPhotos: s.backupPhotos,
      backupVideos: s.backupVideos,
      includedFolders: s.includedFolders,
      excludedFolders: s.excludedFolders,
      excludedFileHashes: s.excludedFileHashes,
      uploadBatchSize: s.uploadBatchSize,
      uploadDelayMs: s.uploadDelayMs,
      lastBackupAt: s.lastBackupAt,
      lastScanAt: s.lastScanAt,
    );
  }

  /// Apply a durable preference change by writing it through to the persisted
  /// [AppSettings]. The [appSettingsProvider] listener then re-syncs this
  /// notifier's state, so there is a single write path.
  Future<void> _updateAppSettings(
    AppSettings Function(AppSettings current) updater,
  ) async {
    await _ref.read(appSettingsProvider.notifier).updateField(updater);
  }

  void updateAutoBackup(bool enabled) {
    _updateAppSettings((s) => s.copyWith(autoBackupEnabled: enabled));
  }

  void updateWifiOnly(bool enabled) {
    _updateAppSettings((s) => s.copyWith(wifiOnly: enabled));
  }

  void updateChargingOnly(bool enabled) {
    _updateAppSettings((s) => s.copyWith(chargingOnly: enabled));
  }

  void updateBackupPhotos(bool enabled) {
    _updateAppSettings((s) => s.copyWith(backupPhotos: enabled));
  }

  void updateBackupVideos(bool enabled) {
    _updateAppSettings((s) => s.copyWith(backupVideos: enabled));
  }

  void updateMaxFileSize(int? maxFileSize) {
    _updateAppSettings((s) => s.copyWith(maxFileSizeBytes: maxFileSize ?? 0));
  }

  void updateIncludedFolders(List<String> folders) {
    _updateAppSettings((s) => s.copyWith(includedFolders: folders));
  }

  void updateExcludedFolders(List<String> folders) {
    _updateAppSettings((s) => s.copyWith(excludedFolders: folders));
  }

  void updateExcludedFileHashes(List<String> hashes) {
    _updateAppSettings((s) => s.copyWith(excludedFileHashes: hashes));
  }

  void updateUploadBatchSize(int batchSize) {
    _updateAppSettings((s) => s.copyWith(uploadBatchSize: batchSize));
  }

  void updateUploadDelayMs(int delayMs) {
    _updateAppSettings((s) => s.copyWith(uploadDelayMs: delayMs));
  }

  void toggleFolderExclusion(String folderPath) {
    _updateAppSettings((s) {
      final excluded = List<String>.of(s.excludedFolders);
      if (excluded.contains(folderPath)) {
        excluded.remove(folderPath);
      } else {
        excluded.add(folderPath);
      }
      return s.copyWith(excludedFolders: excluded);
    });
  }

  void toggleFileExclusion(String fileHash) {
    _updateAppSettings((s) {
      final excluded = List<String>.of(s.excludedFileHashes);
      if (excluded.contains(fileHash)) {
        excluded.remove(fileHash);
      } else {
        excluded.add(fileHash);
      }
      return s.copyWith(excludedFileHashes: excluded);
    });
  }

  void updateLastBackupAt(DateTime? timestamp) {
    _updateAppSettings((s) => s.copyWith(lastBackupAt: timestamp));
  }

  void updateLastScanAt(DateTime? timestamp) {
    _updateAppSettings((s) => s.copyWith(lastScanAt: timestamp));
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }
}

/// Backup environment provider (connectivity, battery).
final backupEnvironmentProvider =
    StateNotifierProvider<BackupEnvironmentNotifier, BackupEnvironment>((ref) {
      return BackupEnvironmentNotifier();
    });

/// Pulls a one-shot connectivity snapshot. Injectable so tests can drive
/// [BackupEnvironmentNotifier.seedFromPlatform] without platform channels.
typedef ConnectivityChecker = Future<List<ConnectivityResult>> Function();

/// Streams connectivity changes.
typedef ConnectivityStreamSource = Stream<List<ConnectivityResult>> Function();

/// Pulls the current battery level percentage.
typedef BatteryLevelReader = Future<int> Function();

/// Streams battery state changes (plug/unplug).
typedef BatteryStateStreamSource = Stream<BatteryState> Function();

class BackupEnvironmentNotifier extends StateNotifier<BackupEnvironment> {
  BackupEnvironmentNotifier({
    ConnectivityChecker? checkConnectivity,
    ConnectivityStreamSource? connectivityStream,
    BatteryLevelReader? batteryLevelReader,
    BatteryStateStreamSource? batteryStateStream,
  }) : _checkConnectivity =
           checkConnectivity ?? (() => Connectivity().checkConnectivity()),
       _connectivityStream =
           connectivityStream ?? (() => Connectivity().onConnectivityChanged),
       _batteryLevelReader =
           batteryLevelReader ?? (() => Battery().batteryLevel),
       _batteryStateStream =
           batteryStateStream ?? (() => Battery().onBatteryStateChanged),
       super(const BackupEnvironment()) {
    _initConnectivityListener();
    _initBatteryListener();
  }

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<BatteryState>? _batterySubscription;
  Timer? _batteryLevelTimer;

  final ConnectivityChecker _checkConnectivity;
  final ConnectivityStreamSource _connectivityStream;
  final BatteryLevelReader _batteryLevelReader;
  final BatteryStateStreamSource _batteryStateStream;

  void _initConnectivityListener() {
    _connectivitySubscription = _connectivityStream().listen(
      _applyConnectivity,
    );
    // Seed the *current* connectivity immediately. onConnectivityChanged only
    // fires on a change, so without this initial read isWifiConnected stayed at
    // its false default until the network toggled — and with wifiOnly on (the
    // default), BackupScheduler.evaluate() then refused to start a backup even
    // on live Wi-Fi ("Waiting for Wi-Fi connection."). Mirrors how
    // _initBatteryListener seeds the battery level below.
    unawaited(seedFromPlatform());
  }

  /// Pulls the current connectivity and battery state into [state], awaited.
  ///
  /// The constructor seeds both fire-and-forget, which is fine for the UI
  /// isolate — but each background WorkManager task builds a fresh container
  /// and can reach `BackupScheduler.evaluate` before that async seed lands,
  /// reading the `isWifiConnected: false` default and refusing a run the OS
  /// had already cleared (the task only fired because WorkManager's own
  /// network constraint passed). Background tasks await this instead.
  Future<void> seedFromPlatform() async {
    try {
      final results = await _checkConnectivity();
      _applyConnectivity(results);
    } catch (e) {
      debugPrint('[BackupEnvironment] Connectivity seed failed: $e');
    }
    await _refreshBatteryLevel();
  }

  void _applyConnectivity(List<ConnectivityResult> results) {
    final hasWifi = results.any((r) => r == ConnectivityResult.wifi);
    state = BackupEnvironment(
      isWifiConnected: hasWifi,
      isCharging: state.isCharging,
      batteryLevel: state.batteryLevel,
      isAutoBackupEnabled: state.isAutoBackupEnabled,
    );
  }

  /// Wire charging state and battery level into the environment.
  ///
  /// [BackupScheduler] gates on both ([BackupScheduler._minBatteryLevel] and
  /// the `chargingOnly` setting), but nothing ever fed them a real source:
  /// `isCharging` stayed false forever and the level stuck at the 100%
  /// default, so the charging gate silently never held back a backup. The
  /// plugin's state stream only fires on plug/unplug, and there is no level
  /// stream on Android — so the level is read once and re-polled in the
  /// background (the scheduler runs on minute-ish cadence anyway).
  void _initBatteryListener() {
    try {
      _batterySubscription = _batteryStateStream().listen(
        (batteryState) => updateCharging(_isPluggedIn(batteryState)),
      );
    } catch (e) {
      debugPrint('[BackupEnvironment] Battery state stream unavailable: $e');
    }

    unawaited(_refreshBatteryLevel());
    _batteryLevelTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(_refreshBatteryLevel()),
    );
  }

  Future<void> _refreshBatteryLevel() async {
    try {
      final level = await _batteryLevelReader();
      // Some devices report -1 while the level is unknown; anything outside
      // 0-100 is garbage and would trip the scheduler's low-battery gate.
      if (level < 0 || level > 100) return;
      updateBatteryLevel(level);
    } catch (e) {
      // Unsupported platform (desktop/web) or plugin not available (tests).
      debugPrint('[BackupEnvironment] Battery level read failed: $e');
    }
  }

  /// Whether the device is on external power.
  ///
  /// [BatteryState.connectedNotCharging] (e.g. a charge limit reached, or an
  /// underpowered source) still counts as "charging" for the scheduler's
  /// `chargingOnly` gate — the battery isn't draining, which is all the gate
  /// is protecting against.
  bool _isPluggedIn(BatteryState state) {
    return state == BatteryState.charging ||
        state == BatteryState.full ||
        state == BatteryState.connectedNotCharging;
  }

  void updateCharging(bool isCharging) {
    state = BackupEnvironment(
      isWifiConnected: state.isWifiConnected,
      isCharging: isCharging,
      batteryLevel: state.batteryLevel,
      isAutoBackupEnabled: state.isAutoBackupEnabled,
    );
  }

  void updateBatteryLevel(int level) {
    state = BackupEnvironment(
      isWifiConnected: state.isWifiConnected,
      isCharging: state.isCharging,
      batteryLevel: level,
      isAutoBackupEnabled: state.isAutoBackupEnabled,
    );
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _batterySubscription?.cancel();
    _batteryLevelTimer?.cancel();
    super.dispose();
  }
}

/// Backup engine provider.
final backupEngineProvider =
    StateNotifierProvider<BackupEngineNotifier, BackupEngineState>((ref) {
      // Deliberately ref.read, not ref.watch, for all of these. This
      // builder only needs to run ONCE — it constructs a BackupEngine
      // holding a live, in-memory upload queue that gets populated by
      // scanAndEnqueue(). The ref.listen calls below already propagate
      // ongoing settings/environment changes into that SAME engine
      // instance via updateSettings()/updateEnvironment(), non-
      // destructively. Watching here instead meant every connectivity
      // change (backupEnvironmentProvider reacts to
      // Connectivity().onConnectivityChanged, which fires often) tore
      // down this whole provider and rebuilt a fresh BackupEngineNotifier
      // — with a brand new, EMPTY queue — silently discarding whatever
      // had just been enqueued. That's why the dashboard could show "0
      // pending" moments after tapping Start Backup: the queue that had
      // real items in it had already been thrown away and replaced.
      final galleryRepository = ref.read(galleryRepositoryProvider);
      final uploadService = ref.read(uploadServiceProvider);
      final settings = ref.read(backupSettingsProvider);
      final environment = ref.read(backupEnvironmentProvider);
      final storageChannelService = ref.read(storageChannelServiceProvider);
      final persistedChannelId = ref.read(appSettingsProvider).storageChannelId;
      final queuePersistence = ref.read(transferQueuePersistenceProvider);

      final notifier = BackupEngineNotifier(
        galleryRepository: galleryRepository,
        uploadService: uploadService,
        settings: settings,
        environment: environment,
        storageChannelService: storageChannelService,
        persistedChannelId: persistedChannelId,
        queuePersistence: queuePersistence,
        onChannelResolved: (channelId) {
          ref.read(appSettingsProvider.notifier).setStorageChannelId(channelId);
        },
        // Persist the last backup/scan timestamps through AppSettings so the
        // dashboard's "last backup" survives an app restart. The
        // appSettingsProvider listener below then re-syncs backupSettings.
        onBackupTimestampsChanged: (lastBackupAt, lastScanAt) {
          ref
              .read(appSettingsProvider.notifier)
              .updateField(
                (s) => s.copyWith(
                  lastBackupAt: lastBackupAt,
                  lastScanAt: lastScanAt,
                ),
              );
        },
        // TdLibClient.initialize() (awaited by tdLibInitializedProvider)
        // returns as soon as the receive loop starts — it does not wait for
        // TDLib to finish validating/restoring the persisted session. Right
        // after a cold connect, authorization is still in the transient
        // authorizationStateWaitTdlibParameters state, so getChats/loadChats
        // during channel search comes back with zero chats (not an error —
        // genuinely not synced yet), the search always finds nothing, and a
        // brand new channel gets created every single launch. authService
        // .initialize() already waits for the state to settle past that
        // transient point (see its docstring) — reuse it instead of
        // duplicating that race-handling logic here.
        ensureTdLibConnected: () async {
          await ref.read(tdLibInitializedProvider.future);
          await ref.read(authServiceProvider).initialize();
        },
        seedEnvironment: () {
          return ref
              .read(backupEnvironmentProvider.notifier)
              .seedFromPlatform();
        },
      );

      ref.listen<BackupSettings>(backupSettingsProvider, (prev, next) {
        notifier.updateSettings(next);
      });

      ref.listen<BackupEnvironment>(backupEnvironmentProvider, (prev, next) {
        notifier.updateEnvironment(next);
      });

      // backupEngineProvider's own state is the coarse BackupEngineState
      // enum (idle/scanning/uploading/paused/error), which only changes a
      // handful of times per backup run — it flips to `uploading` once and
      // then sits there for the whole batch. backupStatsProvider and
      // uploadQueueTasksProvider used to piggyback on THIS provider's
      // watch to know when to re-read stats/tasks, so they were frozen on
      // whatever the snapshot looked like the instant uploading started —
      // 0%, 0 B, "Pending" never moving to "Uploading" — even while the
      // engine was actively uploading in the background. Mirroring
      // statsStream into its own provider gives them a signal that fires
      // on every real progress/status change instead.
      final statsSubscription = notifier.engine.statsStream.listen((stats) {
        ref.read(_backupStatsStreamProvider.notifier).state = stats;
      });
      ref.onDispose(() => statsSubscription.cancel());

      return notifier;
    });

/// Internal: latest [BackupStats] pushed from [BackupEngine.statsStream].
/// Don't read this directly — go through [backupStatsProvider], which is
/// just a thin watch over this.
final _backupStatsStreamProvider = StateProvider<BackupStats>((ref) {
  return const BackupStats();
});

class BackupEngineNotifier extends StateNotifier<BackupEngineState> {
  BackupEngineNotifier({
    required this.galleryRepository,
    required this.uploadService,
    required BackupSettings settings,
    required BackupEnvironment environment,
    required StorageChannelService storageChannelService,
    int? persistedChannelId,
    void Function(int channelId)? onChannelResolved,
    void Function(DateTime? lastBackupAt, DateTime? lastScanAt)?
    onBackupTimestampsChanged,
    Future<void> Function()? ensureTdLibConnected,
    TransferQueuePersistence? queuePersistence,
    this.seedEnvironment,
  }) : super(BackupEngineState.idle) {
    _engine = BackupEngine(
      galleryRepository: galleryRepository,
      uploadService: uploadService,
      settings: settings,
      storageChannelService: storageChannelService,
      persistedChannelId: persistedChannelId,
      onChannelResolved: onChannelResolved,
      onBackupTimestampsChanged: onBackupTimestampsChanged,
      ensureTdLibConnected: ensureTdLibConnected,
      queuePersistence: queuePersistence,
      videoPosterGenerator: _generateVideoPoster,
    );
    _engine.updateEnvironment(environment);

    _stateSubscription = _engine.stateStream.listen((newState) {
      state = newState;
    });
  }

  final GalleryRepository galleryRepository;
  final UploadService uploadService;

  /// Re-reads connectivity/battery from the platform before a user-initiated
  /// start. The engine's environment is seeded asynchronously at startup
  /// (BackupEnvironmentNotifier.seedFromPlatform), so on a cold start it can
  /// still hold unseeded defaults when the user taps "Start Backup Now" — the
  /// Wi-Fi-only gate then refuses even though Wi-Fi is up. Awaiting this
  /// before every start guarantees the gates evaluate fresh platform state.
  final Future<void> Function()? seedEnvironment;

  late final BackupEngine _engine;
  StreamSubscription<BackupEngineState>? _stateSubscription;

  BackupEngine get engine => _engine;
  BackupStats get stats => _engine.stats;

  void updateSettings(BackupSettings settings) {
    _engine.updateSettings(settings);
  }

  void updateEnvironment(BackupEnvironment environment) {
    _engine.updateEnvironment(environment);
  }

  Future<void> scanAndEnqueue() async {
    await _engine.scanAndEnqueue();
  }

  Future<void> startBackup() async {
    await seedEnvironment?.call();
    await _engine.startBackup();
  }

  void pauseBackup() {
    _engine.pauseBackup();
  }

  Future<void> resumeBackup() async {
    await seedEnvironment?.call();
    await _engine.resumeBackup();
  }

  Future<void> retryFailed() async {
    await seedEnvironment?.call();
    await _engine.retryFailed();
  }

  Future<void> retryTask(String taskId) async {
    await _engine.retryTask(taskId);
  }

  void cancelTask(String taskId) {
    _engine.cancelTask(taskId);
  }

  void addToQueue(MediaItem item) {
    _engine.addToQueue(item);
  }

  /// Enqueue a single item the user just selected for backup so it appears
  /// on the dashboard right away, instead of only after the next full scan.
  void enqueueSelectedItem(MediaItem item) {
    _engine.enqueueSelectedItem(item);
  }

  /// Drop the queued task for an item the user just de-selected.
  void dequeueSelectedItem(String mediaItemId) {
    _engine.dequeueSelectedItem(mediaItemId);
  }

  /// Back up one specific item on demand, without draining the whole queue.
  Future<SingleBackupResult> backupItemNow(
    MediaItem item, {
    bool allowMobileData = false,
  }) {
    return _engine.backupItemNow(item, allowMobileData: allowMobileData);
  }

  void clearFinished() {
    _engine.clearFinished();
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _engine.dispose();
    super.dispose();
  }
}

/// Generates a poster frame for a video [task] and returns its temp-file path,
/// or null if no poster could be produced (asset gone, permission revoked,
/// empty bytes). Wired into [BackupEngine.videoPosterGenerator] so video
/// documents get an `inputThumbnail` and show a real timeline thumbnail —
/// video documents get no auto-thumbnail from Telegram otherwise.
///
/// Lives here (not in the engine) so `photo_manager`/`path_provider` stay out
/// of the engine, keeping its unit tests platform-free.
Future<String?> _generateVideoPoster(UploadTask task) async {
  try {
    // The queue task's mediaItemId is the photo_manager asset id.
    final asset = await AssetEntity.fromId(task.mediaItemId);
    if (asset == null) return null;

    // TDLib's inputThumbnail is capped at 320x320 (JPEG, <200KB) and silently
    // drops anything larger — so the poster MUST stay within that box or the
    // document uploads with no thumbnail at all.
    final bytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(320, 320),
    );
    if (bytes == null || bytes.isEmpty) return null;

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/poster_${task.id}_'
      '${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (e) {
    debugPrint('[backup] video poster generation failed: $e');
    return null;
  }
}

/// Backup stats provider (reactive).
final backupStatsProvider = Provider<BackupStats>((ref) {
  return ref.watch(_backupStatsStreamProvider);
});

/// Upload queue tasks provider.
final uploadQueueTasksProvider = Provider<List<UploadTask>>((ref) {
  ref.watch(_backupStatsStreamProvider);
  return ref.read(backupEngineProvider.notifier).engine.queue.allTasks;
});

/// The live upload task for one media item, keyed by its `localId`.
///
/// Lets a per-item surface (the media viewer's backup button) show real upload
/// progress. Rebuilds off the same stats signal as [uploadQueueTasksProvider],
/// which fires on every progress tick.
final uploadTaskForItemProvider = Provider.family<UploadTask?, String>((
  ref,
  mediaItemId,
) {
  ref.watch(_backupStatsStreamProvider);
  return ref
      .read(backupEngineProvider.notifier)
      .engine
      .queue
      .getTaskForMediaItem(mediaItemId);
});

/// Pending upload count provider.
final pendingUploadCountProvider = Provider<int>((ref) {
  final tasks = ref.watch(uploadQueueTasksProvider);
  return tasks.where((t) => t.status == UploadStatus.queued).length;
});

/// Failed upload count provider.
final failedUploadCountProvider = Provider<int>((ref) {
  final tasks = ref.watch(uploadQueueTasksProvider);
  return tasks.where((t) => t.status == UploadStatus.failed).length;
});

/// Whether backup is currently active provider.
final isBackupActiveProvider = Provider<bool>((ref) {
  final engineState = ref.watch(backupEngineProvider);
  return engineState == BackupEngineState.uploading;
});

/// Whether backup is paused provider.
final isBackupPausedProvider = Provider<bool>((ref) {
  final engineState = ref.watch(backupEngineProvider);
  return engineState == BackupEngineState.paused;
});

/// Keeps the WorkManager registrations in step with the user's settings.
///
/// Read once during bootstrap; after that the listener below re-registers
/// whenever the relevant settings change. Riverpod providers are lazy, so
/// without that initial read no background task is ever scheduled — which is
/// exactly how `BackgroundBackupService` came to be dead code.
final backgroundBackupSyncProvider = Provider<BackgroundBackupSync>((ref) {
  final sync = BackgroundBackupSync(BackgroundBackupService.instance);

  unawaited(
    sync.apply(
      enabled: ref.read(appSettingsProvider).backgroundBackupEnabled,
      settings: ref.read(backupSettingsProvider),
      isMiuiDevice: ref.read(isMiuiDeviceProvider).valueOrNull ?? false,
    ),
  );

  ref.listen<AppSettings>(appSettingsProvider, (_, next) {
    unawaited(
      sync.apply(
        enabled: next.backgroundBackupEnabled,
        settings: ref.read(backupSettingsProvider),
        isMiuiDevice: ref.read(isMiuiDeviceProvider).valueOrNull ?? false,
      ),
    );
  });

  ref.listen<BackupSettings>(backupSettingsProvider, (_, next) {
    unawaited(
      sync.apply(
        enabled: ref.read(appSettingsProvider).backgroundBackupEnabled,
        settings: next,
        isMiuiDevice: ref.read(isMiuiDeviceProvider).valueOrNull ?? false,
      ),
    );
  });

  return sync;
});

/// Applies (or removes) the WorkManager registrations for a settings snapshot.
class BackgroundBackupSync {
  BackgroundBackupSync(this._service);

  final BackupTaskScheduler _service;
  bool? _lastEnabled;
  BackupSettings? _lastSettings;

  /// Register or cancel the background tasks for the given settings.
  ///
  /// A no-op when nothing that affects scheduling changed: settings streams
  /// fire on every unrelated edit (theme, grid size), and re-registering on
  /// each one would churn WorkManager's database for nothing.
  ///
  /// [isMiuiDevice] promotes the media scanner to a foreground service on
  /// Xiaomi/Redmi/POCO devices to prevent MIUI from killing it.
  Future<void> apply({
    required bool enabled,
    required BackupSettings settings,
    bool isMiuiDevice = false,
  }) async {
    if (_lastEnabled == enabled && _schedulingEquals(_lastSettings, settings)) {
      return;
    }
    _lastEnabled = enabled;
    _lastSettings = settings;

    try {
      if (!enabled) {
        await _service.cancelAll();
        return;
      }
      await _service.registerAllTasks(
        settings: settings,
        promoteScannerToForeground: isMiuiDevice,
      );
    } catch (e) {
      // No WorkManager on this platform (desktop, tests) — the app must still
      // start, it just won't back up in the background.
      debugPrint('[BackgroundBackupSync] Could not apply registrations: $e');
    }
  }

  bool _schedulingEquals(BackupSettings? a, BackupSettings b) {
    if (a == null) return false;
    return a.isAutoBackupEnabled == b.isAutoBackupEnabled &&
        a.wifiOnly == b.wifiOnly &&
        a.chargingOnly == b.chargingOnly;
  }
}
