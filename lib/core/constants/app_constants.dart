/// Application-wide constants.
abstract final class AppConstants {
  /// App name displayed in UI.
  static const String appName = 'LumoVault';

  /// App description.
  static const String appDescription =
      'Original quality photo and video backup powered by Telegram.';

  /// Package name for Android.
  static const String packageName = 'com.lumovault.app';

  /// Current schema version for metadata migration.
  static const int schemaVersion = 1;

  /// Maximum number of retry attempts for failed uploads.
  static const int maxRetryAttempts = 5;

  /// Default upload batch size.
  static const int defaultUploadBatchSize = 10;

  /// Default delay between uploads in milliseconds.
  static const int defaultUploadDelayMs = 2000;

  /// Thumbnail cache size in megabytes.
  static const int thumbnailCacheSizeMB = 200;

  /// Maximum number of thumbnails in memory cache.
  static const int maxMemoryCacheSize = 100;

  /// Items to load per page in gallery.
  static const int galleryPageSize = 100;

  /// Threshold for triggering next page load (items from bottom).
  static const int galleryLoadThreshold = 20;

  /// Maximum file size for upload (2GB in bytes).
  static const int maxFileSizeBytes = 2 * 1024 * 1024 * 1024;

  /// Trash auto-delete duration in days.
  static const int trashRetentionDays = 30;

  /// Media scanner interval in minutes.
  static const int mediaScannerIntervalMinutes = 15;
}
