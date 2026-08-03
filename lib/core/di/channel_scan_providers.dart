import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/restore/data/repositories/channel_scan_service.dart';
import '../../features/restore/presentation/providers/restore_providers.dart';
import 'gallery_providers.dart';
import 'tdlib_providers.dart';

/// Channel scan service provider.
///
/// Depends on TDLib connection, storage channel service, download service,
/// and gallery repository — all already wired through existing providers.
final channelScanServiceProvider = Provider<ChannelScanService>((ref) {
  final manager = ref.watch(tdLibConnectionManagerProvider);
  final storageChannelService = ref.watch(storageChannelServiceProvider);
  final downloadService = ref.watch(downloadServiceProvider);
  final galleryRepository = ref.watch(galleryRepositoryProvider);

  return ChannelScanService(
    client: manager.client,
    storageChannelService: storageChannelService,
    downloadService: downloadService,
    galleryRepository: galleryRepository,
  );
});

/// Possible states for the channel scan lifecycle.
enum ChannelScanStatus { idle, scanning, completed, failed }

/// State of the channel scan including progress information.
class ChannelScanState {
  const ChannelScanState({
    this.status = ChannelScanStatus.idle,
    this.totalItems = 0,
    this.scannedItems = 0,
    this.newItems = 0,
    this.failedThumbnails = 0,
    this.hasBackup = false,
    this.error,
    this.currentFileName,
  });

  final ChannelScanStatus status;
  final int totalItems;
  final int scannedItems;
  final int newItems;
  final int failedThumbnails;
  final bool hasBackup;
  final String? error;
  final String? currentFileName;

  double get progress => totalItems > 0 ? scannedItems / totalItems : 0.0;

  ChannelScanState copyWith({
    ChannelScanStatus? status,
    int? totalItems,
    int? scannedItems,
    int? newItems,
    int? failedThumbnails,
    bool? hasBackup,
    String? error,
    String? currentFileName,
    bool clearError = false,
    bool clearFileName = false,
  }) {
    return ChannelScanState(
      status: status ?? this.status,
      totalItems: totalItems ?? this.totalItems,
      scannedItems: scannedItems ?? this.scannedItems,
      newItems: newItems ?? this.newItems,
      failedThumbnails: failedThumbnails ?? this.failedThumbnails,
      hasBackup: hasBackup ?? this.hasBackup,
      error: clearError ? null : (error ?? this.error),
      currentFileName: clearFileName
          ? null
          : (currentFileName ?? this.currentFileName),
    );
  }
}

/// Notifier that manages the channel scan lifecycle.
class ChannelScanNotifier extends StateNotifier<ChannelScanState> {
  ChannelScanNotifier(this._ref) : super(const ChannelScanState());

  final Ref _ref;

  /// Trigger a scan of the existing backup channel.
  ///
  /// Idempotent — if a scan has already completed successfully, this is
  /// a no-op unless [forceRescan] is true.
  Future<void> scan({bool forceRescan = false}) async {
    if (state.status == ChannelScanStatus.scanning) return;
    if (state.status == ChannelScanStatus.completed && !forceRescan) return;

    state = const ChannelScanState(status: ChannelScanStatus.scanning);

    try {
      // Ensure TDLib is initialized before scanning.
      await _ref.read(tdLibInitializedProvider.future);
      // Ensure auth service is ready.
      await _ref.read(authServiceProvider).initialize();
    } catch (e) {
      state = state.copyWith(
        status: ChannelScanStatus.failed,
        error: 'Could not connect to Telegram',
      );
      return;
    }

    final service = _ref.read(channelScanServiceProvider);

    // Reset the service's scan flag so a rescan actually re-fetches messages.
    if (forceRescan) {
      service.resetScanState();
    }

    state = state.copyWith(
      status: ChannelScanStatus.scanning,
      clearError: true,
    );

    final result = await service.scanChannel(
      onProgress: (current, total, fileName) {
        state = state.copyWith(
          scannedItems: current,
          totalItems: total,
          currentFileName: fileName,
        );
      },
    );

    if (result.hasError) {
      state = state.copyWith(
        status: ChannelScanStatus.failed,
        error: result.error,
      );
      return;
    }

    state = state.copyWith(
      status: ChannelScanStatus.completed,
      totalItems: result.totalItems,
      scannedItems: result.totalItems,
      newItems: result.newItems,
      failedThumbnails: result.failedThumbnails,
      hasBackup: result.hasBackup,
      clearFileName: true,
    );
  }
}

/// Channel scan state notifier provider.
final channelScanStateProvider =
    StateNotifierProvider<ChannelScanNotifier, ChannelScanState>((ref) {
      return ChannelScanNotifier(ref);
    });

/// Auto-trigger provider that watches authentication state and triggers
/// a channel scan when the user becomes authenticated.
///
/// This provider is meant to be read once during app initialization (or
/// when the auth gate transitions to authenticated) — it handles the
/// "scan after login" flow automatically.
final autoChannelScanProvider = Provider<bool>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  final scanNotifier = ref.watch(channelScanStateProvider.notifier);
  final scanState = ref.watch(channelScanStateProvider);

  // Trigger scan when authenticated and not yet scanned.
  if (isAuthenticated && scanState.status == ChannelScanStatus.idle) {
    // Use Future.microtask to avoid calling state changes during build.
    Future.microtask(() => scanNotifier.scan());
  }

  return isAuthenticated;
});

/// Provider that exposes the current scan progress as a simple (current, total)
/// tuple — useful for showing a progress indicator in the timeline.
final channelScanProgressProvider = Provider<(int, int, bool)>((ref) {
  final scanState = ref.watch(channelScanStateProvider);
  return (
    scanState.scannedItems,
    scanState.totalItems,
    scanState.status == ChannelScanStatus.scanning,
  );
});
