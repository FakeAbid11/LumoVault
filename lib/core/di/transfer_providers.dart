import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/gallery/data/repositories/telegram_upload_service.dart';
import 'tdlib_providers.dart';

/// Provider for upload service.
///
/// The service owns a broadcast StreamController, so it has to be torn down
/// with the provider. This watches the connection manager, meaning a reconnect
/// rebuilds it — without onDispose every rebuild stranded the previous
/// controller and its listeners for the life of the process.
final uploadServiceProvider = Provider<UploadService>((ref) {
  final manager = ref.watch(tdLibConnectionManagerProvider);
  final service = TelegramUploadService(manager: manager);
  ref.onDispose(service.dispose);
  return service;
});
