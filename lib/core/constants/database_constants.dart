/// Database-related constants.
abstract final class DatabaseConstants {
  /// Drift (SQLite) database name.
  static const String databaseName = 'lumovault';

  /// Schema version for migration tracking.
  ///
  /// v2: removed the UploadTasks drift table.
  /// v3: added query hot-path indexes on MediaItems.
  /// v4: added favorites and trash indexes on MediaItems.
  /// v5: added latitude/longitude columns on MediaItems.
  /// v6: added is_location_user_set flag.
  /// v7: added Faces, People, FacePersons tables for People tab.
  /// v8: added face embedding column for face recognition.
  /// v9: added centroid embedding column to People for adaptive clustering.
  /// v10: cleared face data (192-dim → 512-dim InsightFace migration).
  /// v11: added FaceScans (per-photo scan bookkeeping) and cleared face data
  ///      again — embeddings produced before the SCRFD decode fix are junk.
  /// v12: cleared face data once more. Faces are now warped onto the ArcFace
  ///      5-point template before embedding, so embeddings from the earlier
  ///      unaligned crops are not comparable to new ones and would cluster
  ///      against them badly.
  /// v13: added ai_labels column for AI-powered image classification.
  /// v14: added Albums and AlbumItems tables for custom user-created albums.
  /// v15: added is_date_user_set flag to preserve user-edited capture dates.
  /// v16: added location_name column for reverse-geocoded place names.
  /// v17: added clip_embedding column for semantic search vectors.
  /// v18: cleared face data — capable devices now detect with SCRFD-2.5G
  ///      (500M elsewhere); detections from two different detectors cannot
  ///      be mixed, so People rebuilds from scratch under the tier's model.
  static const int schemaVersion = 18;

  /// Maximum database size in bytes (1GB).
  static const int maxDatabaseSizeBytes = 1024 * 1024 * 1024;
}
