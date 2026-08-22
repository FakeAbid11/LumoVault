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
  ///
  /// v4: added favorites and trash indexes on MediaItems (is_favorite,
  /// is_trashed + trashed_at composite).
  ///
  /// v5: added latitude/longitude columns on MediaItems so the Map tab can
  /// plot photos by their GPS EXIF location.
  ///
  /// v6: added is_location_user_set flag so manually-set coordinates survive
  /// rescans (EXIF-derived coordinates are still overwritten on rescan).
  static const int schemaVersion = 6;

  /// Maximum database size in bytes (1GB).
  static const int maxDatabaseSizeBytes = 1024 * 1024 * 1024;
}
