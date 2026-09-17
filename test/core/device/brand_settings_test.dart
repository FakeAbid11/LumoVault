import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/device/brand_settings.dart';

/// Drives the REAL `lumo.app/settings` method channel with a mock
/// messenger — the previous override-hook seam let tests pass while the
/// production url_launcher path was a guaranteed no-op on MIUI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const settingsChannel = MethodChannel('lumo.app/settings');
  const appChannel = MethodChannel('lumo.app/package');

  final calls = <MethodCall>[];

  void mockSettings(bool Function(MethodCall call) responder) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(settingsChannel, (call) async {
          calls.add(call);
          return responder(call);
        });
  }

  void clearMocks() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(settingsChannel, null);
    messenger.setMockMethodCallHandler(appChannel, null);
  }

  List<MethodCall> launches() =>
      calls.where((c) => c.method == 'launchComponent').toList();

  setUp(calls.clear);
  tearDown(clearMocks);

  group('openAutostartSettings', () {
    test(
      'tries AutoStartManagementActivity first and short-circuits',
      () async {
        mockSettings(
          (call) =>
              (call.arguments as Map)['activity'] ==
              'com.miui.permcenter.autostart.AutoStartManagementActivity',
        );

        expect(
          await BrandSettings.openAutostartSettings('com.lumovault.app'),
          isTrue,
        );
        expect(calls, hasLength(1));
        final first = launches().single;
        expect((first.arguments as Map)['package'], 'com.miui.securitycenter');
      },
    );

    test(
      'all-fail chain: activity → permission editor ×2 → app details',
      () async {
        mockSettings((_) => false);

        expect(
          await BrandSettings.openAutostartSettings('com.lumovault.app'),
          isFalse,
        );

        final args = launches().map((c) => c.arguments as Map).toList();
        expect(args, hasLength(3));
        expect(
          args[0]['activity'],
          'com.miui.permcenter.autostart.AutoStartManagementActivity',
        );
        expect(args[1]['action'], 'miui.intent.action.APP_PERM_EDITOR');
        expect((args[1]['extras'] as Map).containsKey('extra_pkgname'), isTrue);
        expect((args[2]['extras'] as Map).containsKey('pkgname'), isTrue);
        // Last candidate is the honest floor: the app's system info page.
        expect(calls.last.method, 'openAppDetails');
      },
    );
  });

  group('openBatterySettings', () {
    test('prefers the com.miui.powerkeeper host', () async {
      mockSettings((call) {
        final args = call.arguments as Map;
        return call.method == 'launchComponent' &&
            args['package'] == 'com.miui.powerkeeper';
      });

      expect(
        await BrandSettings.openBatterySettings('com.lumovault.app'),
        isTrue,
      );
      expect(calls, hasLength(1));
      final args = calls.single.arguments as Map;
      expect(
        args['activity'],
        'com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
      );
      expect((args['extras'] as Map)['package_name'], 'com.lumovault.app');
    });

    test('falls through the securitycenter host, then app details', () async {
      mockSettings((_) => false);

      await BrandSettings.openBatterySettings('com.lumovault.app');

      final args = launches().map((c) => c.arguments as Map).toList();
      expect(args[0]['package'], 'com.miui.powerkeeper');
      expect(args[1]['package'], 'com.miui.securitycenter');
      expect(
        args[1]['activity'],
        'com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
      );
      expect(calls.last.method, 'openAppDetails');
    });
  });

  group('generic launchers', () {
    test('openAppSettings is a single native app-details call', () async {
      mockSettings((_) => true);

      expect(await BrandSettings.openAppSettings('com.lumovault.app'), isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'openAppDetails');
    });

    test(
      'openBatteryOptimizationSettings maps to the native list screen',
      () async {
        mockSettings((_) => true);

        expect(await BrandSettings.openBatteryOptimizationSettings(), isTrue);
        expect(calls.single.method, 'openBatteryOptimizations');
      },
    );

    test(
      'OEM helpers land on app details (no fake deep-link tables)',
      () async {
        mockSettings((_) => true);

        expect(
          await BrandSettings.openSamsungBatterySettings('com.lumovault.app'),
          isTrue,
        );
        expect(
          await BrandSettings.openOnePlusAutoLaunch('com.lumovault.app'),
          isTrue,
        );
        expect(
          await BrandSettings.openOppoStartupManager('com.lumovault.app'),
          isTrue,
        );
        expect(calls, hasLength(3));
        expect(calls.every((c) => c.method == 'openAppDetails'), isTrue);
      },
    );

    test('missing channel yields false without throwing', () async {
      // No mock handler installed → MissingPluginException at invoke time.
      clearMocks();
      expect(
        await BrandSettings.openAutostartSettings('com.lumovault.app'),
        isFalse,
      );
      expect(await BrandSettings.openAppSettings('com.lumovault.app'), isFalse);
      expect(await BrandSettings.openBatteryOptimizationSettings(), isFalse);
    });
  });

  group('resolvePackageName', () {
    test('uses the platform package channel', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(appChannel, (call) async {
            expect(call.method, 'getPackageName');
            return 'com.example.flavor';
          });

      expect(await BrandSettings.resolvePackageName(), 'com.example.flavor');
    });

    test('falls back to the known id when no channel exists', () async {
      clearMocks();
      expect(await BrandSettings.resolvePackageName(), 'com.lumovault.app');
    });
  });
}
