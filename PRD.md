# LumoVault — Product Requirements Document

**Version:** 1.0
**Date:** July 2026
**Status:** Draft
**Classification:** Internal

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Product Vision](#2-product-vision)
3. [Technical Architecture](#3-technical-architecture)
4. [Project Structure](#4-project-structure)
5. [Database Schema](#5-database-schema)
6. [Metadata System](#6-metadata-system)
7. [Feature Specifications](#7-feature-specifications)
8. [UI/UX Design](#8-uiux-design)
9. [Backup Engine](#9-backup-engine)
10. [Restore Engine](#10-restore-engine)
11. [Security](#11-security)
12. [Performance Targets](#12-performance-targets)
13. [CI/CD Pipeline](#13-cicd-pipeline)
14. [Error Handling](#14-error-handling)
15. [Roadmap](#15-roadmap)
16. [Appendix](#16-appendix)

---

## 1. Executive Summary

LumoVault is a production-ready mobile application that backs up photos and videos to Telegram's cloud storage, delivering a Google Photos-like experience without requiring self-hosted infrastructure. The app leverages TDLib (Telegram Database Library) to communicate directly with Telegram's API, using the user's own Telegram account as the storage backend.

**Core value proposition:** Original quality photo/video backup with beautiful browsing, fully automatic, zero technical knowledge required.

**Key differentiators from existing solutions:**

| Feature | Google Photos | Immich | LumoVault |
|---------|--------------|--------|-----------|
| Cloud storage | Google servers | Self-hosted | Telegram (user's account) |
| Original quality | Paid (15GB free) | Unlimited (self-hosted) | Unlimited (Telegram cloud) |
| Self-hosted required | No | Yes | No |
| Open source | No | Yes | Yes |
| Cost | Subscription | Hardware + hosting | Free (or Telegram Premium) |

---

## 2. Product Vision

### 2.1 Mission Statement

Make personal photo and video backup accessible, free, and beautiful — using Telegram as invisible infrastructure.

### 2.2 Design Principles

1. **Invisible infrastructure** — User never sees or interacts with Telegram directly
2. **Offline-first** — All browsing and search works without internet
3. **Original quality** — No compression, no quality loss, ever
4. **Automatic** — Backup happens silently in the background
5. **Beautiful** — Material 3 design, smooth animations, timeline-first browsing

### 2.3 Target Users

- Primary: Android users who want free, reliable photo backup
- Secondary: Privacy-conscious users who prefer owning their storage
- Tertiary: Users migrating from Google Photos who want to avoid subscription fees

### 2.4 Success Metrics

| Metric | Target |
|--------|--------|
| Backup completion rate | > 95% of selected media |
| Median backup time (100 photos) | < 5 minutes on Wi-Fi |
| App cold start to gallery visible | < 1.5 seconds |
| Timeline scroll FPS (50K photos) | > 55 FPS |
| Crash-free sessions | > 99.5% |
| User retention (D7) | > 40% |

---

## 3. Technical Architecture

### 3.1 Technology Stack

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| **Framework** | Flutter 3.44+ | Single codebase, Material 3 native support |
| **Language** | Dart 3.5+ | Null safety, sound typing, isolates |
| **UI** | Material 3 (Material You) | Dynamic color, adaptive components |
| **Local Database** | Isar 3.1.x | Fast NoSQL, Flutter-native, watchers, full-text search |
| **Telegram Client** | TDLib (via `tdlib` package v1.6.0+) | Full Telegram client capabilities, 2GB file limit |
| **Background Work** | `workmanager` + `flutter_background_service_android` | Periodic sync, foreground service for active uploads |
| **State Management** | Riverpod 2.x | Compile-time safety, dependency injection, scalable |
| **Navigation** | GoRouter | Declarative routing, deep link support |
| **Image Loading** | `cached_network_image` + custom thumbnail pipeline | Aggressive caching, lazy loading |
| **Secure Storage** | `flutter_secure_storage` | Encrypted keychain storage for TDLib credentials |
| **Permissions** | `permission_handler` | Unified permission API |
| **DI** | Riverpod (built-in) | Provider-based dependency injection |

### 3.2 Architecture Pattern

**Clean Architecture with Feature-Based Organization**

```
+---------------------------------------------+
|                 PRESENTATION                 |
|  +---------+  +----------+  +------------+  |
|  | Screens |  | Widgets  |  |  Providers |  |
|  +---------+  +----------+  +------------+  |
+---------------------------------------------+
|                 DOMAIN                       |
|  +----------+  +-----------+  +----------+  |
|  | Entities |  | Use Cases |  | Repo Intf|  |
|  +----------+  +-----------+  +----------+  |
+---------------------------------------------+
|                  DATA                        |
|  +----------+  +-----------+  +----------+  |
|  | Isar DB  |  | TDLib     |  | File Sys |  |
|  | Models   |  | Service   |  | Cache    |  |
|  +----------+  +-----------+  +----------+  |
+---------------------------------------------+
```

### 3.3 State Management Strategy

Riverpod providers organized by layer:

```
State Providers
  AuthState          -- Login status, user info
  GalleryState       -- Timeline data, scroll position
  BackupState        -- Upload queue, progress, stats
  SettingsState      -- User preferences
  ConnectivityState  -- Online/offline status

Service Providers
  TDLibClientProvider    -- TDLib client instance
  DatabaseProvider       -- Isar instance
  BackupEngineProvider   -- Backup orchestrator
  RestoreEngineProvider  -- Restore orchestrator
  CacheManagerProvider   -- Thumbnail cache
  ScannerProvider        -- Media scanner
  WorkManagerProvider    -- Background scheduler
```

### 3.4 Dependency Injection

Riverpod handles all DI. No third-party DI framework needed.

```
Main
  ProviderScope (Riverpod root)
    DatabaseProvider (Isar, async)
    TDLibClientProvider (TDLib, async)
    SecureStorageProvider
    BackupEngineProvider
    RestoreEngineProvider
    MediaScannerProvider
    CacheManagerProvider
    ThemeProvider
  MyApp
    MaterialApp.router (GoRouter)
```

### 3.5 Background Services Architecture

```
+---------------------------------------------------+
|              ANDROID WORKMANAGER                    |
|  +----------------------------------------------+  |
|  | PeriodicTask: MediaScanner                   |  |
|  | - Interval: 15 minutes                       |  |
|  | - Constraints: Network available             |  |
|  | - Purpose: Scan device for new media          |  |
|  +----------------------------------------------+  |
|  +----------------------------------------------+  |
|  | OneTimeTask: UploadWorker                    |  |
|  | - Triggered by: MediaScanner findings         |  |
|  | - Constraints: Wi-Fi, Not low battery        |  |
|  | - Purpose: Upload queued files               |  |
|  +----------------------------------------------+  |
+---------------------------------------------------+
          |
          v
+---------------------------------------------------+
|         FLUTTER BACKGROUND SERVICE                 |
|  +----------------------------------------------+  |
|  | Isolate: UploadManager                       |  |
|  | - Runs in background isolate                 |  |
|  | - Communicates via SendPort/ReceivePort       |  |
|  | - Manages TDLib client for uploads            |  |
|  | - Shows foreground notification              |  |
|  +----------------------------------------------+  |
+---------------------------------------------------+
```

### 3.6 TDLib Integration Architecture

```
+----------------------------------------------+
|              TDLib Client Layer               |
|                                              |
|  +----------------------------------------+  |
|  | TDLibClient (singleton)                |  |
|  | - initialize(apiId, apiHash)           |  |
|  | - login(phoneNumber)                   |  |
|  | - sendMessage(chatId, file)            |  |
|  | - downloadFile(fileId)                 |  |
|  | - getStorageUsage()                    |  |
|  | - streamUpdates() -> Stream<TdObject>  |  |
|  +----------------------------------------+  |
|                                              |
|  +----------------------------------------+  |
|  | TelegramStorageManager                 |  |
|  | - createPrivateChannel()               |  |
|  | - sendPhoto(filePath, channelId)       |  |
|  | - sendVideo(filePath, channelId)       |  |
|  | - getChannelMessages(channelId)        |  |
|  | - deleteMessage(messageId)             |  |
|  +----------------------------------------+  |
|                                              |
|  +----------------------------------------+  |
|  | TelegramAuthManager                    |  |
|  | - sendCode(phoneNumber)                |  |
|  | - checkCode(code)                      |  |
|  | - checkPassword(password)              |  |
|  | - getAuthorizationState()              |  |
|  +----------------------------------------+  |
+----------------------------------------------+
```

**Key TDLib Methods Used:**

| TDLib Method | Purpose |
|-------------|---------|
| `setTdlibParameters` | Configure client (database path, files path) |
| `setAuthenticationPhoneNumber` | Initiate phone login |
| `checkAuthenticationCode` | Verify SMS code |
| `checkAuthenticationPassword` | Verify 2FA password |
| `createPrivateChannel` | Create hidden storage channel |
| `sendMessage` | Upload file to channel |
| `downloadFile` | Download file from Telegram |
| `getChat` | Get channel info |
| `searchChatMessages` | Search by caption/metadata |
| `getStorageStatistics` | Get cloud storage usage |
| `deleteMessages` | Delete from trash |

**TDLib Configuration:**

```
TdlibParameters(
  apiId: LUMOVAULT_API_ID,      // Pre-registered on my.telegram.org
  apiHash: LUMOVAULT_API_HASH,  // Hardcoded, never exposed
  databaseDirectory: appDocPath,
  filesDirectory: appDocPath,
  useTestDc: false,
  databaseKey: secureKey,        // From flutter_secure_storage
)
```

---

## 4. Project Structure

### 4.1 Folder Structure

```
lumovault/
  .github/
    workflows/
      ci.yml                    # Main CI pipeline
      build_debug.yml           # Debug APK build
      build_release.yml         # Release APK build
  android/
    app/
      src/main/
        AndroidManifest.xml
        kotlin/.../
          MainActivity.kt
          BackupWorker.kt       # WorkManager worker
          MediaScannerWorker.kt
          UploadForegroundService.kt
        res/
      build.gradle.kts
  lib/
    main.dart
    app.dart
    core/
      constants/
        app_constants.dart
        telegram_constants.dart
        database_constants.dart
      theme/
        app_theme.dart
        app_colors.dart
        app_typography.dart
      utils/
        date_utils.dart
        file_utils.dart
        platform_utils.dart
        permission_utils.dart
      extensions/
        context_extensions.dart
        string_extensions.dart
      router/
        app_router.dart
      di/
        providers.dart
    features/
      auth/
        data/repositories/auth_repository.dart
        data/models/user_model.dart
        domain/entities/user_entity.dart
        domain/usecases/login_usecase.dart
        domain/usecases/logout_usecase.dart
        presentation/screens/
          login_screen.dart
          phone_input_screen.dart
          code_verification_screen.dart
          two_factor_screen.dart
        presentation/widgets/
          phone_input_field.dart
          code_input_field.dart
        presentation/providers/auth_providers.dart
      gallery/
        data/repositories/gallery_repository.dart
        data/models/media_model.dart
        domain/entities/media_entity.dart
        domain/usecases/
          load_timeline_usecase.dart
          load_albums_usecase.dart
          search_media_usecase.dart
        presentation/screens/
          gallery_screen.dart
          timeline_screen.dart
          albums_screen.dart
          album_detail_screen.dart
          media_viewer_screen.dart
          search_screen.dart
        presentation/widgets/
          timeline_grid.dart
          media_tile.dart
          album_card.dart
          date_header.dart
          media_grid_item.dart
          lightbox_viewer.dart
        presentation/providers/
          gallery_providers.dart
          search_providers.dart
      backup/
        data/repositories/backup_repository.dart
        data/datasources/
          upload_queue_datasource.dart
          backup_state_datasource.dart
        data/models/
          upload_task_model.dart
          backup_stats_model.dart
        domain/entities/
          upload_task_entity.dart
          backup_stats_entity.dart
        domain/usecases/
          start_backup_usecase.dart
          pause_backup_usecase.dart
          resume_backup_usecase.dart
          retry_failed_usecase.dart
          get_backup_stats_usecase.dart
        engine/
          backup_engine.dart
          upload_worker.dart
          upload_queue.dart
          chunked_uploader.dart
          backup_scheduler.dart
        presentation/screens/
          backup_dashboard_screen.dart
          backup_settings_screen.dart
          storage_stats_screen.dart
        presentation/widgets/
          backup_progress_card.dart
          storage_usage_bar.dart
          upload_queue_list.dart
          backup_stats_card.dart
        presentation/providers/backup_providers.dart
      restore/
        data/repositories/restore_repository.dart
        domain/usecases/
          restore_library_usecase.dart
          restore_progress_usecase.dart
        engine/
          restore_engine.dart
          restore_worker.dart
        presentation/screens/
          restore_screen.dart
          restore_progress_screen.dart
        presentation/providers/restore_providers.dart
      favorites/
        domain/usecases/
          toggle_favorite_usecase.dart
          load_favorites_usecase.dart
        presentation/screens/favorites_screen.dart
      hidden/
        domain/usecases/
          toggle_hidden_usecase.dart
          load_hidden_usecase.dart
        presentation/screens/hidden_album_screen.dart
      archive/
        domain/usecases/
          archive_media_usecase.dart
          load_archive_usecase.dart
        presentation/screens/archive_screen.dart
      trash/
        domain/usecases/
          trash_media_usecase.dart
          restore_from_trash_usecase.dart
          empty_trash_usecase.dart
        presentation/screens/trash_screen.dart
      onboarding/
        presentation/screens/
          welcome_screen.dart
          permissions_screen.dart
          folder_selection_screen.dart
          initial_scan_screen.dart
        presentation/widgets/
          feature_card.dart
          permission_card.dart
        presentation/providers/onboarding_providers.dart
      settings/
        presentation/screens/
          settings_screen.dart
          account_screen.dart
          storage_screen.dart
          about_screen.dart
        presentation/widgets/settings_tile.dart
        presentation/providers/settings_providers.dart
    shared/
      widgets/
        lumo_scaffold.dart
        lumo_app_bar.dart
        lumo_bottom_nav.dart
        lumo_fab.dart
        lumo_loading.dart
        lumo_empty_state.dart
        lumo_error_widget.dart
        lumo_dialog.dart
        lumo_snackbar.dart
        lumo_chip.dart
        lumo_card.dart
      providers/
        connectivity_provider.dart
        theme_provider.dart
        permission_provider.dart
    l10n/
      app_en.arb
      l10n.dart
  test/
    features/auth/
    features/gallery/
    features/backup/
    features/restore/
    core/
    shared/
  integration_test/
  pubspec.yaml
  analysis_options.yaml
  l10n.yaml
  README.md
  PRD.md
```

### 4.2 Key Files Summary

| File | Purpose |
|------|---------|
| `lib/main.dart` | Entry point, Riverpod initialization |
| `lib/app.dart` | MaterialApp, theme, router |
| `lib/core/di/providers.dart` | All global providers |
| `lib/core/router/app_router.dart` | GoRouter configuration |
| `lib/core/theme/app_theme.dart` | Material 3 theme |
| `lib/features/backup/engine/backup_engine.dart` | Core backup orchestrator |
| `lib/features/backup/engine/upload_worker.dart` | Background upload logic |
| `lib/features/restore/engine/restore_engine.dart` | Restore orchestrator |
| `lib/shared/widgets/` | Reusable UI components |

---

## 5. Database Schema

> **Persistence engine update (2026): Isar → drift.** The schema below was
> originally authored against Isar 3.1.x. During stabilization we switched the
> persistence engine to [`drift`](https://pub.dev/packages/drift) (SQLite). The
> rationale: Isar 3.1.0 is effectively unmaintained upstream, and because no
> production data existed yet there was nothing to migrate — making this the
> cheapest possible point to switch. The drift schema lives in
> `lib/core/database/app_database.dart` (`MediaItems`, `UploadTasks` tables),
> with row↔domain mappers in `media_item_mapper.dart` / `upload_task_mapper.dart`.
> The Isar collection definitions in §5.1 are retained below as the *logical*
> schema reference; the concrete `Id`/`IsarLink`/`IsarLinks` types map to drift
> autoincrement primary keys and explicit foreign-key columns respectively.

### 5.1 Collections (logical schema; implemented as drift tables)


#### Collection 1: `MediaItem`

The central collection storing metadata for every photo and video.

```
@collection
class MediaItem {
  Id id = Isar.autoIncrement;

  // --- Identity ---
  String localId;           // Device's media store ID
  String fileHash;          // SHA-256 of file content
  String? telegramMessageId; // Telegram message ID after upload
  String? telegramFileId;   // Telegram file_id for re-download

  // --- File Info ---
  String filePath;          // Local file system path
  String fileName;          // Original file name
  String mimeType;          // image/jpeg, video/mp4, etc.
  int fileSize;             // Bytes
  int width;                // Pixels
  int height;               // Pixels
  int? durationMs;          // Video duration in milliseconds

  // --- Dates ---
  DateTime createdAt;       // When file was created (EXIF/device)
  DateTime modifiedAt;      // When file was last modified
  DateTime scannedAt;       // When LumoVault discovered it
  DateTime? uploadedAt;     // When successfully uploaded
  DateTime? backedUpAt;     // When metadata was synced

  // --- Status ---
  @enumerated
  MediaStatus status;       // pending, uploading, uploaded, failed, excluded
  String? errorMessage;     // Last upload error

  // --- Categorization ---
  bool isFavorite;
  bool isHidden;
  bool isArchived;
  bool isTrashed;
  DateTime? trashedAt;      // For 30-day auto-delete

  // --- Backup Config ---
  bool isExcluded;          // User-excluded from backup
  String? albumName;        // Device album/folder name
  String? deviceFolder;     // Full device folder path

  // --- Search ---
  String? description;      // User-added description
  List<String> tags = [];   // User tags

  // --- Thumbnail ---
  String? thumbnailPath;    // Local thumbnail cache path
}
```

**Indexes:**

```
// Composite index for timeline queries
@Index(composite: [CompositeIndex('createdAt')])

// Unique index for deduplication
@Index(unique: true, composite: [CompositeIndex('fileHash')])

// Status index for backup queue
@Index(composite: [CompositeIndex('status')])

// Local ID index for device sync
@Index(unique: true, composite: [CompositeIndex('localId')])

// Full-text search on description
@Index(type: IndexType.value, composite: [CompositeIndex('description')])

// Album grouping
@Index(composite: [CompositeIndex('albumName')])

// Favorites
@Index(composite: [CompositeIndex('isFavorite')])

// Trashed items
@Index(composite: [CompositeIndex('isTrashed'), CompositeIndex('trashedAt')])
```

**Relationships:**

```
// Links
IsarLink<DeviceFolder> linkToDeviceFolder;
```

#### Collection 2: `DeviceFolder`

Represents scanned device folders.

```
@collection
class DeviceFolder {
  Id id = Isar.autoIncrement;

  String path;              // /storage/emulated/0/DCIM/Camera
  String name;              // Camera, Screenshots, etc.
  bool isIncluded;          // Is this folder included in backup
  int totalItems;           // Cached count
  int totalSize;            // Cached total size
  DateTime lastScannedAt;   // When last scanned
  DateTime createdAt;       // When first discovered

  // Backlinks to MediaItem
  IsarLinks<MediaItem> mediaItems;
}
```

**Indexes:**

```
@Index(unique: true, composite: [CompositeIndex('path')])
```

#### Collection 3: `UploadTask`

Queue of files waiting to be uploaded or currently uploading.

```
@collection
class UploadTask {
  Id id = Isar.autoIncrement;

  String mediaItemId;       // Reference to MediaItem
  String filePath;          // File to upload
  int fileSize;             // Bytes
  int priority;             // Lower = higher priority

  @enumerated
  UploadTaskStatus status;  // queued, uploading, completed, failed, paused

  int attempts;             // Number of upload attempts
  int? maxAttempts;         // Max retries (default 5)
  String? lastError;        // Last error message
  DateTime? createdAt;      // When queued
  DateTime? startedAt;      // When upload started
  DateTime? completedAt;    // When upload finished
  double progress;          // 0.0 to 1.0

  // Chunked upload state
  int? currentChunk;
  int? totalChunks;
  String? uploadSessionId;
}
```

**Indexes:**

```
@Index(composite: [CompositeIndex('status'), CompositeIndex('priority')])
@Index(composite: [CompositeIndex('mediaItemId')])
```

#### Collection 4: `Album`

Custom albums (beyond device folders).

```
@collection
class Album {
  Id id = Isar.autoIncrement;

  String name;
  String? description;
  String? coverMediaId;     // ID of media used as cover
  DateTime createdAt;
  DateTime updatedAt;
  int itemCount;

  IsarLinks<MediaItem> mediaItems;
}
```

#### Collection 5: `BackupSettings`

Persistent backup configuration.

```
@collection
class BackupSettings {
  Id id = 1;                    // Singleton

  bool isAutoBackupEnabled;
  bool wifiOnly;                // Upload only on Wi-Fi
  bool chargingOnly;            // Upload only when charging
  bool cellularAllowed;         // Allow cellular data
  int? maxFileSize;             // Skip files larger than this (bytes)
  List<String> includedFolders = [];
  List<String> excludedFolders = [];
  List<String> excludedFileHashes = []; // Individual excluded files
  int uploadBatchSize;          // Files per batch (default 10)
  int uploadDelayMs;            // Delay between uploads (default 2000)
  DateTime? lastBackupAt;
  DateTime? lastScanAt;
}
```

#### Collection 6: `SearchIndex`

Full-text search index for fast queries.

```
@collection
class SearchIndex {
  Id id = Isar.autoIncrement;

  String mediaItemId;
  String term;              // Individual search term
  @enumerated
  SearchTermType type;      // filename, description, tag, album, date
}
```

**Indexes:**

```
@Index(composite: [CompositeIndex('term'), CompositeIndex('type')])
@Index(composite: [CompositeIndex('mediaItemId')])
```

#### Collection 7: `SyncLog`

Tracks sync operations for conflict resolution.

```
@collection
class SyncLog {
  Id id = Isar.autoIncrement;

  String mediaItemId;
  String operation;         // upload, download, delete, update
  DateTime timestamp;
  String? details;          // JSON-encoded operation details
  bool success;
  String? error;
}
```

### 5.2 Enums

```
enum MediaStatus {
  pending,      // Discovered but not yet uploaded
  uploading,    // Currently being uploaded
  uploaded,     // Successfully uploaded to Telegram
  failed,       // Upload failed after max retries
  excluded,     // User excluded from backup
}

enum UploadTaskStatus {
  queued,       // Waiting in queue
  uploading,    // Currently uploading
  completed,    // Successfully uploaded
  failed,       // Failed after max retries
  paused,       // User paused
  cancelled,    // User cancelled
}

enum SearchTermType {
  filename,
  description,
  tag,
  album,
  date,
}
```

### 5.3 Migration Strategy

Isar supports automatic schema migration for adding/removing collections and fields. For data migration:

1. **Version tracking:** Store `schemaVersion` in SharedPreferences
2. **Migration scripts:** Each version bump triggers a migration function
3. **Background migration:** Large data migrations run in isolates to avoid UI blocking
4. **Enum safety:** Never reorder or remove enum values; always append new values at the end

```
Schema Version History:
  v1 -> Initial schema (V1.0)
  v2 -> Add SearchIndex collection (V1.1)
  v3 -> Add tags field to MediaItem (V1.2)
  v4 -> (Reserved for future)
```

---

## 6. Metadata System

### 6.1 Design Philosophy

LumoVault does NOT use a single giant metadata.json file. Instead, metadata is:

1. **Distributed** across Isar collections (structured, queryable)
2. **Embedded** in Telegram message captions (portable, survives restore)
3. **Synced** via a lightweight manifest system (versioned, conflict-free)

### 6.2 Metadata Layers

```
Layer 1: Isar Database (Primary)
  MediaItem collection (all metadata)
  DeviceFolder collection (folder state)
  UploadTask collection (backup queue)
  Album collection (custom albums)
  BackupSettings collection (configuration)
  SearchIndex collection (full-text search)

Layer 2: Telegram Captions (Portable Backup)
  media_id:<isar_id>
  file_hash:<sha256>
  created:<iso8601>
  device:<device_model>
  app_version:<version>
  metadata_version:<1>

Layer 3: Telegram Channel Description (App State)
  app:lumovault
  schema_version:1
  created:<iso8601>
  device:<device_id_hash>
  total_items:<count>
```

### 6.3 Caption Metadata Format

When uploading a file to Telegram, LumoVault sets the message caption to:

```
[LV:v1]
id:<local_media_id>
hash:<file_sha256>
ts:<unix_timestamp>
dim:<width>x<height>
dur:<duration_ms>
folder:<album_name>
fav:<0|1>
```

Example:

```
[LV:v1]
id:12345
hash:a1b2c3d4e5f6...
ts:1720000000
dim:4032x3024
dur:0
folder:Camera
fav:0
```

This format is:

- **Compact** -- minimal bandwidth overhead
- **Parseable** -- simple key:value format
- **Versioned** -- `[LV:v1]` prefix allows future format changes
- **Human-readable** -- debuggable without tools

### 6.4 Manifest System

Each private Telegram channel stores a pinned message containing the app manifest:

```json
{
  "app": "lumovault",
  "schema_version": 1,
  "created": "2026-07-14T00:00:00Z",
  "device_hash": "sha256_of_device_id",
  "total_media": 15234,
  "total_size_bytes": 107374182400,
  "last_sync": "2026-07-14T12:00:00Z",
  "chunks": [
    {"id": 0, "count": 5000, "hash": "abc123"},
    {"id": 1, "count": 5000, "hash": "def456"},
    {"id": 2, "count": 5234, "hash": "ghi789"}
  ]
}
```

### 6.5 Sync Strategy

```
+---------------------------------------------------+
|              SYNC STRATEGY                         |
|                                                    |
|  Local -> Telegram (Backup)                        |
|  ---------------------------------                 |
|  1. Scan device for new/modified media              |
|  2. Compute SHA-256 hash of each file              |
|  3. Check Isar for existing hash (dedup)           |
|  4. Upload new files with metadata caption         |
|  5. Update Isar with telegramMessageId             |
|  6. Update manifest                                |
|                                                    |
|  Telegram -> Local (Restore)                       |
|  ---------------------------------                 |
|  1. Fetch manifest from channel description        |
|  2. Compare manifest version with local            |
|  3. Download all messages in channel               |
|  4. Parse captions to extract metadata             |
|  5. Download files and save locally                |
|  6. Populate Isar database                         |
|  7. Rebuild search index                           |
|                                                    |
|  Conflict Resolution:                              |
|  ---------------------                             |
|  - File hash comparison (SHA-256)                  |
|  - Last-write-wins for metadata changes            |
|  - No merge needed (append-only backup)            |
|  - Telegram is source of truth for file bytes      |
|  - Isar is source of truth for metadata            |
+---------------------------------------------------+
```

### 6.6 Future Migrations

The metadata system is designed for forward compatibility:

| Version | Changes | Migration |
|---------|---------|-----------|
| v1 | Initial format | N/A |
| v2 | Add GPS coordinates to caption | Parse missing fields as null |
| v3 | Add face detection tags | Background job populates |
| v4 | Add AI-generated descriptions | Background job populates |
| v5 | End-to-end encryption metadata | Re-encrypt on upgrade |

Each version bump:

1. Updates `schema_version` in manifest
2. New fields are optional (old data remains valid)
3. Background migration populates missing fields
4. No user action required

---

## 7. Feature Specifications

### 7.1 Onboarding Flow

```
+--------------+     +--------------+     +--------------+     +--------------+
|   Welcome    |---->|  Permissions |---->|   Folders    |---->|  First Scan  |
|    Screen    |     |    Screen    |     |  Selection   |     |   Screen     |
+--------------+     +--------------+     +--------------+     +--------------+
```

**Welcome Screen:**

- App logo and tagline: "Your photos, your cloud, your control"
- Three feature highlights with icons
- "Get Started" button (Material 3 FilledButton)
- "I already have an account" link
- Animated background with gradient

**Permissions Screen:**

- Request storage permission (photos/videos)
- Request notification permission
- Request background execution permission
- Each permission shown as a card with explanation
- "Skip for now" option (limited functionality)
- Permission cards with Material 3 icons

**Folder Selection Screen:**

- List of detected device folders with thumbnails
- Toggle switches for each folder
- Default: DCIM/Camera enabled, others disabled
- Show item count and total size per folder
- "Select All" / "Deselect All" buttons
- Preview thumbnails for each folder

**Initial Scan Screen:**

- Animated scanning indicator
- Progress counter: "Found X photos and Y videos"
- Estimated backup size
- Can skip and continue in background
- "Start Backup" button when scan completes

### 7.2 Telegram Login

```
+--------------+     +--------------+     +--------------+     +--------------+
|  Phone Input |---->|  Code Entry  |---->|  2FA         |---->|  Creating    |
|              |     |              |     |  Password    |     |  Storage     |
+--------------+     +--------------+     +--------------+     +--------------+
```

**Phone Input Screen:**

- Country code picker with search
- Phone number input field
- "Continue" button
- Link: "We'll send a verification code to your Telegram"
- Privacy note: "Your phone number is used only for Telegram authentication"

**Code Entry Screen:**

- 5-digit code input (auto-advancing fields)
- Resend code timer (60 seconds)
- "Wrong number?" link back to phone input
- Loading indicator during verification

**2FA Password Screen (conditional):**

- Password input field with visibility toggle
- "Forgot password?" link
- Only shown if user has 2FA enabled

**Storage Creation Screen:**

- "Setting up your secure vault..." message
- Animated progress indicator
- Creates private Telegram channel automatically
- Pins manifest message
- "Done!" confirmation with checkmark animation

### 7.3 Automatic Private Storage Creation

After login, LumoVault automatically:

1. **Creates a private channel** via TDLib `createPrivateChannel`
   - Channel name: "LumoVault Backup" (can be renamed by user)
   - Channel type: Private (no invite links)
   - Description: Contains app manifest JSON

2. **Pins a manifest message** in the channel
   - Contains schema version, device info, initial stats
   - Updated after each backup session

3. **Stores channel ID** securely in Isar + flutter_secure_storage
   - Channel ID is the primary reference for all uploads
   - Never exposed to user

4. **Hides the channel** from Telegram UI
   - The channel won't appear in user's chat list
   - Only accessible via LumoVault

### 7.4 Local Gallery

The main gallery screen with Material 3 design:

```
+-----------------------------------+
| LumoVault            Search  Settings|  <- App Bar
+-----------------------------------+
| +-----+ +-----+ +-----+ +-----+ ||
| |     | |     | |     | |     | ||  <- Date Group Header
| | IMG | | IMG | | IMG | | IMG | ||
| |     | |     | |     | |     | ||
| +-----+ +-----+ +-----+ +-----+ ||
| +-----+ +-----+ +-----+ +-----+ ||
| |     | |     | |     | |     | ||
| | IMG | | IMG | | IMG | | IMG | ||
| |     | |     | |     | |     | ||
| +-----+ +-----+ +-----+ +-----+ ||
|                                   |
+-----------------------------------+
| Home   Albums  Favorites Settings  |  <- Bottom Nav
+-----------------------------------+
```

**Features:**

- Grid layout: 4 columns, responsive to screen width
- Date group headers: "Today", "Yesterday", "July 14, 2026"
- Lazy loading: Load 100 items at a time
- Thumbnail cache: LRU cache with 200MB limit
- Pull-to-refresh
- Multi-select mode (long press)
- Pinch-to-zoom grid density (3-5 columns)

### 7.5 Timeline

The timeline is the default view, showing all media chronologically:

```
Timeline Structure:
  Today
    photo_001.jpg
    photo_002.jpg
    video_001.mp4
  Yesterday
    photo_003.jpg
    photo_004.jpg
  July 12, 2026
    photo_005.jpg
    ...
  July 11, 2026
    ...
```

**Scroll behavior:**

- Fast scrolling with date indicator overlay
- Scroll-to-top button appears after scrolling down
- Preserves scroll position on return
- Animated section headers

### 7.6 Albums

```
Album Types:
  Device Albums (auto-detected)
    Camera
    Screenshots
    WhatsApp Images
    Download
    ...
  Custom Albums (user-created)
    Vacation 2026
    Family
    ...
  Special Albums
    Favorites
    Hidden
    Archive
    Trash
```

**Album Grid View:**

- 2-column grid of album cards
- Each card shows: cover photo, album name, item count
- Long press to reorder custom albums
- "+" button to create new album

### 7.7 Favorites

- Toggle favorite from media viewer (heart icon)
- Toggle from grid (long press then heart icon in toolbar)
- Favorites screen shows all favorited items
- Synced to Telegram: caption includes `fav:1`

### 7.8 Hidden Album

- Accessible via Settings then Hidden Album
- Requires authentication (PIN, pattern, or biometric)
- Hidden items are not shown in timeline or search
- Can be backed up or excluded from backup
- Items remain in Telegram but caption shows `hidden:1`

### 7.9 Archive

- Archive removes items from main timeline
- Archived items accessible via Albums then Archive
- Can be unarchived at any time
- Archived items still backed up unless excluded

### 7.10 Trash

```
Trash Flow:
1. User deletes media -> moved to Trash
2. Trash shows items with "X days left" countdown
3. After 30 days -> permanently deleted
4. User can: restore, delete now, empty trash
5. "Delete now" removes from Telegram AND local storage
```

- Trash items shown with countdown badge
- Batch operations: restore all, empty trash
- Confirmation dialogs for permanent deletion
- Trash does NOT count toward storage statistics

---

## 8. UI/UX Design

### 8.1 Design System

**Material 3 (Material You) Implementation:**

- Dynamic color theming based on device wallpaper
- Seed color fallback: Deep Purple (#6750A4) for branded experience
- Light and Dark theme support
- Typography: Google Sans / Roboto

**Color Palette:**

```
Primary:        #6750A4 (Deep Purple)
On Primary:     #FFFFFF
Primary Container: #EADDFF
Secondary:      #625B71
Tertiary:       #7D5260
Background:     #FFFBFE (Light) / #1C1B1F (Dark)
Surface:        #FFFBFE (Light) / #1C1B1F (Dark)
Error:          #B3261E
```

### 8.2 Navigation Architecture

```
Bottom Navigation (4 tabs):
  Tab 1: Timeline (Home)
    Gallery Screen
      -> Media Viewer (full-screen)
      -> Search Screen
  Tab 2: Albums
    Albums Screen
      -> Album Detail Screen
      -> Create Album Screen
  Tab 3: Favorites
    Favorites Screen
      -> Media Viewer
  Tab 4: Settings
    Settings Screen
      -> Account
      -> Storage
      -> Backup Settings
      -> About

Overflow Menu:
  -> Hidden Album (requires auth)
  -> Archive
  -> Trash
```

### 8.3 Screen Specifications

#### Screen 1: Gallery (Timeline View)

```
+-----------------------------------------------+
| [LumoVault]                     [Search] [More]|  App Bar
+-----------------------------------------------+
|  [Today]                                       |  Date Header
|  +------+------+------+------+                |
|  |      |      |      |      |                |  Photo Grid
|  | img  | img  | img  | img  |                |  (4 columns)
|  |      |      |      |      |                |
|  +------+------+------+------+                |
|  +------+------+------+------+                |
|  |      |      |      |      |                |
|  | img  | vid  | img  | img  |                |
|  |      | [>]  |      |      |                |
|  +------+------+------+------+                |
|  [Yesterday]                                   |  Date Header
|  +------+------+------+------+                |
|  |      |      |      |      |                |
|  | img  | img  | img  | img  |                |
|  |      |      |      |      |                |
|  +------+------+------+------+                |
+-----------------------------------------------+
|  [Timeline] [Albums] [Favs] [Settings]        |  Bottom Nav
+-----------------------------------------------+
```

**Interactions:**
- Tap photo -> Full-screen viewer
- Long press -> Multi-select mode
- Pull down -> Refresh
- Scroll -> Fast scroll with date overlay
- Pinch -> Adjust grid density

#### Screen 2: Media Viewer

```
+-----------------------------------------------+
| [< Back]                       [Share] [More] |  App Bar (auto-hide)
+-----------------------------------------------+
|                                               |
|                                               |
|                                               |
|              FULL-SCREEN IMAGE                |
|                                               |
|                                               |
|                                               |
+-----------------------------------------------+
|  [Heart]   [Info]   [Delete]   [Download]     |  Bottom Toolbar
+-----------------------------------------------+
|  July 14, 2026 at 3:42 PM                     |  Metadata
+-----------------------------------------------+
```

**Interactions:**
- Swipe left/right -> Navigate between photos
- Pinch -> Zoom
- Double tap -> Fit to screen / 2x zoom toggle
- Tap center -> Toggle UI visibility
- Long press -> Share / Set as / Details

#### Screen 3: Backup Dashboard

```
+-----------------------------------------------+
| [< Back]              Backup Dashboard         |
+-----------------------------------------------+
|  +-------------------------------------------+|
|  |     STORAGE USAGE                         ||
|  |  [===========       ] 12.4 GB / 50 GB     ||
|  |  Telegram Cloud: 12.4 GB used             ||
|  +-------------------------------------------+|
|                                               |
|  +-------------------------------------------+|
|  |     BACKUP STATUS                         ||
|  |  Status: Uploading (3 of 147)             ||
|  |  [=========>         ] 47%                ||
|  |  Speed: 2.3 MB/s  |  ETA: 12 min         ||
|  +-------------------------------------------+|
|                                               |
|  [Pause Backup]  [Resume]  [Retry Failed]     |
|                                               |
|  RECENT ACTIVITY                              |
|  +-------------------------------------------+|
|  | photo_001.jpg    Uploaded    2:34 PM       ||
|  | photo_002.jpg    Uploaded    2:33 PM       ||
|  | video_001.mp4    Uploading   2:32 PM       ||
|  | photo_003.jpg    Failed      2:31 PM       ||
|  +-------------------------------------------+|
+-----------------------------------------------+
```

#### Screen 4: Settings

```
+-----------------------------------------------+
| [< Back]                   Settings            |
+-----------------------------------------------+
|                                               |
|  ACCOUNT                                      |
|  +-------------------------------------------+|
|  |  [Avatar]  John Doe                       ||
|  |  +1 234 567 8900                          ||
|  +-------------------------------------------+|
|                                               |
|  BACKUP                                       |
|  +-------------------------------------------+|
|  |  Auto Backup           [Toggle: ON]        ||
|  |  Wi-Fi Only            [Toggle: ON]        ||
|  |  Charging Only         [Toggle: OFF]       ||
|  |  Backup Settings       [>]                 ||
|  +-------------------------------------------+|
|                                               |
|  LIBRARY                                      |
|  +-------------------------------------------+|
|  |  Hidden Album          [>]                 ||
|  |  Archive               [>]                 ||
|  |  Trash (3)             [>]                 ||
|  +-------------------------------------------+|
|                                               |
|  ABOUT                                        |
|  +-------------------------------------------+|
|  |  Storage Usage         [>]                 ||
|  |  Version 1.0.0                            ||
|  |  About LumoVault      [>]                 ||
|  +-------------------------------------------+|
+-----------------------------------------------+
```

### 8.4 Animations and Transitions

| Transition | Animation | Duration |
|-----------|-----------|----------|
| Page push | Slide from right | 300ms |
| Page pop | Slide to right | 250ms |
| Tab switch | Cross-fade | 200ms |
| Grid item tap | Hero animation to viewer | 400ms |
| Multi-select | Scale + overlay | 200ms |
| Pull to refresh | Material 3 refresh indicator | Indefinite |
| Backup progress | Smooth counter animation | 300ms |
| Empty state | Fade in + slide up | 500ms |
| Error state | Shake animation (subtle) | 300ms |

### 8.5 Responsive Layout

```
Phone (< 600px):
  - 4-column grid
  - Bottom navigation
  - Single pane

Tablet (600-840px):
  - 5-column grid
  - Side navigation rail
  - Two-pane (list + detail)

Large Tablet (> 840px):
  - 6-column grid
  - Side navigation drawer
  - Three-pane (list + detail + info)
```

### 8.6 Accessibility

- Minimum touch target: 48x48dp
- Color contrast ratio: WCAG AA (4.5:1)
- Screen reader labels on all interactive elements
- Dynamic text scaling support
- Reduced motion mode support
- Semantic labels for all images

---

## 9. Backup Engine

### 9.1 Architecture Overview

```
+-----------------------------------------------------------+
|                    BACKUP ENGINE                            |
|                                                            |
|  +------------------+    +------------------+              |
|  | Media Scanner    |    | Upload Scheduler |              |
|  | - Scan device    |--->| - Prioritize     |              |
|  | - Detect changes |    | - Batch          |              |
|  | - Compute hashes |    | - Throttle       |              |
|  +------------------+    +--------+---------+              |
|                                  |                         |
|                                  v                         |
|                         +------------------+              |
|                         | Upload Worker    |              |
|                         | - TDLib client   |              |
|                         | - Chunked upload |              |
|                         | - Progress track |              |
|                         | - Error handle   |              |
|                         +--------+---------+              |
|                                  |                         |
|                                  v                         |
|                         +------------------+              |
|                         | State Manager    |              |
|                         | - Isar updates   |              |
|                         | - Notifications  |              |
|                         | - Stats calc     |              |
|                         +------------------+              |
+-----------------------------------------------------------+
```

### 9.2 Media Scanner

**Trigger Points:**

1. App startup (if auto-backup enabled)
2. WorkManager periodic task (every 15 minutes)
3. Device boot (via `BOOT_COMPLETED` receiver)
4. User manual refresh
5. New media detected via `ContentObserver`

**Scanning Process:**

```
1. Query Android MediaStore for all images/videos
2. For each media item:
   a. Check if localId exists in Isar
   b. If not found -> new item, compute SHA-256
   c. If found but modifiedAt changed -> re-hash
   d. If hash unchanged -> skip
3. Create Isar records for new items
4. Create UploadTasks for items needing backup
5. Update DeviceFolder stats
```

**Performance Optimizations:**

- Batch Isar writes (100 items per transaction)
- Parallel hash computation (up to 4 isolates)
- Incremental scanning (only scan folders modified since last scan)
- Hash caching (store hashes in Isar, skip re-computation)

### 9.3 Upload Queue

**Priority Algorithm:**

```
priority = (fileSize / 1024/1024) + (recencyScore * 10) + (retryPenalty * 50)

Where:
  fileSize = File size in MB (smaller = higher priority)
  recencyScore = 1.0 - (daysSinceCreation / 365) (newer = higher priority)
  retryPenalty = attemptNumber (more retries = lower priority)
```

**Queue Management:**

```
UploadQueue:
  - PriorityQueue<UploadTask> (min-heap by priority)
  - Batch size: configurable (default 10)
  - Throttle: configurable delay between uploads (default 2000ms)
  - Constraints: Wi-Fi only, charging only
  - Concurrency: 1 upload at a time (TDLib limitation)
```

### 9.4 Chunked Uploader

For files larger than a threshold (default 50MB), use chunked upload:

```
1. Split file into 10MB chunks
2. Upload chunks sequentially
3. Track progress per chunk
4. On failure: retry from failed chunk
5. On success: combine on Telegram side (automatic)
```

### 9.5 Backup Scheduler

**Constraints Evaluation:**

```
ShouldUpload(task):
  1. Is Wi-Fi available? (if wifiOnly setting)
  2. Is device charging? (if chargingOnly setting)
  3. Is battery level > 20%?
  4. Is file size < maxFileSize?
  5. Is folder in includedFolders?
  6. Is file not in excludedFileHashes?
  7. Is app not in battery-optimized mode?

  All conditions must be true to proceed.
```

### 9.6 Error Handling

| Error Type | Handling |
|-----------|----------|
| Network unavailable | Pause queue, retry when connected |
| TDLib not initialized | Re-initialize, retry |
| File not found | Mark as failed, skip |
| File too large (>2GB) | Notify user, offer compression |
| TDLib rate limit | Exponential backoff |
| Authentication expired | Prompt re-login |
| Storage full on Telegram | Notify user, pause backup |
| Unknown error | Log, retry up to 5 times |

---

## 10. Restore Engine

### 10.1 Restore Flow

```
+-------------------+     +-------------------+     +-------------------+
|  Connect to       |     |  Scan Channel     |     |  Download         |
|  Telegram         |---->|  Messages         |---->|  Manifest         |
+-------------------+     +-------------------+     +-------------------+
          |                                                   |
          v                                                   v
+-------------------+     +-------------------+     +-------------------+
|  Login with       |     |  Parse Captions   |     |  Download Files   |
|  Phone + Code     |     |  Extract Metadata |     |  (Batch)          |
+-------------------+     +-------------------+     +-------------------+
                                                          |
                                                          v
+-------------------+     +-------------------+     +-------------------+
|  Rebuild Search   |     |  Populate Isar    |     |  Save Files       |
|  Index            |<----|  Database         |<----|  to Device        |
+-------------------+     +-------------------+     +-------------------+
```

### 10.2 Restore Process

**Step 1: Authentication**

- User enters phone number + code (same as initial login)
- TDLib connects to Telegram
- If same account, channel already exists

**Step 2: Channel Discovery**

```
1. Search user's channels for "LumoVault Backup"
2. If found -> use existing channel
3. If not found -> no backup to restore, offer fresh start
```

**Step 3: Manifest Fetch**

```
1. Get pinned message from channel
2. Parse manifest JSON
3. Display restore summary:
   - Total media items
   - Total size
   - Date range (oldest to newest)
   - Device info
```

**Step 4: File Download**

```
For each message in channel:
  1. Parse caption for metadata
  2. Check if file already exists locally (by hash)
  3. If not exists:
     a. Download file via TDLib
     b. Save to local storage
     c. Create thumbnail
  4. Create/update MediaItem in Isar
  5. Update progress UI
```

**Step 5: Database Population**

```
1. Create all MediaItem records
2. Create DeviceFolder records
3. Build SearchIndex
4. Mark all items as "uploaded" status
5. Update BackupSettings with restore timestamp
```

### 10.3 Restore Progress

```
+-----------------------------------------------+
|  RESTORING YOUR LIBRARY                        |
+-----------------------------------------------+
|                                                |
|  Downloading files... (1,234 of 15,234)       |
|  [==========>              ] 8.1%              |
|                                                |
|  Speed: 5.2 MB/s | ETA: 42 minutes            |
|  Downloaded: 1.2 GB of 15.0 GB                |
|                                                |
|  Current: photo_001.jpg                        |
|                                                |
|  [Pause]  [Cancel]                             |
+-----------------------------------------------+
```

**Features:**

- Real-time progress with ETA
- Pause/Resume capability
- Cancel with confirmation
- Background download support
- Duplicate detection (skip existing files)

### 10.4 Differential Restore

On subsequent restores (e.g., new phone with same account):

```
1. Fetch latest manifest
2. Compare with local state (if any)
3. Only download new/missing files
4. Skip files already present (by hash)
5. Update metadata for changed files
```

---

## 11. Security

### 11.1 Authentication

**Telegram Login Flow:**

```
1. User provides phone number
2. TDLib sends verification code via Telegram
3. User enters code
4. If 2FA enabled, user enters password
5. TDLib stores session locally (encrypted)
6. LumoVault stores session reference in secure storage
```

**Session Management:**

- TDLib handles session persistence internally
- Session database encrypted with user-provided key
- Stored in app's private directory (sandboxed)
- Session expires after 30 days of inactivity
- Re-login required after session expiry

### 11.2 Secure Storage

| Data | Storage Location | Encryption |
|------|-----------------|------------|
| TDLib session | App sandbox | TDLib internal encryption |
| TDLib database key | flutter_secure_storage | Android Keystore |
| API ID/Hash | Hardcoded in binary | N/A (public API credentials) |
| Channel ID | Isar + secure storage | App sandbox |
| User preferences | SharedPreferences | None (non-sensitive) |
| Backup settings | Isar | App sandbox |

### 11.3 Encryption Strategy

**At Rest:**

- TDLib database: Encrypted with user-provided key (AES-256)
- Local files: Stored in app sandbox (Android file-based encryption)
- Thumbnails: Stored in app cache (encrypted by Android)

**In Transit:**

- TDLib uses MTProto encryption (Telegram's protocol)
- All file transfers encrypted end-to-end via MTProto
- No additional encryption layer needed (Telegram provides it)

**Future: Optional Client-Side Encryption (V2.0):**

- User-defined passphrase
- Encrypt files before upload using AES-256-GCM
- Decrypt after download
- Passphrase never stored (user must remember)
- Encrypted files stored in Telegram as opaque data

### 11.4 Privacy

**Data Collection:**

- LumoVault collects ZERO analytics
- No crash reporting services
- No tracking
- No advertising

**Data Storage:**

- All data stored locally on device
- Backup files stored in user's own Telegram account
- No LumoVault servers
- No third-party cloud services

**Telegram Interaction:**

- User's Telegram account is the only cloud storage
- LumoVault creates a private channel (visible only to user)
- No shared data with other Telegram users
- No bot interactions (direct TDLib client)

### 11.5 Permissions

| Permission | Purpose | Required? |
|-----------|---------|-----------|
| `READ_MEDIA_IMAGES` | Scan photos for backup | Yes |
| `READ_MEDIA_VIDEO` | Scan videos for backup | Yes |
| `INTERNET` | Upload/download via TDLib | Yes |
| `RECEIVE_BOOT_COMPLETED` | Restart backup after reboot | Yes |
| `FOREGROUND_SERVICE` | Keep uploads running | Yes |
| `POST_NOTIFICATIONS` | Show backup progress | Yes |
| `WAKE_LOCK` | Prevent sleep during upload | Yes |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Reliable background backup | Recommended |

### 11.6 TDLib API Credentials

- Registered on my.telegram.org under LumoVault developer account
- API ID and API hash hardcoded in the app binary
- These are NOT secrets -- they identify the app to Telegram
- Same approach used by all third-party Telegram clients
- Rate limits apply per API ID (standard Telegram limits)

---

## 12. Performance Targets

### 12.1 Key Performance Indicators

| Metric | Target | Measurement |
|--------|--------|-------------|
| Cold start to gallery | < 1.5s | Time from app launch to gallery grid visible |
| Warm start to gallery | < 0.5s | Time from app resume to gallery grid visible |
| Timeline scroll FPS | > 55 FPS | Measured on mid-range device (Snapdragon 695) |
| Thumbnail load time | < 200ms | Time from scroll stop to thumbnail visible |
| Backup speed (Wi-Fi) | > 2 MB/s average | Upload speed including overhead |
| Memory usage (idle) | < 150MB | RAM usage when gallery is displayed |
| Memory usage (uploading) | < 250MB | RAM usage during active backup |
| Database query time | < 50ms | P95 for standard queries |
| App size (APK) | < 30MB | Download size (without TDLib native libs) |
| Battery usage (backup) | < 5% per 1000 photos | Measured on 4000mAh battery |

### 12.2 Thumbnail Cache Strategy

```
Cache Architecture:
  L1: In-memory LRU cache (50MB)
    - Holds recently viewed thumbnails as Uint8List
    - Eviction: LRU when full
    - Access time: < 1ms

  L2: Disk cache (200MB)
    - Stores resized thumbnails (300x300px)
    - Format: JPEG, quality 85%
    - Eviction: LRU when full
    - Access time: < 50ms

  L3: Original file (on-demand)
    - Full-resolution original
    - Only loaded when user taps to view
    - Not cached by default

Cache Population:
  1. On scan: Generate thumbnails for new items
  2. On view: Cache thumbnail for viewed items
  3. Background: Pre-generate thumbnails for next 100 items in timeline
```

### 12.3 Lazy Loading Strategy

```
Gallery Grid:
  - Initial load: 100 items (sorted by date, newest first)
  - Scroll threshold: Load next 100 when 20 items from bottom
  - Prefetch: Load thumbnails for next 50 items ahead
  - Unload: Remove thumbnails 200 items above viewport

Timeline Sections:
  - Load date groups on demand
  - Each date group: Load items when section becomes visible
  - Collapse distant sections (show count only)

Albums:
  - Load album list immediately
  - Load cover photos lazily (first 4 items per album)
  - Load full album content on tap
```

### 12.4 Database Query Optimization

```
Optimized Queries:

1. Timeline (most common):
   MediaItem.where()
     .sortByCreatedAtDesc()
     .offset(page * pageSize)
     .limit(pageSize)
     .findAll();
   Index: createdAt (composite)

2. Search:
   SearchIndex.where()
     .termEqualTo(query.toLowerCase())
     .findAll();
   Index: term (composite with type)

3. Backup Queue:
   UploadTask.where()
     .statusEqualTo(UploadTaskStatus.queued)
     .sortByPriority()
     .limit(batchSize)
     .findAll();
   Index: status + priority (composite)

4. Favorites:
   MediaItem.where()
     .isFavoriteEqualTo(true)
     .sortByCreatedAtDesc()
     .findAll();
   Index: isFavorite (composite)

5. Album Items:
   Album.where()
     .nameEqualTo(albumName)
     .findFirst()
     .then((album) => album.mediaItems.load());
   Index: name (unique)
```

### 12.5 Memory Management

```
Strategies:

1. Image Disposal:
   - Use dispose() on Image widgets when removed from tree
   - Limit concurrent image decoding to 10
   - Use ImageCache.maximumSize = 100

2. Database Connection:
   - Single Isar instance (shared)
   - Use Isolate for large queries
   - Close query results after use

3. TDLib Client:
   - Single TDLib client instance
   - Reuse across operations
   - Proper cleanup on logout

4. Background Isolate:
   - Upload worker runs in separate isolate
   - Communicates via SendPort
   - No shared memory with UI isolate
```

---

## 13. CI/CD Pipeline

### 13.1 GitHub Actions Workflow

**Main CI Pipeline** (`.github/workflows/ci.yml`):

```
name: LumoVault CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  analyze:
    name: Static Analysis
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.44.0'
          cache: true
      - run: flutter pub get
      - run: flutter analyze --fatal-infos

  test:
    name: Unit & Integration Tests
    needs: analyze
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.44.0'
          cache: true
      - run: flutter pub get
      - run: flutter test --coverage
      - uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage/lcov.info

  build-debug:
    name: Build Debug APK
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.44.0'
          cache: true
      - uses: actions/cache@v4
        with:
          path: ~/.gradle/caches
          key: ${{ runner.os }}-gradle-${{ hashFiles('android/gradle/wrapper/gradle-wrapper.properties') }}
      - run: flutter pub get
      - run: flutter build apk --debug
      - uses: actions/upload-artifact@v4
        with:
          name: debug-apk
          path: build/app/outputs/flutter-apk/app-debug.apk
          retention-days: 14

  build-release:
    name: Build Release APK
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.44.0'
          cache: true
      - uses: actions/cache@v4
        with:
          path: ~/.gradle/caches
          key: ${{ runner.os }}-gradle-${{ hashFiles('android/gradle/wrapper/gradle-wrapper.properties') }}
      - run: flutter pub get
      - name: Decode keystore
        uses: timheuer/base64-to-file@v1
        with:
          fileName: android/app/upload-keystore.jks
          encodedString: ${{ secrets.KEYSTORE_BASE64 }}
      - name: Create key.properties
        run: |
          echo "storePassword=${{ secrets.STORE_PASSWORD }}" > android/key.properties
          echo "keyPassword=${{ secrets.KEY_PASSWORD }}" >> android/key.properties
          echo "keyAlias=${{ secrets.KEY_ALIAS }}" >> android/key.properties
          echo "storeFile=upload-keystore.jks" >> android/key.properties
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v4
        with:
          name: release-apk
          path: build/app/outputs/flutter-apk/app-release.apk
          retention-days: 90
```

### 13.2 Build Matrix

| Job | Runner | Flutter | Java | Cache | Output |
|-----|--------|---------|------|-------|--------|
| analyze | ubuntu-latest | 3.44.0 | N/A | pub cache | lint results |
| test | ubuntu-latest | 3.44.0 | N/A | pub cache | coverage |
| build-debug | ubuntu-latest | 3.44.0 | Temurin 17 | Gradle + pub | app-debug.apk |
| build-release | ubuntu-latest | 3.44.0 | Temurin 17 | Gradle + pub | app-release.apk |

### 13.3 Secrets Management

| Secret | Purpose | Location |
|--------|---------|----------|
| `KEYSTORE_BASE64` | Release signing keystore | GitHub Secrets |
| `STORE_PASSWORD` | Keystore password | GitHub Secrets |
| `KEY_PASSWORD` | Key password | GitHub Secrets |
| `KEY_ALIAS` | Key alias | GitHub Secrets |

### 13.4 Artifact Retention

| Artifact | Retention | Purpose |
|----------|-----------|---------|
| Debug APK | 14 days | Testing, development |
| Release APK | 90 days | Distribution, rollback |
| Coverage report | 30 days | Quality tracking |

### 13.5 TDLib Native Library Handling

TDLib requires pre-built native `.so` files for Android. These are included in the repository:

```
android/app/src/main/jniLibs/
  arm64-v8a/
    libtdjsonandroid.so
  armeabi-v7a/
    libtdjsonandroid.so
  x86_64/
    libtdjsonandroid.so
  x86/
    libtdjsonandroid.so
```

The GitHub Actions workflow builds with these files already present. No special TDLib build step is needed in CI.

---

## 14. Error Handling

### 14.1 Error Categories

| Category | Examples | User Impact | Recovery |
|----------|---------|-------------|----------|
| **Network** | No internet, timeout, DNS failure | Backup pauses | Auto-resume when connected |
| **TDLib** | Auth expired, rate limit, API error | Backup pauses | Re-auth or wait |
| **Storage** | File not found, permission denied | Individual file skipped | Log and continue |
| **Telegram** | Channel not found, storage full | Backup pauses | Notify user |
| **Database** | Corruption, migration failure | App may crash | Rebuild from Telegram |
| **Device** | Low storage, low battery | Backup pauses | Resume when conditions met |

### 14.2 Error Recovery Strategy

```
Error Handling Flow:
  1. Catch error at source (TDLib, Isar, file system)
  2. Categorize error (network, auth, storage, etc.)
  3. Log error with context (file, operation, timestamp)
  4. Update UploadTask status (if applicable)
  5. Notify user (if user action needed)
  6. Retry with backoff (if transient)
  7. Skip and continue (if persistent)
  8. Pause backup (if critical)
```

### 14.3 User-Facing Error Messages

| Error | Message | Action |
|-------|---------|--------|
| No internet | "Waiting for internet connection..." | Auto-resume |
| Auth expired | "Session expired. Please log in again." | Re-login button |
| File not found | "File no longer available. Skipping." | Skip |
| Telegram storage full | "Telegram storage is full. Upgrade to Telegram Premium or free up space." | Settings link |
| Permission denied | "Storage permission required. Grant in Settings." | Settings link |
| Upload failed | "Failed to upload [filename]. Tap to retry." | Retry button |
| Backup paused | "Backup paused. Tap resume to continue." | Resume button |

### 14.4 Logging

```
Log Levels:
  DEBUG:    Detailed operational info (TDLib calls, DB queries)
  INFO:     Key events (backup started, upload completed)
  WARNING:  Recoverable errors (retry, skip)
  ERROR:    Critical errors (backup failed, auth lost)

Log Storage:
  - Debug builds: Full logs to console + file
  - Release builds: Warnings and errors only to file
  - Log location: App documents directory
  - Log rotation: 5MB max, 3 files
```

### 14.5 Crash Reporting

- No external crash reporting in V1 (privacy-first)
- Local crash logs stored in app documents directory
- User can export crash logs via Settings > About > Export Logs
- Future: Optional opt-in crash reporting (V2.0)

---

## 15. Roadmap

### 15.1 Version 1.0 — MVP (3 months)

**Scope:** Core backup and browsing experience

| Feature | Priority | Status |
|---------|----------|--------|
| Telegram login (phone + code) | P0 | Planned |
| Auto-create private channel | P0 | Planned |
| Device media scanner | P0 | Planned |
| Backup engine (upload queue) | P0 | Planned |
| Timeline gallery | P0 | Planned |
| Photo viewer | P0 | Planned |
| Video player | P0 | Planned |
| Albums (device folders) | P0 | Planned |
| Favorites | P1 | Planned |
| Search (filename, date) | P1 | Planned |
| Backup dashboard | P1 | Planned |
| Storage statistics | P1 | Planned |
| Onboarding flow | P1 | Planned |
| Settings screen | P1 | Planned |
| Background backup (WorkManager) | P0 | Planned |
| Pause/Resume backup | P1 | Planned |
| Wi-Fi only mode | P1 | Planned |
| Error handling (basic) | P0 | Planned |
| Unit tests | P1 | Planned |
| Integration tests (critical paths) | P1 | Planned |

### 15.2 Version 1.5 — Enhanced Experience (6 months)

**Scope:** Polish, advanced features, and restore

| Feature | Priority | Status |
|---------|----------|--------|
| Restore engine (full library) | P0 | Planned |
| Custom albums | P1 | Planned |
| Hidden album (biometric) | P1 | Planned |
| Archive | P1 | Planned |
| Trash (30-day auto-delete) | P1 | Planned |
| Multi-select operations | P1 | Planned |
| Share to other apps | P2 | Planned |
| Batch download | P2 | Planned |
| Advanced search (tags, description) | P2 | Planned |
| Backup scheduling (time-based) | P2 | Planned |
| Charging only mode | P2 | Planned |
| Detailed error messages | P1 | Planned |
| Performance optimization (50K+ items) | P0 | Planned |
| Accessibility improvements | P1 | Planned |
| Localization (5 languages) | P2 | Planned |

### 15.3 Version 2.0 — Advanced Features (12 months)

**Scope:** Intelligence, security, and ecosystem

| Feature | Priority | Status |
|---------|----------|--------|
| AI-powered search (natural language) | P1 | Planned |
| Face detection and grouping | P1 | Planned |
| Object recognition and tagging | P1 | Planned |
| Location-based albums | P1 | Planned |
| Client-side encryption (optional) | P1 | Planned |
| Multi-account support | P2 | Planned |
| Web gallery (companion app) | P2 | Planned |
| Desktop companion app | P3 | Planned |
| Shared albums | P2 | Planned |
| Collaboration features | P3 | Planned |
| Storage analytics dashboard | P2 | Planned |
| Export to other clouds | P2 | Planned |

### 15.4 AI Features (Coming Soon)

| Feature | Description | Timeline |
|---------|-------------|----------|
| Smart Search | "Find photos from the beach last summer" | V2.0 |
| Auto-Tagging | Automatically tag objects, scenes, people | V2.0 |
| Face Grouping | Group photos by detected faces | V2.0 |
| Duplicate Detection | Find similar/near-duplicate photos | V2.0 |
| Photo Enhancement | AI-powered photo improvement suggestions | V2.1 |
| Video Highlights | Auto-generate video highlight reels | V2.1 |
| Memories | "On this day" style回忆 features | V2.0 |
| Smart Albums | Auto-categorize photos into smart albums | V2.0 |

---

## 16. Appendix

### 16.1 Glossary

| Term | Definition |
|------|-----------|
| TDLib | Telegram Database Library — cross-platform library for building Telegram clients |
| Isar | Fast NoSQL database built for Flutter |
| WorkManager | Android Jetpack library for deferrable background work |
| MTProto | Telegram's custom encryption protocol |
| Material 3 | Google's latest design system (Material You) |
| Riverpod | Flutter state management library |
| GoRouter | Declarative routing package for Flutter |
| LRU | Least Recently Used — cache eviction strategy |
| SHA-256 | Cryptographic hash function producing 256-bit digest |
| EXIF | Exchangeable Image File Format — metadata in images |

### 16.2 Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  tdlib: ^1.6.0                    # Telegram client
  isar: ^3.1.0+1                   # Local database
  isar_flutter_libs: ^3.1.0+1     # Isar native libs
  flutter_riverpod: ^2.5.0         # State management
  riverpod_annotation: ^2.3.0      # Riverpod code generation
  go_router: ^14.0.0               # Navigation
  workmanager: ^0.5.2              # Background tasks
  flutter_background_service_android: ^6.0.0  # Background isolate
  flutter_secure_storage: ^9.0.0   # Encrypted storage
  permission_handler: ^11.0.0      # Permissions
  cached_network_image: ^3.3.0     # Image caching
  photo_view: ^0.15.0              # Image zoom/viewer
  video_player: ^2.8.0             # Video playback
  path_provider: ^2.1.0            # File paths
  device_info_plus: ^10.0.0        # Device info
  connectivity_plus: ^6.0.0        # Network status
  share_plus: ^10.0.0              # Share functionality
  url_launcher: ^6.2.0             # External links
  intl: ^0.19.0                    # Date formatting

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  isar_generator: ^3.1.0+1
  build_runner: ^2.4.0
  riverpod_generator: ^2.4.0
  mockito: ^5.4.0
  integration_test:
    sdk: flutter
```

### 16.3 Android Manifest Permissions

```xml
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
<uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
```

### 16.4 API Reference

**TDLib API (key methods):**

| Method | Parameters | Returns |
|--------|-----------|---------|
| `setTdlibParameters` | TdlibParameters | Ok |
| `setAuthenticationPhoneNumber` | phoneNumber, settings | Ok |
| `checkAuthenticationCode` | code | Ok |
| `checkAuthenticationPassword` | password | Ok |
| `createPrivateChannel` | title, description | Updates |
| `sendMessage` | chatId, inputMessageContent | Message |
| `downloadFile` | fileId, priority | File |
| `searchChatMessages` | chatId, query, filter | Messages |
| `getStorageStatistics` | chatLimit | StorageStatistics |
| `deleteMessages` | chatId, messageIds, revoke | Ok |

### 16.5 Testing Strategy

| Test Type | Coverage Target | Tools |
|-----------|----------------|-------|
| Unit Tests | > 80% business logic | flutter_test, mockito |
| Widget Tests | > 70% critical widgets | flutter_test |
| Integration Tests | 100% critical paths | integration_test |
| Database Tests | 100% Isar operations | flutter_test + Isar |
| TDLib Tests | Mock-based unit tests | mockito |

### 16.6 Performance Benchmarks

| Operation | Target | Device |
|-----------|--------|--------|
| Scan 10K photos | < 10s | Mid-range (SD 695) |
| Upload 100 photos (Wi-Fi) | < 5 min | 10 Mbps upload |
| Timeline scroll (50K items) | > 55 FPS | Mid-range |
| Search (10K items) | < 100ms | Mid-range |
| App cold start | < 1.5s | Mid-range |
| Thumbnail generation (batch) | < 50ms each | Mid-range |

---

**End of Document**

*This PRD is the master reference for all LumoVault development. All coding prompts should reference this document for context and specifications.*
