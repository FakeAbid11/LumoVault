import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Permission status for media access.
final mediaPermissionProvider = FutureProvider<bool>((ref) async {
  final status = await Permission.photos.status;
  if (status.isGranted) return true;

  final result = await Permission.photos.request();
  return result.isGranted;
});

/// Permission status for notifications.
final notificationPermissionProvider = FutureProvider<bool>((ref) async {
  final status = await Permission.notification.status;
  if (status.isGranted) return true;

  final result = await Permission.notification.request();
  return result.isGranted;
});
