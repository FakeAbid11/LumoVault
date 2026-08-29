import 'package:url_launcher/url_launcher.dart';

/// Brand-specific deep links for background permission settings.
///
/// Each manufacturer has different settings pages for autostart,
/// battery optimization, and background activity. This class encapsulates
/// all OEM-specific URIs with graceful fallback to app settings.
class BrandSettings {
  BrandSettings._();

  /// Try to open a list of [uris] in order, returning the first one that launches.
  /// Falls back to the app's own settings page if none work.
  static Future<bool> _tryLaunch(
    List<Uri> uris, {
    String? fallbackPackage,
  }) async {
    for (final uri in uris) {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
    }
    // Fallback: open app settings
    if (fallbackPackage != null) {
      final fallback = Uri.parse('package:$fallbackPackage/details');
      if (await canLaunchUrl(fallback)) {
        await launchUrl(fallback, mode: LaunchMode.externalApplication);
        return true;
      }
    }
    return false;
  }

  // ── MIUI (Xiaomi / Redmi / POCO) ────────────────────────────────

  static Future<bool> openAutostartSettings(String packageName) async {
    return _tryLaunch([
      Uri.parse('package:$packageName/details#autostart'),
      Uri(scheme: 'package', host: packageName, path: 'details'),
    ], fallbackPackage: packageName);
  }

  static Future<bool> openBatterySettings(String packageName) async {
    return _tryLaunch([
      Uri.parse('package:$packageName/details#power'),
      Uri(scheme: 'package', host: packageName, path: 'details'),
    ], fallbackPackage: packageName);
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
