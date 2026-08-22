import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/gallery/data/repositories/gallery_save_service.dart';

/// Provider for the gallery save service.
final gallerySaveServiceProvider = Provider<GallerySaveService>((ref) {
  return GallerySaveService();
});
