import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../core/di/metadata_providers.dart';
import '../../../../core/di/tdlib_providers.dart';
import '../../../gallery/data/repositories/telegram_download_service.dart';
import '../../data/models/restore_progress.dart';
import '../../data/repositories/restore_repository.dart';
import '../../engine/restore_engine.dart';

/// Whether a restore is currently in progress.
final isRestoreActiveProvider = Provider<bool>((ref) {
  final progress = ref.watch(restoreProgressProvider);
  return progress.isActive;
});

/// Current restore progress state.
final restoreProgressProvider =
    StateNotifierProvider<RestoreProgressNotifier, RestoreProgress>((ref) {
      return RestoreProgressNotifier();
    });

/// Notifier for managing restore progress state.
class RestoreProgressNotifier extends StateNotifier<RestoreProgress> {
  RestoreProgressNotifier() : super(const RestoreProgress());

  void updateProgress(RestoreProgress progress) {
    state = progress;
  }

  void reset() {
    state = const RestoreProgress();
  }
}

/// Restore engine provider.
final restoreEngineProvider = Provider<RestoreEngine>((ref) {
  final tdLibClient = ref.watch(tdLibClientProvider);
  final storageChannelService = ref.watch(storageChannelServiceProvider);
  final downloadService = ref.watch(downloadServiceProvider);
  final galleryRepository = ref.watch(galleryRepositoryProvider);
  final metadataRepository = ref.watch(metadataRepositoryProvider);
  final manifestService = ref.watch(manifestServiceProvider);
  final partitionService = ref.watch(partitionServiceProvider);
  final searchIndexService = ref.watch(searchIndexServiceProvider);

  final engine = RestoreEngine(
    restoreRepository: RestoreRepository(
      client: tdLibClient,
      storageChannelService: storageChannelService,
      downloadService: downloadService,
      storageBasePath: '/data/user/0/com.lumovault.app/files',
    ),
    galleryRepository: galleryRepository,
    metadataRepository: metadataRepository,
    manifestService: manifestService,
    partitionService: partitionService,
    searchIndexService: searchIndexService,
  );

  ref.onDispose(() => engine.dispose());
  return engine;
});

/// Provider for starting a restore operation.
final startRestoreProvider = Provider<Future<bool> Function()>((ref) {
  final engine = ref.watch(restoreEngineProvider);
  final progressNotifier = ref.watch(restoreProgressProvider.notifier);

  return () async {
    // Subscribe to engine progress updates
    final subscription = engine.progressStream.listen((progress) {
      progressNotifier.updateProgress(progress);
    });

    try {
      final success = await engine.startRestore();
      return success;
    } finally {
      await subscription.cancel();
    }
  };
});

/// Provider for pausing restore.
final pauseRestoreProvider = Provider<void Function()>((ref) {
  final engine = ref.watch(restoreEngineProvider);
  return () => engine.pauseRestore();
});

/// Provider for resuming restore.
final resumeRestoreProvider = Provider<void Function()>((ref) {
  final engine = ref.watch(restoreEngineProvider);
  return () => engine.resumeRestore();
});

/// Provider for cancelling restore.
final cancelRestoreProvider = Provider<void Function()>((ref) {
  final engine = ref.watch(restoreEngineProvider);
  final progressNotifier = ref.watch(restoreProgressProvider.notifier);
  return () {
    engine.cancelRestore();
    progressNotifier.reset();
  };
});

/// Whether the user should be shown the restore flow after auth.
///
/// Per PRD Section 10.1: after successful Telegram auth, detect if
/// an existing storage channel has prior backup data.
final shouldShowRestoreProvider = FutureProvider<bool>((ref) async {
  final authService = ref.watch(authServiceProvider);

  // Only check if user is authenticated
  if (authService.currentState != AuthState.authenticated) {
    return false;
  }

  try {
    final engine = ref.watch(restoreEngineProvider);
    final result = await engine.restoreRepository.detectExistingBackup();
    return result.hasBackup;
  } catch (e) {
    return false;
  }
});

/// Download service provider (from transfer_providers).
final downloadServiceProvider = Provider<DownloadService>((ref) {
  final manager = ref.watch(tdLibConnectionManagerProvider);
  return TelegramDownloadService(manager: manager);
});
