import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/people/data/repositories/face_scan_lock.dart';
import 'package:lumovault/features/people/presentation/providers/people_providers.dart';
import 'package:lumovault/features/people/presentation/widgets/face_scan_background_handoff.dart';

/// When the user leaves the app mid-scan, Android freezes the UI isolate and
/// the in-app scan stalls. The hand-off enqueues the one-off WorkManager face
/// scan (foreground-service-promoted) on `paused` so the remaining photos are
/// grouped while the app is frozen; the repository skips already-scanned
/// photos, so the two scans dovetail.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FaceScanBackgroundHandoff', () {
    var scheduled = 0;
    var scheduleThrows = false;

    setUp(() {
      scheduled = 0;
      scheduleThrows = false;
      scheduleOneOffFaceScan = () async {
        scheduled++;
        if (scheduleThrows) throw StateError('no workmanager here');
      };
    });

    tearDown(() {
      scheduleOneOffFaceScan = null;
    });

    Future<void> pumpHandoff(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: FaceScanBackgroundHandoff(child: SizedBox()),
        ),
      );
    }

    void setScanning(WidgetTester tester, bool scanning) {
      final context = tester.element(find.byType(FaceScanBackgroundHandoff));
      ProviderScope.containerOf(
        context,
      ).read(faceScanProgressProvider.notifier).state = FaceScanProgress(
        current: 1,
        total: 10,
        isScanning: scanning,
      );
    }

    testWidgets('enqueues the background scan when paused mid-scan', (
      tester,
    ) async {
      await pumpHandoff(tester);
      setScanning(tester, true);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(scheduled, 1);
    });

    testWidgets('does nothing when no scan is running', (tester) async {
      await pumpHandoff(tester);
      setScanning(tester, false);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(scheduled, 0);
    });

    testWidgets('a scheduling failure does not crash the app', (tester) async {
      scheduleThrows = true;
      await pumpHandoff(tester);
      setScanning(tester, true);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(scheduled, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not fire for foreground-only lifecycle changes', (
      tester,
    ) async {
      await pumpHandoff(tester);
      setScanning(tester, true);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(scheduled, 0);
    });
  });
}
