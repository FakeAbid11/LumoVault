# LumoVault — Technical & Product Review

*Independent audit of the full Flutter codebase. Every claim is anchored to a file path and, where possible, a line number. Draft assembled from direct inspection plus module-by-module deep reads.*

- **Repo:** `LumoVault-main` · **Branch:** `main` · **Commit at review:** `1bdb8d7`
- **Scale:** 193 Dart source files, ~41,373 LOC (excl. generated); ~20,770 LOC of tests across 89 files (983 `test`/`testWidgets` calls, 193 `group`s).
- **Static analysis at review time:** `dart analyze` → **"No issues found!"** (clean). CI enforces `dart analyze --fatal-infos` + `dart format --set-exit-if-changed`.
- **Project age:** 113 commits, 2026-08-25 → 2026-09-06 (~13 days), effectively one developer.

---

## 1. App Overview

**What it does.** LumoVault backs up a phone's photos and videos, at original quality, into a *private Telegram channel the user owns* — there is no first-party backend. It uses TDLib (the native Telegram client library) to upload files as **documents** (avoiding server-side recompression), and layers a Google-Photos-style browsing experience on top: unified timeline, map, search, people/faces, albums, trash, archive, hidden album, and restore-to-a-second-device.

**Platform.** **Android only.** `minSdk 23`, `target/compile 36` (`android/app/build.gradle.kts:38-41`). No `ios/` directory exists; `pubspec.yaml:117` disables iOS launcher icons. TDLib has Linux/Windows load branches for desktop debugging only.

**Core user flows.**
1. **Onboarding** — Welcome → Permissions → Background-permissions → Folder selection → Telegram connect (`lib/features/onboarding/...`, routed in `lib/core/router/app_router.dart:99-123`).
2. **Backup** — incremental media scan (`photo_manager`) → SHA-256 dedup → upload queue → WorkManager background/foreground service uploads to the channel.
3. **Browse** — Local / Timeline / Map / People tabs in an `IndexedStack` shell (`app_router.dart:126-195`), plus Search, media viewer with video playback.
4. **Metadata sync** — albums/captions/status mirrored as JSON manifest + partition files in the channel, so a second device rebuilds the catalog (two-way sync).
5. **Restore** — scan the channel, rebuild the local catalog + thumbnails; originals are saved to the camera roll on demand per item.
6. **Security** — optional PIN + biometric app lock.

**Architecture pattern.** Feature-first, **two-layer (data + presentation)** with dedicated `engine/` packages for backup and restore orchestration. State management is **Riverpod 2.6.1** (providers only, no codegen); navigation is **go_router 14.8.1** (`StatefulShellRoute.indexedStack`); persistence is **Drift 2.x** (SQLite, code-gen). DI is entirely Riverpod providers grouped under `lib/core/di/*`.

> **Documentation drift (finding):** `PRD.md` is stale relative to the implementation. It specifies **Isar 3.1.x** as the database (`PRD.md:91`, `:119`) and "**Clean Architecture with … Use Cases / domain entities / repo interfaces**" (`PRD.md:101-123`, `:112-115`). The code has **zero Isar references** (fully on Drift) and **no `domain/`/`usecase/` layer anywhere** — it is a lighter repository/MVVM pattern. `README.md` *is* accurate (lists drift 2.20). Treat `README.md`, not `PRD.md`, as ground truth.

**Folder layout (verified):**
```
lib/
├── core/       # di, database (drift), tdlib, auth, security, permissions,
│               # notifications, error_handling, logging, storage, theme, router
├── features/   # onboarding, gallery, backup, restore, metadata, people,
│               # app_lock, hidden, archive, trash, duplicates, settings
│               #   each: data/ + presentation/ (+ engine/ for backup, restore)
├── shared/     # design-system widgets, shared providers/utils
└── main.dart   # bootstrap: DB open → hydrate → wire sync listeners → run
packages/workmanager_android/  # vendored, patched plugin (see §4)
```

`lib/main.dart` is a notably careful bootstrap (heavily commented) that opens the DB, hydrates the in-memory gallery read model before first frame, eagerly reads lazy providers to *install* the metadata/sync/delete callbacks, applies the persisted onboarding + debug-mode flags, and wraps `runApp` in a Sentry-reporting error zone with a `BootstrapErrorApp` fallback (`lib/main.dart:41-62`).

---

## 2. Feature Inventory

*(state per module — filled from module deep-reads)*

| Feature / Screen | Route | State | Notes |
|---|---|---|---|
| Onboarding (Welcome→Perms→BgPerms→Folders→Telegram) | `/onboarding/*` | _pending_ | |
| Telegram connect / login | `/connect-telegram` | ⚠️ partial | **2FA bug** — see §3 Telegram |
| Local gallery | `/local` | _pending_ | |
| Timeline (unified local+cloud) | `/timeline` | _pending_ | |
| Map (OpenStreetMap) | `/map` | _pending_ | |
| Search | `/gallery/search` | _pending_ | |
| Media viewer (local + telegram) | `/gallery/media/:id`, `/gallery/telegram-media/:id` | _pending_ | |
| People / Faces | `/people`, `/people/:id` | ⚠️ unverified on device | ONNX SCRFD+ArcFace |
| Backup dashboard / settings / stats | `/settings/backup*` | _pending_ | |
| Restore | `/restore`, `/restore/progress` | ⚠️ partial | rehydration, not bulk file restore |
| Metadata sync | (no UI route; background) | _pending_ | |
| Trash (30-day) / Hidden / Archive / Duplicates | `/settings/*` | _pending_ | |
| App lock (PIN + biometric) | gate widget | _pending_ | |
| Settings (general/media/storage/privacy/appearance/notifications/developer/about/account) | `/settings/*` | _pending_ | E2E-encryption toggle = "Coming soon" (`privacy_settings_screen.dart:76`) |

---

## 3. Code Quality Review (by module)

### Telegram / TDLib / Auth — `lib/core/tdlib/*`, `lib/core/auth/*`, `lib/features/gallery/data/repositories/telegram_*`

**State:** mostly complete and well-tested. `TdLibClient` (FFI singleton + receive-loop isolate), `TdLibConnectionManager` (state machine + exponential backoff), upload/download services, and `StorageChannelService` (find/create private supergroup) are complete. Deletion service complete but **untested**.

**Strengths.**
- Request/response correlation by monotonic `@extra` id with a bounded `_expiredRequestIds` set so late replies can't be misread as updates (`tdlib_client.dart:99-104, 277-281, 427-432`).
- Blocking native receive runs on a dedicated isolate (`tdlib_client.dart:396-409, 514-529`).
- "Subscribe-before-request" race fix in both transfer services (`telegram_upload_service.dart:136-161`, `telegram_download_service.dart:177-214`).
- Typed errors with `FLOOD_WAIT_<n>` extraction (`tdlib_exception.dart:37-45, 82-92`).
- Duplicate-channel prevention via a tri-state result that distinguishes "not found" from "lookup failed", searching the archive list too (`storage_channel_service.dart:34-55, 221-232`).
- Reconnect deliberately preserves backoff and reuses the DB key so the encrypted session stays readable (`tdlib_connection_manager.dart:172-200`).

**Weaknesses / bugs.**
- **HIGH — 2FA users are wrongly treated as authenticated.** `verifyCode` returns `AuthSuccess` whenever `checkAuthenticationCode` doesn't throw (`telegram_auth_repository.dart:200-217`); `AuthPasswordRequired` is only returned on `PASSWORD_HASH_INVALID`, which is the *wrong-password* error and never occurs here. With 2FA on, TDLib succeeds the code check then emits `authorizationStateWaitPassword` **via the update stream**, but the connect screen consumes the returned `AuthResult`, not `stateStream` (`telegram_connect_screen.dart:190-195`), so the user is driven into `_onAuthSuccess()` while TDLib is still unauthorized — the password screen never appears and every later request fails. The repo test even acknowledges the gap without asserting behavior (`telegram_auth_repository_test.dart:273-275`).
- **MEDIUM — original-quality guarantee may be defeated.** `telegram_upload_service.dart:208` sets `'disable_content_type_detection': false`; with detection enabled Telegram may auto-convert an image/video document into a compressed photo/video, contradicting the stated "never recompressed" premise (asserted in `telegram_upload_service_test.dart:184-204`).
- **MEDIUM — stale singleton after `close()`.** `tdlib_client.dart:358` sets `_instance = null` while `TdLibConnectionManager` keeps the old instance (`tdlib_connection_manager.dart:43`); a later reader of `TdLibClient.instance` can construct a *second* client racing the same native session.
- **MEDIUM — `Stream.first` subscription leaks on timeout** during bootstrap (`telegram_auth_repository.dart:80-96`); two concurrent update subscriptions live during init.
- LOW: progress mis-attribution when the provisional file id is null (`telegram_upload_service.dart:214-216, 307`); `isAuthenticated()` collapses transient errors to `false` (`tdlib_client.dart:298-306`); `TdLibConfig.maxFileSizeBytes` (2 GB) is defined but never enforced pre-upload (`tdlib_config.dart:38`); `close()` awaits a 30-s-timeout `close` request before teardown (`tdlib_client.dart:322`).

**Security (Telegram).** No hardcoded secrets — `apiId`/`apiHash` are `--dart-define` compile-time constants defaulting to 0/empty (`tdlib_config.dart:15-25`); `.env*` gitignored. TDLib DB encryption key is 32 bytes from `Random.secure()`, stored in `flutter_secure_storage` with a single-flight memo to avoid divergent keys (`tdlib_providers.dart:133-176`). Phone/code/password are never logged or persisted by the app. Caveats: `--dart-define` values are extractable from a shipped APK (inherent to any Telegram client); Sentry's default `enablePrintBreadcrumbs` can capture `debugPrint` auth-*error* metadata (`crash_reporter.dart:136-144`) — no scrubbing configured.

### Restore — `lib/features/restore/*`, `lib/core/di/channel_scan_providers.dart`

**Key framing:** "Restore" is **catalog/timeline rehydration** (rebuild the metadata DB + download thumbnails), **not** a bulk restore of originals to the camera roll. Originals are saved on demand, per item, by the viewer's "Save to gallery" button (`telegram_media_viewer_screen.dart:67-141` → `gallery_save_service.dart:14-62`).

**Strengths.**
- Channel pagination is correct: empty-page terminator + non-advancing-cursor bail-out prevents truncation and infinite loops (`channel_scan_service.dart:383-392`, `restore_repository.dart:148-158`), with bounded per-page retry (`restore_repository.dart:168-199`); regression-tested.
- "No backup" vs "lookup failed" are distinguished so failed scans stay retryable (`channel_scan_service.dart:92-115`, `restore_repository.dart:35-54`).
- Atomic resume-state writes (tmp + rename) that never block restore (`restore_state_store.dart:62-73`).
- Tombstones honored on rebuild (deletions aren't resurrected), and `backedUpAt` is taken from the caption not `now()` (`restore_engine.dart:209, 324-328`); tested.
- On-demand thumbnail fetcher coalesces in-flight requests + failure cooldown (`channel_scan_providers.dart:60-131`).

**Weaknesses / bugs.**
- **Manifest is never stored after restore.** `restore_engine.dart:330-334` guards on `manifestService.getCurrentManifest()` (null during a fresh restore) and, even if non-null, would `setManifest` to itself — a no-op. Post-restore `manifestService` has no manifest and `_partitionHashes` is empty, so `getPartitionHash()` returns null for all partitions, corrupting the dirty-check baseline for the *next* backup/sync.
- **Differential-restore-by-hash is effectively unimplemented (dead code).** `_existingHashes`/`isAlreadyRestored()`/`RestoreStateStore` are wired but the only reader has no non-test caller; DB rebuild re-creates every item unconditionally and the only real skip is `ThumbnailCache.contains(localId)` (`restore_engine.dart:438, 514-551`).
- **Engine restore drops native photos/videos.** `restore_repository.fetchChannelMessages` handles only `messageDocument` (`restore_repository.dart:117-134`) while the scanner also handles photo/video (`channel_scan_service.dart:331-369`) — a silent asymmetry.
- **Cancellation doesn't interrupt detect/manifest/message phases** and can flip the UI back off "failed"; `RestorePhase.cancelled` is never actually produced (`restore_engine.dart:182-192, 307-310`).
- **Thumbnail temp files leak** in the engine (never deleted, unlike the scanner) (`restore_engine.dart:473-478` vs `channel_scan_service.dart:506-510`).
- Empty-but-valid channel misreported as `manifestCorrupted` (non-retryable) (`restore_engine.dart:172-175`); corrupt manifest JSON reported as retryable "unknown" instead (`restore_repository.dart:108`, engine `272-283`).
- Dead code + a hardcoded Android path: `downloadOriginal`/`saveRestoredFile`/`buildMediaItemFromMessage`, and `storageBasePath: '/data/user/0/com.lumovault.app/files'` (`restore_providers.dart:56`). `buildMediaItemFromMessage` even re-introduces the `backedUpAt: DateTime.now()` bug the engine avoids.
- Unbounded in-memory accumulation of the whole channel history + several parallel maps for large libraries (`restore_repository.dart:96-161`, `restore_engine.dart:178-179, 362`).
- Misleading cancel dialog ("You can resume it later." then hard-resets and navigates to onboarding) (`restore_progress_screen.dart:431-433`); detection runs 2–3× per entry.

### Backup engine & background work — _pending_
### Metadata sync — _pending_
### Gallery data layer & database — _pending_
### People / faces — _pending_
### Core infrastructure (security, storage, notifications, errors) — _pending_
### UI / presentation / theme / settings — _pending_

---

## 4. Cross-Cutting Concerns

**Platform / Android hardening (strong).**
- `android:allowBackup="false"`, `fullBackupContent="false"`, and a `data_extraction_rules.xml` that excludes *every* domain from cloud backup and device-transfer — deliberately, because the TDLib session key lives in the Keystore-backed store and can't be exported (`android/app/src/main/AndroidManifest.xml`, `android/app/src/main/res/xml/data_extraction_rules.xml`).
- Release signing **fails to UNSIGNED** rather than silently falling back to the public debug key (`android/app/build.gradle.kts` `hasReleaseSigning`), R8 minify + resource shrink enabled with keep rules.
- Scoped media permissions for API 33+ with legacy fallback ≤32; foreground-service type `dataSync` declared for API 34+ (`AndroidManifest.xml`).
- `FlutterFragmentActivity` used so `local_auth` BiometricPrompt works (`MainActivity.kt`).

**Secrets.** None hardcoded (verified by grep across `lib/`). API creds + `SENTRY_DSN` are `--dart-define`; `.env*` gitignored.

**Dependency currency (weakness).** `flutter pub outdated` shows most direct deps **major versions behind** as of the review date:

| Package | Current | Latest | Gap |
|---|---|---|---|
| flutter_riverpod | 2.6.1 | 3.4.3 | **major** |
| go_router | 14.8.1 | 18.0.1 | **4 majors** |
| flutter_secure_storage | 9.2.4 | 11.0.0 | **2 majors** |
| sentry_flutter | 8.14.2 | 9.29.0 | **major** |
| permission_handler | 11.4.0 | 13.0.2 | **2 majors** |
| flutter_map (+cluster) | 7.0.2 / 1.4.0 | 8.3.2 / 8.2.2 | major |
| cached_network_image | 3.4.1 | 4.0.0 | major |
| device_info_plus | 11.5 | 13.2 | 2 majors |
| workmanager | 0.9.3 | 0.10.9 | minor (relevant — see vendored patch) |
| flutter_lints | 5.0.0 | 6.0.0 | major (dev) |

Transitive red flags: `sqlite3_flutter_libs` latest is `0.6.0+eol`, `flutter_secure_storage_macos` discontinued, `js` discontinued. None are breakage *today*, but the Sentry and secure-storage majors in particular carry security/analytics fixes worth tracking.

**CI (mostly strong, one gap).** `.github/workflows/ci.yml` runs analyze (`--fatal-infos` + format), test with coverage → Codecov, and a debug-APK build. **Gap:** it triggers only on `workflow_dispatch` (manual) — there is no automatic gating on push/PR, so a bad commit isn't caught until someone runs it.

**Testing.** ~983 test cases, ~1:2 test:source LOC — high for a 2-week-old project. **Gaps:** the `integration_test` dev-dependency has **no tests** (no `integration_test/` dir); no end-to-end / on-device coverage; several destructive/edge paths untested (Telegram deletion, restore cancellation, manifest-persist-after-restore). Face pipeline is unit-tested only and unverified against real photos (per project notes; corroborated by DB migrations v10–v12 repeatedly clearing face data).

**Misc.** Git identity is misconfigured for 25 commits (`Your Name <your_email@example.com>`). A stray `.freebuff/` entry sits at the end of `.gitignore` (intentional per commit `b3fe88d`, but odd).

---

## 5. Ratings

_(finalized after all module reads — placeholder)_

---

## 6. Prioritized Recommendations

_(finalized after all module reads — placeholder)_
