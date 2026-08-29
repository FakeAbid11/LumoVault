import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Helper to open MIUI-specific settings pages.
///
/// MIUI uses proprietary settings screens that are not accessible via
/// standard Android intents. These helpers try multiple URI formats
/// across MIUI versions (12/13/14/HyperOS) with graceful fallbacks.
class MiuiSettings {
  MiuiSettings._();

  /// URI formats for MIUI battery settings, tried in order.
  /// Different MIUI/HyperOS versions use different activity paths.
  static final _batteryUris = <String Function(String)>[
    // MIUI 14+ / HyperOS — settings fragment
    (pkg) => 'package:$pkg/details#power',
    // MIUI 12/13 — dedicated battery activity
    (pkg) => 'package:$pkg/details',
    // Stock Android — battery optimization intent
    (pkg) =>
        'package:$pkg/details'
        '?android:show_fragment=com.android.settings.fuelgauge'
        '.BatteryOptimizeSettings',
  ];

  /// URI formats for MIUI autostart settings.
  static final _autostartUris = <String Function(String)>[
    // MIUI 14+ / HyperOS
    (pkg) => 'package:$pkg/details',
    // MIUI 12/13 autostart manager
    (pkg) => 'package:$pkg/details?autostart=true',
  ];

  /// Open the app-specific battery settings on MIUI.
  ///
  /// Tries multiple URI formats for different MIUI versions,
  /// falling back to standard Android app settings.
  static Future<bool> openBatterySettings(String packageName) async {
    for (final uriBuilder in _batteryUris) {
      try {
        final uri = Uri.parse(uriBuilder(packageName));
        if (await canLaunchUrl(uri)) {
          return launchUrl(uri);
        }
      } catch (_) {}
    }
    return openAppSettings(packageName);
  }

  /// Open the autostart settings on MIUI.
  ///
  /// Tries multiple URI formats for different MIUI versions,
  /// falling back to standard Android app settings.
  static Future<bool> openAutostartSettings(String packageName) async {
    for (final uriBuilder in _autostartUris) {
      try {
        final uri = Uri.parse(uriBuilder(packageName));
        if (await canLaunchUrl(uri)) {
          return launchUrl(uri);
        }
      } catch (_) {}
    }
    return openAppSettings(packageName);
  }

  /// Open the standard Android app settings page.
  static Future<bool> openAppSettings(String packageName) async {
    try {
      final uri = Uri.parse('package:$packageName/details');
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri);
      }
      // Last resort: Android application details in Settings app
      final fallback = Uri.parse(
        'android:application-details?package=$packageName',
      );
      return launchUrl(fallback);
    } catch (e) {
      return false;
    }
  }

  /// Open the MIUI battery saver settings.
  static Future<bool> openBatterySaverSettings() async {
    const uris = [
      'package:com.miui.powerkeeper/details',
      'package:com.miui.powerkeeper/details#power',
    ];
    for (final uriStr in uris) {
      try {
        final uri = Uri.parse(uriStr);
        if (await canLaunchUrl(uri)) {
          return launchUrl(uri);
        }
      } catch (_) {}
    }
    return false;
  }

  /// Get the package name of the current app.
  ///
  /// Uses a method channel to retrieve the package name from the native side.
  static Future<String?> getPackageName() async {
    try {
      const channel = MethodChannel('lumo.app/package');
      return await channel.invokeMethod<String>('getPackageName');
    } catch (e) {
      return null;
    }
  }
}
