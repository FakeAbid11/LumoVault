import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/backup_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../core/di/tdlib_providers.dart';
import '../../../settings/presentation/providers/settings_providers.dart';

/// Scans for and enqueues newly-added device media whenever the app becomes
/// active — a foreground counterpart to the background WorkManager periodics.
///
/// Without this, `BackupEngine.scanAndEnqueue()` only ran from onboarding and
/// the 15-minute WorkManager tasks. Those periodics are heavily deferred by
/// Android OEM battery optimizations, so a photo the user just took (e.g. in
/// their camera app) could sit un-backed-up for hours. This observer catches
/// it as soon as they open or return to LumoVault instead.
///
/// Pure passthrough — renders [child] and adds no UI. Mirrors [AppLockGate]'s
/// lifecycle-observer pattern.
class BackupForegroundSync extends ConsumerStatefulWidget {
  const BackupForegroundSync({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<BackupForegroundSync> createState() =>
      _BackupForegroundSyncState();
}

class _BackupForegroundSyncState extends ConsumerState<BackupForegroundSync>
    with WidgetsBindingObserver {
  /// Guards against overlapping runs (a scan is async and can outlast a
  /// rapid background/foreground bounce).
  bool _inFlight = false;

  /// When the last sync started, to debounce resume storms. `didChange...`
  /// can fire several times in quick succession on some OEMs.
  DateTime? _lastRun;

  static const _minInterval = Duration(seconds: 45);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A cold start begins already in `resumed`, so didChangeAppLifecycleState
    // won't fire for the first launch — kick off the initial run once the
    // first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_maybeSync());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_maybeSync());
    }
  }

  Future<void> _maybeSync() async {
    if (_inFlight) return;
    final now = DateTime.now();
    if (_lastRun != null && now.difference(_lastRun!) < _minInterval) {
      return;
    }

    final settings = ref.read(appSettingsProvider);
    if (!settings.onboardingCompleted) return; // onboarding has its own trigger
    if (!settings.autoBackupEnabled) return; // respect the auto-backup toggle

    _inFlight = true;
    _lastRun = now;
    try {
      final engine = ref.read(backupEngineProvider.notifier);
      // Discover any new device media and queue it. Reads the engine's
      // (already-hydrated, in the foreground isolate) includedFolders.
      await engine.scanAndEnqueue();
      // Only drain the queue if signed in; otherwise leave it queued for the
      // next start rather than tripping startBackup()'s connect-failure path.
      if (ref.read(isAuthenticatedProvider)) {
        await engine.startBackup();
      }
    } catch (e) {
      debugPrint('[BackupForegroundSync] sync failed: $e');
    } finally {
      _inFlight = false;
    }
  }

  /// Drain the backup queue when auth lands — separate from [_maybeSync]
  /// because the scan already ran but was blocked on authentication. No
  /// debounce needed; this only fires on a genuine auth state transition.
  Future<void> _drainOnAuth() async {
    if (_inFlight) return;
    final settings = ref.read(appSettingsProvider);
    if (!settings.onboardingCompleted || !settings.autoBackupEnabled) return;
    if (!ref.read(isAuthenticatedProvider)) return;

    _inFlight = true;
    try {
      final engine = ref.read(backupEngineProvider.notifier);
      await engine.startBackup();
    } catch (e) {
      debugPrint('[BackupForegroundSync] auth drain failed: $e');
    } finally {
      _inFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // When auth state transitions to authenticated, drain any queued items
    // so backed-up photos don't sit "in queue" until the next lifecycle event.
    ref.listen<bool>(isAuthenticatedProvider, (previous, isAuth) {
      if (isAuth) {
        unawaited(_drainOnAuth());
      }
    });
    // Trigger background CLIP embedding generation for images that don't have
    // one yet. This supplements the periodic WorkManager task so embeddings
    // are ready sooner after the app foregrounds.
    ref.watch(generateEmbeddingsProvider);
    return widget.child;
  }
}
