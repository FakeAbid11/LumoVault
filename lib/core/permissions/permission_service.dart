/// Well-defined permission status types matching Android's actual states.
enum PermissionStatus {
  /// Permission is fully granted.
  granted,

  /// Permission is denied by the user.
  denied,

  /// Permission is permanently denied — user must go to app settings.
  permanentlyDenied,

  /// Limited/partial access granted (Android 14+ "select photos").
  limited,

  /// Permission has not been requested yet.
  notDetermined,
}

/// Result of a permission request operation.
class PermissionRequestResult {
  const PermissionRequestResult({
    required this.status,
    required this.previousStatus,
  });

  /// The current status after the request.
  final PermissionStatus status;

  /// The status before the request was made.
  final PermissionStatus previousStatus;

  /// Whether the status changed as a result of the request.
  bool get changed => status != previousStatus;
}

/// Abstract permission service interface.
///
/// Defines the contract for checking and requesting permissions.
/// The real implementation wraps the permission_handler plugin.
abstract class PermissionService {
  /// Check the current status of media (photos/videos) permission.
  Future<PermissionStatus> checkMediaPermissionStatus();

  /// Check the current status of notification permission.
  Future<PermissionStatus> checkNotificationPermissionStatus();

  /// Check whether battery optimization is disabled (not restricted).
  Future<bool> isBatteryOptimizationDisabled();

  /// Request media (photos/videos) permission from the user.
  ///
  /// Returns the resulting status after the request.
  Future<PermissionRequestResult> requestMediaPermission();

  /// Request notification permission from the user.
  ///
  /// Returns the resulting status after the request.
  Future<PermissionRequestResult> requestNotificationPermission();

  /// Request to ignore battery optimizations.
  ///
  /// Returns true if the user granted the request.
  Future<bool> requestIgnoreBatteryOptimizations();

  /// Open the app settings page so the user can manually grant permissions.
  ///
  /// Returns true if the settings page was opened successfully.
  Future<bool> openAppSettings();

  /// Check all critical permissions and return a combined status.
  ///
  /// Returns true only if all critical permissions are granted or limited.
  Future<bool> areAllCriticalPermissionsGranted();

  /// Stream that emits whenever permission statuses may have changed.
  ///
  /// Useful for reacting to permission revocations from system settings.
  Stream<void> get onPermissionsChanged;
}
