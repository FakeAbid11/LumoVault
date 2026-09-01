import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/di/backup_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupEnvironmentNotifier.seedFromPlatform', () {
    test('seeds Wi-Fi connectivity from the platform read', () async {
      final notifier = BackupEnvironmentNotifier(
        checkConnectivity: () async => [ConnectivityResult.wifi],
        connectivityStream: () => const Stream.empty(),
        batteryLevelReader: () async => 80,
        batteryStateStream: () => const Stream.empty(),
      );
      addTearDown(notifier.dispose);

      await notifier.seedFromPlatform();

      expect(notifier.state.isWifiConnected, isTrue);
      expect(notifier.state.batteryLevel, 80);
    });

    test('seeds a non-wifi connection as not connected', () async {
      final notifier = BackupEnvironmentNotifier(
        checkConnectivity: () async => [ConnectivityResult.mobile],
        connectivityStream: () => const Stream.empty(),
        batteryLevelReader: () async => 80,
        batteryStateStream: () => const Stream.empty(),
      );
      addTearDown(notifier.dispose);

      await notifier.seedFromPlatform();

      expect(notifier.state.isWifiConnected, isFalse);
    });

    test('a failing connectivity read keeps the previous state', () async {
      final notifier = BackupEnvironmentNotifier(
        checkConnectivity: () => throw StateError('channel down'),
        connectivityStream: () => const Stream.empty(),
        batteryLevelReader: () async => 80,
        batteryStateStream: () => const Stream.empty(),
      );
      addTearDown(notifier.dispose);

      await notifier.seedFromPlatform();

      // Battery still seeded; no bogus zero from the failed connectivity read.
      expect(notifier.state.batteryLevel, 80);
      expect(notifier.state.isWifiConnected, isFalse);
    });

    test('an out-of-range battery level is ignored', () async {
      final notifier = BackupEnvironmentNotifier(
        checkConnectivity: () async => [ConnectivityResult.wifi],
        connectivityStream: () => const Stream.empty(),
        batteryLevelReader: () async => -1,
        batteryStateStream: () => const Stream.empty(),
      );
      addTearDown(notifier.dispose);

      await notifier.seedFromPlatform();

      expect(notifier.state.batteryLevel, 100); // unchanged default
      expect(notifier.state.isWifiConnected, isTrue);
    });

    test('charging state arrives through the battery stream', () async {
      final charging = StreamController<BatteryState>();
      final notifier = BackupEnvironmentNotifier(
        checkConnectivity: () async => [ConnectivityResult.wifi],
        connectivityStream: () => const Stream.empty(),
        batteryLevelReader: () async => 80,
        batteryStateStream: () => charging.stream,
      );
      addTearDown(notifier.dispose);
      addTearDown(charging.close);

      charging.add(BatteryState.charging);
      await notifier.seedFromPlatform();

      expect(notifier.state.isCharging, isTrue);
    });
  });
}
