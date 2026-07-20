/// Database-related constants.
abstract final class DatabaseConstants {
  /// Isar database name.
  static const String databaseName = 'lumovault';

  /// Schema version for migration tracking.
  static const int schemaVersion = 1;

  /// Maximum database size in bytes (1GB).
  static const int maxDatabaseSizeBytes = 1024 * 1024 * 1024;
}
