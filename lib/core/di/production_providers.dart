import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/data/models/app_settings.dart';
import '../../features/settings/presentation/providers/settings_providers.dart';
import '../diagnostics/diagnostics_service.dart';
import '../notifications/notification_service.dart';
import '../security/biometric_service.dart';
import '../security/pin_attempt_throttle.dart';
import '../security/pin_service.dart';
import '../storage/thumbnail_cache.dart';
import '../storage/transfer_queue_persistence.dart';
import 'gallery_providers.dart';

/// Notification service singleton provider.
///
/// Settings are pushed in with `listen` rather than `watch`: watching would
/// rebuild the service on every settings change, discarding its initialized
/// plugin state and re-creating the channels.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  service.updateSettings(ref.read(appSettingsProvider));
  ref.listen<AppSettings>(
    appSettingsProvider,
    (_, next) => service.updateSettings(next),
  );
  ref.onDispose(() => service.cancelAll());
  return service;
});

/// Biometric service singleton provider.
final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

/// PIN hashing/verification service provider.
final pinServiceProvider = Provider<PinService>((ref) {
  return PinService();
});

/// PIN brute-force throttle provider.
final pinAttemptThrottleProvider = Provider<PinAttemptThrottle>((ref) {
  return PinAttemptThrottle();
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
