/// Database-related constants.
abstract final class DatabaseConstants {
  /// Drift (SQLite) database name.
  static const String databaseName = 'lumovault';

  /// Schema version for migration tracking.
  ///
  /// v2: removed the UploadTasks drift table (upload queue now persisted to
  /// JSON via TransferQueuePersistence instead of drift).
  ///
  /// v3: added query hot-path indexes on MediaItems (file_hash, status,
  /// album_name, created_at).
  static const int schemaVersion = 3;

  /// Maximum database size in bytes (1GB).
  static const int maxDatabaseSizeBytes = 1024 * 1024 * 1024;
}
