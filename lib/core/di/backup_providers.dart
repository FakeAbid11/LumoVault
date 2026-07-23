import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/backup/data/models/backup_settings.dart';
import '../../features/backup/engine/backup_engine.dart';
import '../../features/backup/engine/backup_scheduler.dart';
import '../../features/gallery/data/models/media_item.dart';
import '../../features/gallery/data/models/upload_task.dart';
import '../../features/gallery/data/repositories/gallery_repository.dart';
import '../../features/gallery/data/repositories/telegram_upload_service.dart';
import '../../features/settings/presentation/providers/settings_providers.dart';
import '../storage/storage_channel_service.dart';
import 'gallery_providers.dart';
import 'tdlib_providers.dart';
import 'transfer_providers.dart';

/// Backup settings state provider.
///
/// Persists backup configuration in memory (would be Isar in production).
final backupSettingsProvider =
    StateNotifierProvider<BackupSettingsNotifier, BackupSettings>((ref) {
      return BackupSettingsNotifier();
    });

class BackupSettingsNotifier extends StateNotifier<BackupSettings> {
  BackupSettingsNotifier() : super(const BackupSettings());

  void updateAutoBackup(bool enabled) {
    state = state.copyWith(isAutoBackupEnabled: enabled);
  }

  void updateWifiOnly(bool enabled) {
    state = state.copyWith(wifiOnly: enabled);
  }

  void updateChargingOnly(bool enabled) {
    state = state.copyWith(chargingOnly: enabled);
  }

  void updateBackupPhotos(bool enabled) {
    state = state.copyWith(backupPhotos: enabled);
  }

  void updateBackupVideos(bool enabled) {
    state = state.copyWith(backupVideos: enabled);
  }

  void updateMaxFileSize(int? maxFileSize) {
    if (maxFileSize == null) {
      state = state.copyWith(clearMaxFileSize: () => null);
    } else {
      state = state.copyWith(maxFileSize: maxFileSize);
    }
  }

  void updateIncludedFolders(List<String> folders) {
    state = state.copyWith(includedFolders: folders);
  }

  void updateExcludedFolders(List<String> folders) {
    state = state.copyWith(excludedFolders: folders);
  }

  void updateExcludedFileHashes(List<String> hashes) {
    state = state.copyWith(excludedFileHashes: hashes);
  }

  void updateUploadBatchSize(int batchSize) {
    state = state.copyWith(uploadBatchSize: batchSize);
  }

  void updateUploadDelayMs(int delayMs) {
    state = state.copyWith(uploadDelayMs: delayMs);
  }

  void toggleFolderExclusion(String folderPath) {
    final excluded = List<String>.of(state.excludedFolders);
    if (excluded.contains(folderPath)) {
      excluded.remove(folderPath);
    } else {
      excluded.add(folderPath);
    }
    state = state.copyWith(excludedFolders: excluded);
  }

  void toggleFileExclusion(String fileHash) {
    final excluded = List<String>.of(state.excludedFileHashes);
    if (excluded.contains(fileHash)) {
      excluded.remove(fileHash);
    } else {
      excluded.add(fileHash);
    }
    state = state.copyWith(excludedFileHashes: excluded);
  }

  void updateLastBackupAt(DateTime? timestamp) {
    state = state.copyWith(lastBackupAt: timestamp);
  }

  void updateLastScanAt(DateTime? timestamp) {
    state = state.copyWith(lastScanAt: timestamp);
  }
}

/// Backup environment provider (connectivity, battery).
final backupEnvironmentProvider =
    StateNotifierProvider<BackupEnvironmentNotifier, BackupEnvironment>((ref) {
      return BackupEnvironmentNotifier();
    });

class BackupEnvironmentNotifier extends StateNotifier<BackupEnvironment> {
  BackupEnvironmentNotifier() : super(const BackupEnvironment()) {
    _initConnectivityListener();
  }

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final hasWifi = results.any((r) => r == ConnectivityResult.wifi);
      state = BackupEnvironment(
        isWifiConnected: hasWifi,
        isCharging: state.isCharging,
        batteryLevel: state.batteryLevel,
        isAutoBackupEnabled: state.isAutoBackupEnabled,
      );
    });
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

      final notifier = BackupEngineNotifier(
        galleryRepository: galleryRepository,
        uploadService: uploadService,
        settings: settings,
        environment: environment,
        storageChannelService: storageChannelService,
        persistedChannelId: persistedChannelId,
        onChannelResolved: (channelId) {
          ref.read(appSettingsProvider.notifier).setStorageChannelId(channelId);
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
  }) : super(BackupEngineState.idle) {
    _engine = BackupEngine(
      galleryRepository: galleryRepository,
      uploadService: uploadService,
      settings: settings,
      storageChannelService: storageChannelService,
      persistedChannelId: persistedChannelId,
      onChannelResolved: onChannelResolved,
    );
    _engine.updateEnvironment(environment);

    _stateSubscription = _engine.stateStream.listen((newState) {
      state = newState;
    });
  }

  final GalleryRepository galleryRepository;
  final UploadService uploadService;
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
    await _engine.startBackup();
  }

  void pauseBackup() {
    _engine.pauseBackup();
  }

  Future<void> resumeBackup() async {
    await _engine.resumeBackup();
  }

  Future<void> retryFailed() async {
    await _engine.retryFailed();
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

/// Backup stats provider (reactive).
final backupStatsProvider = Provider<BackupStats>((ref) {
  return ref.watch(_backupStatsStreamProvider);
});

/// Upload queue tasks provider.
final uploadQueueTasksProvider = Provider<List<UploadTask>>((ref) {
  ref.watch(_backupStatsStreamProvider);
  return ref.read(backupEngineProvider.notifier).engine.queue.allTasks;
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
