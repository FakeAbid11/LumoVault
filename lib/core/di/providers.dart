import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../permissions/permission_handler_service.dart';
import '../permissions/permission_service.dart';

/// Global providers for dependency injection.
///
/// All core services and providers are registered here.
/// Feature-specific providers live in their respective feature folders.

/// Theme mode provider.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// Connectivity status provider.
final connectivityProvider = StateProvider<bool>((ref) => true);

/// Current route location provider.
final currentRouteProvider = StateProvider<String>((ref) => '/timeline');

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
