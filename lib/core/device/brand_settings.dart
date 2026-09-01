import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../constants/app_constants.dart';

/// Method channel shared with [MainActivity]
/// (`android/app/src/main/kotlin/com/lumovault/app/MainActivity.kt`), which
/// serves both `getPackageName` and the MIUI autostart deep link.
const MethodChannel _packageChannel = MethodChannel('lumo.app/package');

/// User-facing hint shown when an automatic Settings launch fails. Kept here
/// so every call site surfaces the same guidance.
const String kOpenSettingsFallbackHint =
    "Couldn't open Settings automatically. "
    'Open device Settings → Apps → LumoVault manually.';

// ── Test seams ──────────────────────────────────────────────────────────
// Each launch mechanism is injectable so [BrandSettings] can be unit-tested
// without a platform channel — same pattern as TdRequestSender upstream.

/// When set, used instead of the native `openMiuiAutostart` channel call.
@visibleForTesting
Future<bool> Function()? nativeAutostartOverride;

/// When set, used instead of the native `openMiuiBatterySettings` call.
@visibleForTesting
Future<bool> Function()? nativeBatteryOverride;

/// When set, used instead of permission_handler's `openAppSettings`.
@visibleForTesting
Future<void> Function()? openAppInfoOverride;

/// Clears every test seam. Call from test `tearDown`.
@visibleForTesting
void resetBrandSettingsOverrides() {
  nativeAutostartOverride = null;
  nativeBatteryOverride = null;
  openAppInfoOverride = null;
}

/// Brand-specific deep links for background permission settings.
///
/// Each manufacturer has different settings pages for autostart, battery
/// optimization, and background activity. Three mechanisms are used:
///
/// 1. **Native explicit-component intents** (MIUI Autostart only) — the page
///    lives in a non-exported `com.miui.securitycenter` activity that
///    `url_launcher` can neither resolve (`canLaunchUrl` is subject to
///    Android 11+ package-visibility filtering) nor target. [MainActivity]
///    fires the component intent directly, where `startActivity` is not
///    filtered.
/// 2. **permission_handler's `openAppSettings`** — opens the App Info page
///    via `Settings.ACTION_APPLICATION_DETAILS_SETTINGS`, which works on
///    every supported Android version and needs no `<queries>` declaration.
/// 3. **The native battery chain** (see MainActivity.openMiuiBatterySettings)
///    — MIUI's per-app PowerKeeper page first, then the AOSP
///    "ignore battery optimizations" prompt for stock-ROM builds, then App
///    Info. The permission_handler request path is deliberately not used for
///    this step: MIUI suppresses the AOSP dialog, and its request can
///    resolve instantly with no visible UI on Xiaomi builds.
///
/// The OEM-specific methods (Samsung/Huawei/OnePlus/Oppo) collapse onto 2+3:
/// those skins expose their per-app controls through App Info, and none of
/// their private activities have stable public intents.
class BrandSettings {
  BrandSettings._();

  /// Best-effort Android package name: asks the platform first, falling back
  /// to the build-time constant when the channel is unavailable (tests,
  /// desktop debugging).
  static Future<String> resolvePackageName() async {
    try {
      final name = await _packageChannel.invokeMethod<String>('getPackageName');
      if (name != null && name.isNotEmpty) return name;
    } catch (e) {
      debugPrint('[BrandSettings] getPackageName failed, using default: $e');
    }
    return AppConstants.packageName;
  }

  // ── MIUI (Xiaomi / Redmi / POCO) ────────────────────────────────

  /// Opens MIUI's Autostart management page via the native channel,
  /// falling back to the App Info page when the deep link is unavailable.
  static Future<bool> openAutostartSettings(String packageName) async {
    final native = nativeAutostartOverride;
    if (native != null) {
      try {
        final ok = await native();
        return ok || await _openAppInfo();
      } catch (e) {
        debugPrint('[BrandSettings] Native autostart override failed: $e');
        return _openAppInfo();
      }
    }

    try {
      final ok = await _packageChannel.invokeMethod<bool>('openMiuiAutostart');
      if (ok == true) return true;
    } on MissingPluginException {
      debugPrint('[BrandSettings] openMiuiAutostart channel unavailable.');
    } on PlatformException catch (e) {
      debugPrint('[BrandSettings] openMiuiAutostart failed: ${e.code}');
    }
    return _openAppInfo();
  }

  /// Battery saver / background activity.
  ///
  /// Native-first (see MainActivity.openMiuiBatterySettings): the MIUI
  /// PowerKeeper per-app page, then the AOSP prompt, then App Info — every
  /// step launching something the user actually sees, unlike the
  /// permission_handler request which can resolve silently on MIUI. A short
  /// timeout guards the channel so a wedged platform response can never
  /// leave the button dead again.
  static Future<bool> openBatterySettings(String packageName) async {
    final native = nativeBatteryOverride;
    if (native != null) {
      try {
        return await native() || await _openAppInfo();
      } catch (e) {
        debugPrint('[BrandSettings] Native battery override failed: $e');
        return _openAppInfo();
      }
    }

    try {
      final ok = await _packageChannel
          .invokeMethod<bool>('openMiuiBatterySettings')
          .timeout(const Duration(seconds: 5));
      if (ok == true) return true;
    } on MissingPluginException {
      debugPrint(
        '[BrandSettings] openMiuiBatterySettings channel unavailable.',
      );
    } on PlatformException catch (e) {
      debugPrint('[BrandSettings] openMiuiBatterySettings failed: ${e.code}');
    } catch (e) {
      // TimeoutException and friends — never leave the button silent.
      debugPrint('[BrandSettings] openMiuiBatterySettings did not answer: $e');
    }
    return _openAppInfo();
  }

  // ── Samsung (One UI) ─────────────────────────────────────────────

  static Future<bool> openSamsungBatterySettings(String packageName) =>
      openBatterySettings(packageName);

  static Future<bool> openSamsungBatteryOptimization(String packageName) =>
      openBatterySettings(packageName);

  // ── Huawei (EMUI) ────────────────────────────────────────────────

  static Future<bool> openHuaweiAppLaunch(String packageName) =>
      openBatterySettings(packageName);

  static Future<bool> openHuaweiBatteryOptimization(String packageName) =>
      openBatterySettings(packageName);

  // ── OnePlus (OxygenOS) ───────────────────────────────────────────

  static Future<bool> openOnePlusAutoLaunch(String packageName) =>
      openBatterySettings(packageName);

  static Future<bool> openOnePlusBatterySettings(String packageName) =>
      openBatterySettings(packageName);

  // ── Oppo / Realme (ColorOS) ──────────────────────────────────────

  static Future<bool> openOppoStartupManager(String packageName) =>
      openBatterySettings(packageName);

  static Future<bool> openOppoBatterySettings(String packageName) =>
      openBatterySettings(packageName);

  // ── Generic ──────────────────────────────────────────────────────

  /// Open the standard App Info page (works on all Android devices).
  static Future<bool> openAppSettings(String packageName) => _openAppInfo();

  /// Open standard Android battery optimization settings. Delegates to the
  /// native battery chain (PowerKeeper page → AOSP prompt → App Info).
  static Future<bool> openBatteryOptimizationSettings() =>
      openBatterySettings(AppConstants.packageName);

  // ── Launch mechanisms ────────────────────────────────────────────

  static Future<bool> _openAppInfo() async {
    final override = openAppInfoOverride;
    if (override != null) {
      try {
        await override();
        return true;
      } catch (e) {
        debugPrint('[BrandSettings] App Info launch failed: $e');
        return false;
      }
    }
    try {
      // permission_handler's App Info page: ACTION_APPLICATION_DETAILS_
      // SETTINGS via platform channel — immune to the `<queries>`
      // package-visibility filtering that silently broke the old
      // `canLaunchUrl('package:…')` path on Android 11+.
      await ph.openAppSettings();
      return true;
    } catch (e) {
      debugPrint('[BrandSettings] openAppSettings failed: $e');
      return false;
    }
  }
}
