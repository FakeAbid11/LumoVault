import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/constants/app_constants.dart';
import 'package:lumovault/core/device/brand_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetBrandSettingsOverrides);
  tearDown(resetBrandSettingsOverrides);

  group('openAutostartSettings', () {
    test('returns true when the native MIUI page opens', () async {
      nativeAutostartOverride = () async => true;
      var appInfoCalls = 0;
      openAppInfoOverride = () async => appInfoCalls++;

      final ok = await BrandSettings.openAutostartSettings('com.lumovault.app');

      expect(ok, isTrue);
      expect(appInfoCalls, 0);
    });

    test(
      'falls back to App Info when the native page is unavailable',
      () async {
        nativeAutostartOverride = () async => false;
        var appInfoCalls = 0;
        openAppInfoOverride = () async => appInfoCalls++;

        final ok = await BrandSettings.openAutostartSettings(
          'com.lumovault.app',
        );

        expect(ok, isTrue);
        expect(appInfoCalls, 1);
      },
    );

    test('returns false when every path fails', () async {
      nativeAutostartOverride = () async => false;
      openAppInfoOverride = () => throw Exception('no settings activity');

      final ok = await BrandSettings.openAutostartSettings('com.lumovault.app');

      expect(ok, isFalse);
    });
  });

  group('openBatterySettings', () {
    test('returns true when the native battery page opens', () async {
      nativeBatteryOverride = () async => true;
      var appInfoCalls = 0;
      openAppInfoOverride = () async => appInfoCalls++;

      expect(
        await BrandSettings.openBatterySettings('com.lumovault.app'),
        isTrue,
      );
      expect(appInfoCalls, 0);
    });

    test('falls back to App Info when the native path misses', () async {
      nativeBatteryOverride = () async => false;
      var appInfoCalls = 0;
      openAppInfoOverride = () async => appInfoCalls++;

      expect(
        await BrandSettings.openBatterySettings('com.lumovault.app'),
        isTrue,
      );
      expect(appInfoCalls, 1);
    });

    test('falls back to App Info when the native path throws', () async {
      nativeBatteryOverride = () => throw Exception('channel wedged');
      openAppInfoOverride = () async {};

      expect(
        await BrandSettings.openBatterySettings('com.lumovault.app'),
        isTrue,
      );
    });

    test('returns false when every path fails', () async {
      nativeBatteryOverride = () async => false;
      openAppInfoOverride = () => throw Exception('no settings activity');

      expect(
        await BrandSettings.openBatterySettings('com.lumovault.app'),
        isFalse,
      );
    });
  });

  group('OEM convenience wrappers', () {
    test('all delegate to the battery + App Info path', () async {
      nativeBatteryOverride = () async => true;

      for (final open in [
        BrandSettings.openSamsungBatterySettings,
        BrandSettings.openSamsungBatteryOptimization,
        BrandSettings.openHuaweiAppLaunch,
        BrandSettings.openHuaweiBatteryOptimization,
        BrandSettings.openOnePlusAutoLaunch,
        BrandSettings.openOnePlusBatterySettings,
        BrandSettings.openOppoStartupManager,
        BrandSettings.openOppoBatterySettings,
      ]) {
        expect(await open('com.lumovault.app'), isTrue);
      }
    });
  });

  group('resolvePackageName', () {
    test('falls back to the build-time constant without the channel', () async {
      expect(
        await BrandSettings.resolvePackageName(),
        AppConstants.packageName,
      );
    });
  });
}
