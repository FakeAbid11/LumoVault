import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/diagnostics_service.dart';
import '../notifications/notification_service.dart';
import '../security/biometric_service.dart';
import '../storage/thumbnail_cache.dart';
import '../storage/transfer_queue_persistence.dart';
import 'gallery_providers.dart';

/// Notification service singleton provider.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  ref.onDispose(() => service.cancelAll());
  return service;
});

/// Biometric service singleton provider.
final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

/// Transfer queue persistence singleton provider.
final transferQueuePersistenceProvider = Provider<TransferQueuePersistence>((
  ref,
) {
  return TransferQueuePersistence.instance;
});

/// Diagnostics service provider.
final diagnosticsServiceProvider = Provider<DiagnosticsService>((ref) {
  final gallery = ref.read(galleryRepositoryProvider);
  return DiagnosticsService(galleryRepository: gallery);
});

/// Thumbnail cache singleton provider.
final thumbnailCacheProvider = Provider<ThumbnailCache>((ref) {
  return ThumbnailCache.instance;
});
