import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_info_service.dart';
import '../permissions/permission_handler_service.dart';
import '../permissions/permission_service.dart';
import '../../shared/providers/connectivity_provider.dart';

/// Global providers for dependency injection.
///
/// All core services and providers are registered here.
/// Feature-specific providers live in their respective feature folders.

/// Connectivity status provider.
///
/// Derives from [isOnlineProvider] which uses [connectivityStreamProvider]
/// to track actual network state. Defaults to `true` while loading.
final connectivityProvider = Provider<bool>((ref) {
  return ref.watch(isOnlineProvider);
});

/// Current route location provider.
final currentRouteProvider = StateProvider<String>((ref) => '/local');

/// Permission service provider.
///
/// This is the primary way to access the permission service.
/// Can be overridden in tests with a mock implementation.
final permissionServiceProvider = Provider<PermissionService>((ref) {
  final service = PermissionHandlerService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Media permission status provider.
///
/// Watches the permission service and provides the current media permission status.
/// Automatically refreshes when permissions change.
final mediaPermissionStatusProvider = FutureProvider<PermissionStatus>((
  ref,
) async {
  final service = ref.watch(permissionServiceProvider);
  return service.checkMediaPermissionStatus();
});

/// Notification permission status provider.
final notificationPermissionStatusProvider = FutureProvider<PermissionStatus>((
  ref,
) async {
  final service = ref.watch(permissionServiceProvider);
  return service.checkNotificationPermissionStatus();
});

/// Whether all critical permissions are granted.
final criticalPermissionsGrantedProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(permissionServiceProvider);
  return service.areAllCriticalPermissionsGranted();
});

/// Device info service provider.
///
/// Used to detect device manufacturer and show device-specific guidance.
final deviceInfoServiceProvider = Provider<DeviceInfoService>((ref) {
  return DeviceInfoService();
});

/// Whether the current device is a Xiaomi/Redmi/POCO running MIUI.
final isMiuiDeviceProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(deviceInfoServiceProvider);
  return service.isMiuiDevice();
});
