import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'device_info_service.dart';
import 'miui_settings.dart';

/// Checks whether MIUI background restrictions are likely blocking backups
/// and shows a warning if so.
///
/// This is not a definitive check (MIUI doesn't expose autostart or
/// battery-saver-per-app status via APIs), so we use heuristics: if the
/// device is MIUI, auto-backup is enabled, but no backup has completed in
/// over 24 hours, the user is probably affected by MIUI restrictions.
class MiuiHealthCheck {
  MiuiHealthCheck._();

  /// Threshold after which we consider background backup stalled.
  static const _staleThreshold = Duration(hours: 24);

  /// Whether the device is MIUI and background backup appears blocked.
  ///
  /// [isMiuiDevice] — from [DeviceInfoService.isMiuiDevice].
  /// [isAutoBackupEnabled] — user setting.
  /// [lastBackupAt] — from [BackupStats.lastBackupAt].
  static bool isLikelyRestricted({
    required bool isMiuiDevice,
    required bool isAutoBackupEnabled,
    required DateTime? lastBackupAt,
  }) {
    if (!isMiuiDevice || !isAutoBackupEnabled) return false;
    if (lastBackupAt == null) {
      // Never backed up — might be fine (first run) or blocked.
      // Only flag if auto-backup has been on for a while without any backup.
      return false;
    }
    return DateTime.now().difference(lastBackupAt) > _staleThreshold;
  }

  /// Show a Material banner at the top of a Scaffold for MIUI warnings.
  ///
  /// Call this from a build method when [isLikelyRestricted] returns true.
  static Widget buildWarningBanner({
    required BuildContext context,
    required String packageName,
    VoidCallback? onDismissed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return MaterialBanner(
      content: Text(
        'Background backup hasn\'t run recently. On Xiaomi/Redmi devices, '
        'MIUI may be blocking background activity.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      leading: Icon(Symbols.warning, color: colorScheme.error),
      actions: [
        TextButton(
          onPressed: () => MiuiSettings.openBatterySettings(packageName),
          child: const Text('Open Settings'),
        ),
        if (onDismissed != null)
          TextButton(onPressed: onDismissed, child: const Text('Dismiss')),
      ],
    );
  }
}
