import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';

/// Provides the singleton [AppDatabase].
///
/// Overridden in [main] with the instance opened during bootstrap so the whole
/// app shares one connection. The fallback constructor here keeps the provider
/// usable in tests that don't perform the bootstrap override.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
