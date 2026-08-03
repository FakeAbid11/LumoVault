import 'dart:async';

import 'package:permission_handler/permission_handler.dart' as ph;

import 'permission_service.dart';

/// Real implementation of [PermissionService] wrapping the permission_handler plugin.
class PermissionHandlerService implements PermissionService {
  PermissionHandlerService({PermissionHandler? permissionHandler})
    : _handler = permissionHandler ?? const PermissionHandler();

  final PermissionHandler _handler;

  /// Internal controller for permission change events.
  final _changeController = StreamController<void>.broadcast();

  @override
  Stream<void> get onPermissionsChanged => _changeController.stream;

  @override
  Future<PermissionStatus> checkMediaPermissionStatus() async {
    // On Android 13+ (API 33+), check granular media permissions.
    final imagesStatus = await _handler.checkPermission(ph.Permission.photos);
    final videoStatus = await _handler.checkPermission(ph.Permission.videos);

    // If either is limited, treat as limited.
    if (imagesStatus == ph.PermissionStatus.limited ||
        videoStatus == ph.PermissionStatus.limited) {
      return PermissionStatus.limited;
    }

    // If both are granted, we're good.
    if (imagesStatus == ph.PermissionStatus.granted &&
        videoStatus == ph.PermissionStatus.granted) {
      return PermissionStatus.granted;
    }

    // Check if either is permanently denied.
    if (imagesStatus == ph.PermissionStatus.permanentlyDenied ||
        videoStatus == ph.PermissionStatus.permanentlyDenied) {
      return PermissionStatus.permanentlyDenied;
    }

    // Check if either is denied.
    if (imagesStatus == ph.PermissionStatus.denied ||
        videoStatus == ph.PermissionStatus.denied) {
      return PermissionStatus.denied;
    }

    // Check if not yet determined (restricted/limited).
    if (imagesStatus == ph.PermissionStatus.restricted ||
        videoStatus == ph.PermissionStatus.restricted) {
      return PermissionStatus.notDetermined;
    }

    return PermissionStatus.denied;
  }

  @override
  Future<PermissionStatus> checkNotificationPermissionStatus() async {
    final status = await _handler.checkPermission(ph.Permission.notification);
    return _mapPermissionStatus(status);
  }

  @override
  Future<bool> isBatteryOptimizationDisabled() async {
    final status = await _handler.checkPermission(
      ph.Permission.ignoreBatteryOptimizations,
    );
    return status == ph.PermissionStatus.granted;
  }

  @override
  Future<PermissionRequestResult> requestMediaPermission() async {
    final previousStatus = await checkMediaPermissionStatus();

    // Request both photos and videos permissions.
    final results = await _handler.request([
      ph.Permission.photos,
      ph.Permission.videos,
    ]);

    final imagesResult =
        results[ph.Permission.photos] ?? ph.PermissionStatus.denied;
    final videosResult =
        results[ph.Permission.videos] ?? ph.PermissionStatus.denied;

    PermissionStatus newStatus;

    // Determine combined status.
    if (imagesResult == ph.PermissionStatus.limited ||
        videosResult == ph.PermissionStatus.limited) {
      newStatus = PermissionStatus.limited;
    } else if (imagesResult == ph.PermissionStatus.granted &&
        videosResult == ph.PermissionStatus.granted) {
      newStatus = PermissionStatus.granted;
    } else if (imagesResult == ph.PermissionStatus.permanentlyDenied ||
        videosResult == ph.PermissionStatus.permanentlyDenied) {
      newStatus = PermissionStatus.permanentlyDenied;
    } else {
      newStatus = PermissionStatus.denied;
    }

    _changeController.add(null);

    return PermissionRequestResult(
      status: newStatus,
      previousStatus: previousStatus,
    );
  }

  @override
  Future<PermissionRequestResult> requestNotificationPermission() async {
    final previousStatus = await checkNotificationPermissionStatus();
    final results = await _handler.request([ph.Permission.notification]);
    final result =
        results[ph.Permission.notification] ?? ph.PermissionStatus.denied;
    final newStatus = _mapPermissionStatus(result);

    _changeController.add(null);

    return PermissionRequestResult(
      status: newStatus,
      previousStatus: previousStatus,
    );
  }

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async {
    final results = await _handler.request([
      ph.Permission.ignoreBatteryOptimizations,
    ]);
    final result =
        results[ph.Permission.ignoreBatteryOptimizations] ??
        ph.PermissionStatus.denied;
    return result == ph.PermissionStatus.granted;
  }

  @override
  Future<bool> openAppSettings() async {
    return ph.openAppSettings();
  }

  @override
  Future<bool> areAllCriticalPermissionsGranted() async {
    final mediaStatus = await checkMediaPermissionStatus();
    return mediaStatus == PermissionStatus.granted ||
        mediaStatus == PermissionStatus.limited;
  }

  /// Maps a permission_handler PermissionStatus to our PermissionStatus.
  PermissionStatus _mapPermissionStatus(ph.PermissionStatus status) {
    if (status == ph.PermissionStatus.granted) return PermissionStatus.granted;
    if (status == ph.PermissionStatus.limited) return PermissionStatus.limited;
    if (status == ph.PermissionStatus.permanentlyDenied) {
      return PermissionStatus.permanentlyDenied;
    }
    if (status == ph.PermissionStatus.denied) return PermissionStatus.denied;
    if (status == ph.PermissionStatus.restricted) {
      return PermissionStatus.notDetermined;
    }
    return PermissionStatus.denied;
  }

  /// Dispose of resources.
  void dispose() {
    _changeController.close();
  }
}

/// Thin wrapper around permission_handler for testability.
///
/// This allows tests to mock the plugin calls without
/// relying on platform channels.
class PermissionHandler {
  const PermissionHandler();

  Future<ph.PermissionStatus> checkPermission(ph.Permission permission) {
    return permission.status;
  }

  Future<Map<ph.Permission, ph.PermissionStatus>> request(
    List<ph.Permission> permissions,
  ) async {
    final results = <ph.Permission, ph.PermissionStatus>{};
    for (final permission in permissions) {
      results[permission] = await permission.request();
    }
    return results;
  }
}
