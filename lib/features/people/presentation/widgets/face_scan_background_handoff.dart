import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/face_scan_lock.dart';
import '../providers/people_providers.dart';

/// Hands an in-app face scan off to the background when the app leaves the
/// foreground mid-scan.
///
/// Android freezes the app's Dart VM within seconds of losing focus
/// (MIUI/HyperOS is even more aggressive), which stalls a running
/// [FaceScanController] mid-batch. The scan is resumable — already-scanned
/// photos are skipped via the face_scans table — so on `paused` we enqueue a
/// one-off background face-scan task: the WorkManager isolate, running under
/// the face-scan foreground service, finishes the remaining photos while the
/// app is frozen, and the People grid reflects them when the user returns.
///
/// Mounted next to [AppLockGate] so it wraps the whole navigator.
class FaceScanBackgroundHandoff extends ConsumerStatefulWidget {
  const FaceScanBackgroundHandoff({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<FaceScanBackgroundHandoff> createState() =>
      _FaceScanBackgroundHandoffState();
}

class _FaceScanBackgroundHandoffState
    extends ConsumerState<FaceScanBackgroundHandoff>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused) return;
    // Keyed on the progress provider rather than the controller's private
    // field: same truth (the controller sets isScanning for the whole run),
    // and settable directly in widget tests.
    if (!ref.read(faceScanProgressProvider).isScanning) return;

    final schedule = scheduleOneOffFaceScan;
    if (schedule == null) {
      debugPrint('[FaceScanHandoff] No scheduler wired; scan will stall');
      return;
    }
    unawaited(() async {
      try {
        await schedule();
      } catch (e) {
        // Fire-and-forget by contract: the in-app scan keeps the lock and
        // keeps running whenever the app is next resumed, and the periodic
        // face-scan task remains as the safety net.
        debugPrint('[FaceScanHandoff] Scheduling failed: $e');
      }
    }());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
