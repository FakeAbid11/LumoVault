import 'package:flutter/services.dart';

/// Shared fallback copy for every settings-launch failure: the button
/// surfaces a snackbar telling the user to navigate manually.
const String kSettingsLaunchFallbackHint =
    'Could not open settings. Please navigate manually.';

/// Brand-specific launchers for OEM background-permission pages.
///
/// All launches go through the native `lumo.app/settings` channel:
/// url_launcher can never have worked here — it builds plain ACTION_VIEW
/// intents and never calls `Intent.parseUri`, so the old `intent:#Intent;
/// component=…` "deep links" matched nothing, and `package:` URIs gated by
/// `canLaunchUrl` are refused by Android 11+ package visibility. That
/// combination made every MIUI button fall through to the manual
/// instructions — the exact bug this rewrite fixes.
///
/// Each OEM entry walks a candidate chain that always ends at the app's
/// system App-Info page: a button opens something real or fails honestly,
/// never a silently dead end.
class BrandSettings {
  BrandSettings._();

  static const MethodChannel _settings = MethodChannel('lumo.app/settings');
  static const MethodChannel _app = MethodChannel('lumo.app/package');

  /// MIUI Security Center package (autostart manager + permission editor).
  static const String _miuiSecurityCenter = 'com.miui.securitycenter';

  /// MIUI battery package (per-app "HiddenApps" configuration).
  static const String _miuiPowerkeeper = 'com.miui.powerkeeper';

  /// MIUI's public permission-editor action for a single app.
  static const String _miuiPermEditorAction =
      'miui.intent.action.APP_PERM_EDITOR';

  /// Fallback constant for environments without the channel (unit tests,
  /// non-Android hosts). Production reads the real applicationId natively.
  static const String _fallbackPackageName = 'com.lumovault.app';

  /// The app's package name, resolved from the platform so renamed or
  /// flavored builds still open the RIGHT system pages.
  static Future<String> resolvePackageName() async {
    try {
      final name = await _app.invokeMethod<String>('getPackageName');
      return name ?? _fallbackPackageName;
    } on MissingPluginException {
      return _fallbackPackageName;
    } on PlatformException {
      return _fallbackPackageName;
    }
  }

  static Future<bool> _launchComponent(
    String packageName,
    String activity, {
    String? action,
    Map<String, String>? extras,
  }) async {
    try {
      final launched = await _settings.invokeMethod<bool>('launchComponent', {
        'package': packageName,
        'activity': activity,
        if (action != null) 'action': action,
        if (extras != null) 'extras': extras,
      });
      return launched ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> _openAppDetails(String packageName) async {
    try {
      final launched = await _settings.invokeMethod<bool>('openAppDetails', {
        'package': packageName,
      });
      return launched ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// MIUI per-app permission editor via action intent (activity left empty
  /// so the native side uses setPackage instead of a component).
  static Future<bool> _openMiuiPermEditor(
    String packageName,
    String extraKey,
  ) => _launchComponent(
    _miuiSecurityCenter,
    '',
    action: _miuiPermEditorAction,
    extras: {extraKey: packageName},
  );

  // ── MIUI (Xiaomi / Redmi / POCO) ────────────────────────────────

  /// Open MIUI's Security Center → Autostart manager.
  ///
  /// Chain: the explicit AutoStartManagementActivity component, then the
  /// permission-editor action with both historically-shipped extra names,
  /// then App Info as the floor.
  static Future<bool> openAutostartSettings(String packageName) async {
    if (await _launchComponent(
      _miuiSecurityCenter,
      'com.miui.permcenter.autostart.AutoStartManagementActivity',
    )) {
      return true;
    }
    if (await _openMiuiPermEditor(packageName, 'extra_pkgname')) return true;
    if (await _openMiuiPermEditor(packageName, 'pkgname')) return true;
    return _openAppDetails(packageName);
  }

  /// Open MIUI's per-app battery saver configuration.
  ///
  /// The activity lives in com.miui.powerkeeper on current MIUI and was
  /// hosted by the Security Center package on older builds — try both,
  /// then the permission editor, then App Info.
  static Future<bool> openBatterySettings(String packageName) async {
    final extras = {'package_name': packageName, 'packageLabel': packageName};
    if (await _launchComponent(
      _miuiPowerkeeper,
      'com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
      extras: extras,
    )) {
      return true;
    }
    if (await _launchComponent(
      _miuiSecurityCenter,
      'com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
      extras: extras,
    )) {
      return true;
    }
    if (await _openMiuiPermEditor(packageName, 'extra_pkgname')) return true;
    return _openAppDetails(packageName);
  }

  // ── Other OEMs ───────────────────────────────────────────────────
  //
  // Samsung/Huawei/OnePlus/Oppo deep-link components are not publicly
  // documented and change per ROM build; the previous "candidates" here
  // were all the same package:.../details URI twice over. App Info is the
  // honest, working landing — the step instructions on each screen spell
  // out the rest of the path from there.

  static Future<bool> openSamsungBatterySettings(String packageName) =>
      _openAppDetails(packageName);

  static Future<bool> openHuaweiAppLaunch(String packageName) =>
      _openAppDetails(packageName);

  static Future<bool> openHuaweiBatteryOptimization(String packageName) =>
      _openAppDetails(packageName);

  static Future<bool> openOnePlusAutoLaunch(String packageName) =>
      _openAppDetails(packageName);

  static Future<bool> openOnePlusBatterySettings(String packageName) =>
      _openAppDetails(packageName);

  static Future<bool> openOppoStartupManager(String packageName) =>
      _openAppDetails(packageName);

  static Future<bool> openOppoBatterySettings(String packageName) =>
      _openAppDetails(packageName);

  // ── Generic ──────────────────────────────────────────────────────

  /// Open the standard system App-Info page (works on all Android devices).
  ///
  /// Deliberately NOT gated by `canLaunchUrl`: on Android 11+ it is
  /// package-visibility restricted and returned false for these very
  /// launches, which is half of why every button "went manual".
  static Future<bool> openAppSettings(String packageName) =>
      _openAppDetails(packageName);

  /// Open the stock Android battery-optimization exemption list
  /// (`ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`) — a screen
  /// `package:` URIs could not express at all; the native side falls back
  /// to this app's details when the ROM lacks the global list.
  static Future<bool> openBatteryOptimizationSettings() async {
    try {
      final launched = await _settings.invokeMethod<bool>(
        'openBatteryOptimizations',
      );
      return launched ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
