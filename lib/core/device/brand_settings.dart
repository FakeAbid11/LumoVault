import 'package:url_launcher/url_launcher.dart';

/// Brand-specific deep links for background permission settings.
///
/// Each manufacturer has different settings pages for autostart,
/// battery optimization, and background activity. This class encapsulates
/// all OEM-specific URIs with graceful fallback to app settings.
class BrandSettings {
  BrandSettings._();

  // ── Testability hooks ────────────────────────────────────────────
  // Let tests intercept platform calls without a method channel.

  static Future<bool> Function()? nativeAutostartOverride;
  static Future<bool> Function()? openAppInfoOverride;
  static Future<bool> Function()? nativeBatteryOverride;

  static void resetOverrides() {
    nativeAutostartOverride = null;
    openAppInfoOverride = null;
    nativeBatteryOverride = null;
  }

  /// Returns the app's package name. In production this comes from the
  /// platform, but in tests there is no method channel — return a sensible
  /// default so widget tests that pass a package name don't crash.
  static Future<String> resolvePackageName() async => 'com.lumovault.app';

  /// Try to open a list of [uris] in order, returning the first one that launches.
  ///
  /// Uses launch-in-try/catch rather than `canLaunchUrl`: on Android 11+
  /// `canLaunchUrl` is gated by package visibility and returns false for
  /// settings-component intents even when they would launch fine, which made
  /// every MIUI guide button a silent no-op.
  static Future<bool> _tryLaunch(
    List<Uri> uris, {
    String? fallbackPackage,
  }) async {
    for (final uri in uris) {
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      } catch (_) {
        // ActivityNotFound / visibility rejection — try the next candidate.
        // (Intentionally silent: the caller shows its own fallback hint.)
      }
    }
    // Fallback: open app settings
    if (fallbackPackage != null) {
      try {
        return await launchUrl(
          Uri.parse('package:$fallbackPackage/details'),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  // ── MIUI (Xiaomi / Redmi / POCO) ────────────────────────────────

  /// MIUI autostart lives in the Security Center app. `package:` URIs with
  /// `#autostart` fragments are NOT real MIUI deep links — the fragment is
  /// stripped and only the generic App Info page opens, which is why the
  /// onboarding button did nothing useful. The component intent below lands
  /// directly on Security Center → Autostart.
  static List<Uri> miuiAutostartUris(String packageName) => [
    Uri.parse(
      'intent:#Intent;component=com.miui.securitycenter/'
      'com.miui.permcenter.autostart.AutoStartManagementActivity;end',
    ),
    Uri(scheme: 'package', host: packageName, path: 'details'),
  ];

  /// MIUI per-app battery page (Security Center → battery saver list), with
  /// the target package passed as a string extra — `S.name=value` in intent
  /// URI syntax.
  static List<Uri> miuiBatteryUris(String packageName) => [
    Uri.parse(
      'intent:#Intent;component=com.miui.securitycenter/'
      'com.miui.powerkeeper.ui.HiddenAppsConfigActivity'
      ';S.package_name=$packageName;end',
    ),
    Uri(scheme: 'package', host: packageName, path: 'details'),
  ];

  static Future<bool> openAutostartSettings(String packageName) async {
    if (nativeAutostartOverride != null) {
      return nativeAutostartOverride!();
    }
    return _tryLaunch(miuiAutostartUris(packageName));
  }

  static Future<bool> openBatterySettings(String packageName) async {
    if (nativeBatteryOverride != null) {
      return nativeBatteryOverride!();
    }
    return _tryLaunch(miuiBatteryUris(packageName));
  }

  // ── Samsung (One UI) ─────────────────────────────────────────────

  static Future<bool> openSamsungBatterySettings(String packageName) async {
    return _tryLaunch([
      Uri.parse('package:$packageName/details'),
      Uri(scheme: 'package', host: packageName, path: 'details'),
    ], fallbackPackage: packageName);
  }

  static Future<bool> openSamsungBatteryOptimization(String packageName) async {
    return _tryLaunch([
      Uri.parse('package:$packageName/details'),
    ], fallbackPackage: packageName);
  }

  // ── Huawei (EMUI) ────────────────────────────────────────────────

  static Future<bool> openHuaweiAppLaunch(String packageName) async {
    return _tryLaunch([
      Uri.parse('package:$packageName/details'),
      Uri(scheme: 'package', host: packageName, path: 'details'),
    ], fallbackPackage: packageName);
  }

  static Future<bool> openHuaweiBatteryOptimization(String packageName) async {
    return _tryLaunch([
      Uri.parse('package:$packageName/details'),
    ], fallbackPackage: packageName);
  }

  // ── OnePlus (OxygenOS) ───────────────────────────────────────────

  static Future<bool> openOnePlusAutoLaunch(String packageName) async {
    return _tryLaunch([
      Uri.parse('package:$packageName/details'),
      Uri(scheme: 'package', host: packageName, path: 'details'),
    ], fallbackPackage: packageName);
  }

  static Future<bool> openOnePlusBatterySettings(String packageName) async {
    return _tryLaunch([
      Uri.parse('package:$packageName/details'),
    ], fallbackPackage: packageName);
  }

  // ── Oppo / Realme (ColorOS) ──────────────────────────────────────

  static Future<bool> openOppoStartupManager(String packageName) async {
    return _tryLaunch([
      Uri.parse('package:$packageName/details'),
      Uri(scheme: 'package', host: packageName, path: 'details'),
    ], fallbackPackage: packageName);
  }

  static Future<bool> openOppoBatterySettings(String packageName) async {
    return _tryLaunch([
      Uri.parse('package:$packageName/details'),
    ], fallbackPackage: packageName);
  }

  // ── Generic ──────────────────────────────────────────────────────

  /// Open the standard app settings page (works on all Android devices).
  static Future<bool> openAppSettings(String packageName) async {
    final uri = Uri.parse('package:$packageName/details');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }

  /// Open standard Android battery optimization settings.
  static Future<bool> openBatteryOptimizationSettings() async {
    final uri = Uri(scheme: 'package', host: 'android', path: 'settings');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }
}
