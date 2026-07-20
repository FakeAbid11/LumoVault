# LumoVault — Technical & Product Review

Reviewed at commit `c602bb5`. All claims reference actual files/lines in the repository.

---

## 1. App Overview

**What it does.** LumoVault is a Flutter photo/video backup app that uses the user's own Telegram account (via TDLib) as unlimited cloud storage — a Google Photos-style experience with Telegram as invisible infrastructure (`PRD.md` §1, `pubspec.yaml:2`).

**Target platforms.** Android-first. `android/` is fully scaffolded; `ios/` exists but `MainActivity.kt` is bare (`android/app/src/main/kotlin/com/lumovault/app/MainActivity.kt:5` is just `class MainActivity : FlutterActivity()`). PRD §2.3 explicitly targets Android.

**Core user flows.** Onboarding (welcome → permissions → folders → scan → Telegram connect), Telegram auth (phone → code → 2FA), gallery/timeline browsing, backup dashboard, restore, and settings. Routes defined in `lib/core/router/app_router.dart`.

**Architecture pattern.** Clean-ish Architecture with feature-first folders (`lib/features/<feature>/{data,domain,engine,presentation}`) and Riverpod for state + DI. Navigation via GoRouter. It's closer to a layered MVVM-with-repositories than strict Clean Architecture — the `domain/` layer (entities, use cases) described in PRD §4.1 is largely absent; only `gallery/domain/` exists as a folder and most features skip use cases entirely.

**The single most important finding:** the app is a well-structured **UI + business-logic skeleton with no working data backend.** Two foundational pieces named as the core of the product are not wired in:

- **TDLib is entirely stubbed.** `lib/core/tdlib/tdlib_client.dart:184-231` — `_createClient()` returns `0`, `_sendJson()` only `debugPrint`s, and `_receiveJson()` always returns `null`. So every request completer waits and times out (`sendRequest` at `:100`). Auth, upload, download, channel creation, and restore all sit on top of this no-op transport.
- **Isar is never used.** Despite `isar: ^3.1.0` in `pubspec.yaml:21` and an elaborate schema in PRD §5, a repo-wide search for `Isar`/`@collection` returns only comments ("would be Isar in production"). `MediaItem` (`lib/features/gallery/data/models/media_item.dart`) is a plain immutable class, and `GalleryRepository` holds everything in an in-memory `List` (`gallery_repository.dart:18`). All data is lost on restart.

So the product is best characterized as a **high-fidelity prototype**: navigation, theming, state orchestration, queueing logic, and error models are real; the actual Telegram integration and persistence are placeholders.

---

## 2. Feature Inventory

| Feature / Screen | State | Relies on |
|---|---|---|
| Onboarding (welcome, permissions, folders, scan, telegram) | Partial — UI complete, `onboardingCompletedProvider` is in-memory only (`onboarding_provider.dart:158`) so onboarding re-shows every launch | Riverpod `StateNotifier` |
| Auth (phone/code/2FA screens) | Partial — full state machine in `TelegramAuthRepository`, but transport is stubbed so it never authenticates | Riverpod, TDLib (stub) |
| Timeline / Gallery | Partial — real grid, real device scan via `photo_manager`, but re-scans on every screen init | Riverpod, `photo_manager` |
| Media Viewer | **Stubbed** — literally `Text('Media viewer')` (`media_viewer_screen.dart:35`) | none |
| Albums | **Stubbed** — hardcoded empty state (`albums_screen.dart`) | none |
| Search | **Stubbed** — text field with static "No results"; `GalleryRepository.searchMedia` exists but isn't called (`search_screen.dart`) | none |
| Favorites / Archive / Hidden / Trash | **Stubbed** — all four are static empty-state screens; repository has working `toggle*`/`getTrashedItems` logic that the screens ignore (`favorites_screen.dart`, `archive_screen.dart`, etc.) | none |
| Backup Dashboard + engine | Partial — `BackupEngine`/`UploadQueue`/`BackupScheduler` are genuinely implemented and tested, but upload target `channelId` is hardcoded `0` (`backup_engine.dart:288`) and the upload transport is stubbed | Riverpod `StateNotifier` |
| Backup Settings (v1 + v2) | Partial — two versions exist; v1 (`backup_settings_screen.dart`) is dead (router only wires v2 at `app_router.dart:248`) | Riverpod |
| Restore + engine | Partial — full 6-phase orchestration in `restore_engine.dart`, but depends on stubbed TDLib/channel | Riverpod |
| Metadata system (manifest, partitions, sync, search index, conflict, migration, validator) | Partial — extensively implemented and well-tested in memory; no persistence | plain services |
| Settings (10 screens) | Mostly complete — `AppSettings` persisted via `flutter_secure_storage` (`settings_repository.dart`) | Riverpod + secure storage |
| Background tasks (WorkManager) | **Stubbed** — all handlers only `debugPrint` (`background_backup_service.dart:181-245`); foreground service is a boolean flag | `workmanager` |
| Biometric lock | **Stubbed** — calls `MethodChannel('com.lumovault/biometric')` (`biometric_service.dart:10`) with no native handler, so always returns false | platform channel (missing) |
| Notifications | **Stubbed** — all methods `debugPrint` (`notification_service.dart`) | none |
| Crash reporting | **Stubbed** — `SentryCrashReporter._initialized` is always `false` (`crash_reporter.dart:77`), so it never reports | none |

---

## 3. Code Quality Review

### UI / Presentation
**Strengths.** Consistent Material 3 usage, a real shared widget library (`lib/shared/widgets/lumo_*`), clean `AsyncValue.when` handling in `timeline_screen.dart:129-139`, thoughtful permission-denied and empty states. Good `mounted` guards around async gaps (`timeline_screen.dart:36,56,182`).

**Weaknesses / bugs.**
- **Router recreated every build.** `app.dart:19` calls `createRouter(onboardingCompleted)` inside `build()`. GoRouter should be created once; rebuilding it discards navigation state and is a real performance/UX bug.
- **Dead legacy router.** `app_router.dart:315` `final goRouter = createRouter(false);` runs at module load and is unused.
- **Full device re-scan on every timeline entry.** `timeline_screen.dart:44-63` triggers `scanDevice()` in `initState` with no "already scanned" guard — and that scan reads every file's bytes (see Data layer). On a large library this blocks and re-hashes gigabytes each visit.
- **Non-functional buttons everywhere.** Search/more/favorite/share actions are `onPressed: () {}` (`timeline_screen.dart:119,124`, `media_viewer_screen.dart:19-30`), and timeline tile tap is a `// TODO: Navigate` (`:302`).
- Four feature screens (favorites/archive/hidden/trash) ignore existing repository logic and render static placeholders.

### State Management
**Strengths.** Riverpod DI is clean and layered (`lib/core/di/*`). `BackupEngineNotifier` correctly bridges an imperative engine to reactive state and disposes subscriptions (`backup_providers.dart:241-246`).

**Weaknesses / bugs.**
- **Duplicate provider name collision.** `pendingUploadCountProvider` is declared in **both** `backup_providers.dart:262` and `transfer_providers.dart:298`. Importing both creates an ambiguous-import compile error; at minimum it signals two parallel, competing queue systems.
- **Two competing upload pipelines.** `BackupEngine.UploadQueue` (`backup/engine/upload_queue.dart`) and `TransferQueueNotifier` (`transfer_providers.dart`) both implement enqueue/retry/progress with different retry caps (batchSize vs `< 3`). Only one can be the source of truth.
- `backupStatsProvider` (`backup_providers.dart:250`) does `ref.watch` then `ref.read(...).stats` — stats aren't a listenable, so the UI won't reactively update as the engine's `statsStream` fires; `backup_dashboard_screen.dart:22` also uses `ref.read` for stats, so progress cards won't refresh live.

### Data Layer
**Strengths.** Models are immutable with proper `copyWith`/`==`/`hashCode` (`media_item.dart`, `upload_task.dart`, `transfer_error.dart`). `CaptionMetadata` has a compact, versioned, defensively-parsed serializer (`caption_metadata.dart:26-61`).

**Weaknesses / bugs.**
- **No persistence.** `GalleryRepository._mediaItems` is a `List` (`gallery_repository.dart:18`); everything vanishes on restart. Isar is a dependency in name only.
- **Whole-file read for hashing — OOM risk.** `media_scanner_service.dart:104` `final fileBytes = await file.readAsBytes(); md5.convert(fileBytes)`. For a 2GB video (the stated max) this loads the entire file into memory. Also uses **MD5**, contradicting the SHA-256 dedup spec (PRD §6.5) and weaker for collision resistance.
- **O(n) asset lookups capped at 100.** `getThumbnail`/`getFullFile` (`:143-172`) page only the first 100 assets per album and linear-scan — silently fails for items beyond 100.
- `getTimelineByDate` (`gallery_repository.dart:113`) produces unordered date-key map keys like `"7/16/2026"` that won't sort chronologically in the UI.

### Networking (TDLib)
**Strengths.** The abstraction is well-shaped: request/response correlation via `@extra` id + `Completer` map, broadcast update stream, 30s timeouts (`tdlib_client.dart:87-109`), and a solid `TdLibConnectionManager` with exponential backoff, heartbeat, and reconnect (`tdlib_connection_manager.dart`). Upload/download services correctly parse TDLib update shapes.

**Weaknesses / bugs.**
- **Transport is a no-op** (`tdlib_client.dart:210,223,230`) — nothing actually reaches Telegram.
- **Reconnect uses a bogus key.** `tdlib_connection_manager.dart:133` calls `connect(databaseKey: 'reconnect_key')` — a hardcoded literal instead of the real key, so any reconnect would re-init the encrypted DB with the wrong key.
- **DB key ignored.** `tdlib_client.dart:214-218` `_getDatabaseKey()` returns `'default_key_for_development'` regardless of secure storage.
- **Hardcoded `channelId = 0`.** `backup_engine.dart:288` and `transfer_providers.dart:214` — uploads target chat 0. `StorageChannelService` can find/create the real channel but is never called by the upload path.

### Storage / Persistence
**Strengths.** `ThumbnailCache` (`thumbnail_cache.dart`) is genuinely good — two-tier LRU (memory + disk), size-based eviction, mtime ordering. `TransferQueuePersistence` (`transfer_queue_persistence.dart`) has real JSON round-tripping with a version field and in-progress→queued reset on merge. `SettingsRepository` persists via secure storage with an in-memory cache.

**Weaknesses.** These persistence utilities are never initialized/called from `main.dart` (which only sets up error handling — `main.dart:8-20`). `ThumbnailCache.initialize()` and `TransferQueuePersistence.initialize()` have no caller in the app bootstrap. Backup settings (`BackupSettings`) are entirely in-memory (`backup_providers.dart:18`), separate from persisted `AppSettings`.

### Background Tasks
**Strengths.** WorkManager task registration is correct and complete — constraints, backoff, `@pragma('vm:entry-point')` dispatcher, periodic + one-off tasks (`background_backup_service.dart:33-146`).

**Weaknesses.** Every task body is a stub (`:181-245`); nothing scans or uploads in the background. No native Kotlin worker classes exist (PRD §4.1 lists `BackupWorker.kt`, `UploadForegroundService.kt` — absent from `android/app/src/main/kotlin/`). `_callbackDispatcher` never re-inits Flutter engine/plugins, so even non-stub work couldn't touch platform plugins.

---

## 4. Cross-Cutting Concerns

- **Null safety.** Sound throughout; good use of `?.`/`??`. A few forced-unwraps to watch: `metadata_integration.dart:33` `_handleNewScanItem(item!)` trusts the callback contract; `restore_engine.dart:86` `detection.channelId!` is guarded by prior checks (OK).
- **Exception handling — inconsistent.** Ranges from good typed handling (`TransferError.fromTdLibError`, `restore_engine.dart` try/catch with categorized `RestoreError`) to silent swallowing: `gallery_repository.dart:138` empty `catch (_)`, `storage_channel_service.dart:123,181` swallow-and-continue, `settings_repository.dart:34,64,73` empty catches. The `empty_catches: true` lint (`analysis_options.yaml:11`) is skirted by using `catch (e)` with an empty body.
- **Logging.** Only `debugPrint` scattered across services; no structured logging or levels. Background isolates' `debugPrint` won't surface anywhere useful.
- **Security — several real issues.**
  - Hardcoded, **malformed** API hash: `tdlib_config.dart:13` `'a]4f8b2e1d9c7a6b5e3f2d1c0a9b8e7f6'` — contains a `]`, isn't 32 hex chars, and is committed to source. Meanwhile `telegram_constants.dart:5-9` has a *second, conflicting* set (`apiId = 0`, empty hash). Two sources of truth, both wrong.
  - **Weak "secure" key generation.** `tdlib_providers.dart:95-98` `_generateSecureKey()` derives the DB encryption key from `DateTime.now()` — predictable, not cryptographic. This is the key protecting the Telegram session DB.
  - Biometric app-lock is non-functional (no native side), so "privacy lock enabled" in settings is misleading.
- **Dependencies / deprecations.**
  - **Isar 3.1.0 is unmaintained/discontinued** upstream; committing to it for the persistence layer is a risk.
  - Riverpod `StateNotifierProvider`/`StateNotifier` are legacy as of Riverpod 2.x (superseded by `Notifier`/`AsyncNotifier`).
  - `tdlib: ^1.6.0` — verify this package is maintained and ships current TDLib binaries for both ABIs.
- **Platform-specific.** iOS has no permission usage strings wired to these flows and no TDLib setup; `MainActivity.kt` has no method-channel handlers for the biometric channel it's called with. Android manifest is reasonable (scoped media perms, foreground-service-data-sync, POST_NOTIFICATIONS) but declares `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, which can trigger Play Store policy review.
- **Test coverage gaps.** Good breadth on pure logic (~40 test files: metadata services, upload queue, scheduler, restore engine, error models). But: no tests for the real TDLib path (untestable by design), no widget tests for the stubbed screens, and tests validate in-memory behavior that won't match real Isar/TDLib. Coverage is high on the throwaway layer and zero on the release-critical layer.

---

## 5. Ratings (1–10)

| Dimension | Score | Justification |
|---|---:|---|
| Architecture & Code Organization | **7** | Clean feature-first layout, sensible DI, good separation. Docked for duplicate/competing queue systems, `pendingUploadCountProvider` name collision, and a `domain/` layer that's specified but mostly missing. |
| UI/UX Implementation | **6** | Polished M3 shells and shared widgets, but Media Viewer/Albums/Search/Favorites/Archive/Hidden/Trash are placeholders and many buttons are no-ops. |
| Performance & Efficiency | **4** | Full-device re-scan on every timeline visit, whole-file `readAsBytes` for hashing (OOM risk), router rebuilt per frame, stats providers that don't react. Thumbnail cache is the bright spot. |
| Error Handling & Robustness | **5** | Strong typed error models and a global handler/zone, undercut by numerous empty catches and a crash reporter that never initializes. |
| Security | **3** | Committed malformed API hash, timestamp-derived DB encryption key, hardcoded dev DB key, non-functional biometric lock. Foundational, not cosmetic. |
| Test Coverage | **5** | Broad unit tests, but concentrated on in-memory logic that will be replaced; release-critical TDLib/persistence paths are untested. |
| Maintainability | **6** | Readable, consistent style and good linting intent. Docked for two settings systems, two queue systems, v1/v2 duplicate screens, and dead code. |
| **Overall Readiness for Release** | **3** | The two pillars of the product — Telegram transport and local persistence — are stubbed. Demoable prototype, not a shippable app. |

---

## 6. Prioritized Recommendations (impact vs. effort)

1. **Implement the real TDLib transport** (`tdlib_client.dart:184-231`). Highest impact — nothing works without it. Wire `_createClient`/`_sendJson`/`_receiveJson` to the `tdlib` package's native interface and run receive in an isolate. High effort, but it's the product.
2. **Wire in Isar (or commit to an alternative) for persistence.** Annotate `MediaItem`/`UploadTask`/etc. as collections, generate adapters, and back `GalleryRepository` with the DB. High impact, medium-high effort. Given Isar 3's maintenance status, evaluate `sqflite`/`drift` before locking in.
3. **Fix the security foundation** (low effort, high impact): replace `_generateSecureKey` with `Random.secure()`-derived 32-byte keys (`tdlib_providers.dart:95`); make `_getDatabaseKey` read from secure storage (`tdlib_client.dart:214`); fix `reconnect()` to reuse the real key (`tdlib_connection_manager.dart:133`); move API credentials to `--dart-define`/build config and delete the malformed/duplicate constants.
4. **Connect the real `channelId`** from `StorageChannelService` into the upload path (`backup_engine.dart:288`, `transfer_providers.dart:214`). Low effort once TDLib works; without it uploads target chat 0.
5. **Consolidate the two upload queues and the duplicate `pendingUploadCountProvider`.** Pick `BackupEngine` or `TransferQueueNotifier` as canonical, delete the other. Fixes an ambiguous-import hazard and halves the surface area. Low-medium effort.
6. **Move device scanning off the UI thread and out of `initState`.** Add a "scanned" guard, stream hashing (chunked digest instead of `readAsBytes`), switch MD5→SHA-256, and run in an isolate (`media_scanner_service.dart:104`, `timeline_screen.dart:44`). Medium effort, big perf/stability win.
7. **Create the GoRouter once** and use `refreshListenable`/redirect for onboarding instead of `createRouter` in `build()` (`app.dart:19`); persist onboarding completion via the already-existing `AppSettings.onboardingCompleted` instead of the throwaway in-memory provider.
8. **Implement the stubbed screens** (Media Viewer, Albums, Search, Favorites, Archive, Hidden, Trash) against the repository logic that already exists. Medium effort, high UX impact — the logic is done, only wiring is missing.
9. **Make stats reactive.** Convert `backupStatsProvider` to a `StreamProvider` off `statsStream` so the dashboard updates live (`backup_providers.dart:250`, `backup_dashboard_screen.dart:22`). Low effort.
10. **Replace empty catches with logging + actually initialize the crash reporter** (or drop the Sentry stub). Bootstrap `ThumbnailCache`/`TransferQueuePersistence`/`NotificationService` in `main.dart`. Low effort, improves observability.

**Before the next milestone**, items 1–5 are the gate: they convert the prototype into something that authenticates, persists, and uploads securely. Items 6–10 are the fast-follow quality pass.
