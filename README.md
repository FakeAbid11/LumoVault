# 📱 LumoVault — Original Quality Backup Powered by Telegram

<p align="center">
  <img src="android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" alt="LumoVault Logo" width="120">
</p>

<p align="center">
  <strong>Original-quality photo & video backup, powered by your own Telegram channel.</strong>
</p>

<p align="center">
  Never lose another photo. LumoVault backs up your device photos and videos to a channel <b>you</b> own on Telegram — no compression, no third-party cloud. A built-in metadata layer travels with your files, so a second device can restore the same catalog: albums, captions, statuses, and timestamps.
</p>

<p align="center">
  <a href="#-features">Features</a> •
  <a href="#-getting-started">Get Started</a> •
  <a href="#-usage">Usage</a> •
  <a href="#-technical-details">Technical</a> •
  <a href="#-status">Status</a>
</p>

<p align="center">
  <img src="https://github.com/FakeAbid11/LumoVault/actions/workflows/ci.yml/badge.svg" alt="CI">
  <img src="https://img.shields.io/badge/Flutter-3.44.6-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/Tests-721%20passing-brightgreen" alt="Tests">
</p>

---

## ✨ Features

| | |
| :--- | :--- |
| 🗂️ **Original-quality backup** | Files uploaded as documents via TDLib — never recompressed. |
| 📁 **Opt-in folder selection** | Choose exactly which device folders to back up. |
| ⚡ **Incremental scanning + dedup** | SHA-256 hashing means only new or changed files are uploaded. |
| 🔄 **Background, periodic backup** | WorkManager keeps the queue moving, with progress notifications. |
| 📅 **Unified timeline** | Date-grouped view merging local items with items in your channel. |
| 🖼️ **Local gallery** | Albums, search, and a full-screen media viewer with video playback. |
| 📥 **Restore** | Scan your Telegram channel and download items back to the device. |
| 🧬 **Metadata sync** | Albums, captions, and state mirrored as JSON manifests/partitions. |
| 🗑️ **Trash with auto-purge** | Deleted items rest for 30 days before permanent removal. |
| 🙈 **Hidden album & Archive** | Keep sensitive or old items out of the main views. |
| 🔒 **App lock** | PIN plus optional biometric unlock. |
| 🩺 **Crash reporting** | Sentry in release builds (opt-in via `SENTRY_DSN`). |

## 🚀 Getting Started

### Prerequisites

- **Flutter 3.44.6 stable** (Dart ^3.12.2)
- A Telegram account, plus an **API ID / API hash** from [my.telegram.org](https://my.telegram.org) — LumoVault connects to your account as a client app and uses a channel you own as storage.

### Run

```sh
flutter pub get
flutter run \
  --dart-define=LUMOVAULT_TELEGRAM_API_ID=<your_api_id> \
  --dart-define=LUMOVAULT_TELEGRAM_API_HASH=<your_api_hash>
```

## 📖 Usage

### Build an APK

```sh
flutter build apk --debug \
  --dart-define=LUMOVAULT_TELEGRAM_API_ID=<your_api_id> \
  --dart-define=LUMOVAULT_TELEGRAM_API_HASH=<your_api_hash>
```

> 💡 No local Android SDK required for releases — CI builds and uploads the APK as an artifact.
>
> 💡 Add `--dart-define=SENTRY_DSN=<dsn>` to enable Sentry crash reporting.

## ⚙️ Technical Details

### How it works

```
 📱 Device photos & videos
      │
      │  incremental scan (photo_manager) + SHA-256 hashing
      ▼
 📤 Upload queue (drift-persisted)
      │
      │  TDLib document upload — original quality
      ▼
 📦 Your Telegram channel
      │
      │  channel scan + manifest/partition JSON
      ▼
 📅 Timeline   📥 Restore   🧬 Metadata sync
```

### Tech stack

| Area | Choice |
| :--- | :--- |
| 🎨 Language / framework | **Flutter 3.44.6** (stable), Dart ^3.12.2 |
| 🧠 State management | Riverpod 2.6.1 |
| 🧭 Navigation | go_router 14.8.1 |
| 🗄️ Database | drift 2.20 (SQLite, codegen) |
| 🖼️ Media scanning | photo_manager |
| 📨 Telegram client | TDLib (`tdlib` package) |
| ⏰ Background work | workmanager (+ vendored patched `workmanager_android`) |
| 🔐 Secure storage | flutter_secure_storage |
| ✅ Permissions | permission_handler |
| ▶️ Video playback | video_player |
| 🩺 Crash reporting | sentry_flutter |

### Project structure

```
lib/
├── core/            # DI, drift DB, storage, security, router, errors, TDLib
├── features/
│   ├── onboarding/  # Welcome → permissions → folders → Telegram connect
│   ├── gallery/     # Local tab, Timeline, Albums, Search, media viewer
│   ├── backup/      # Dashboard, upload queue, engine, scheduler
│   ├── restore/     # Channel scan, restore engine, progress
│   ├── metadata/    # Manifests/partitions, sync coordinator, search index
│   ├── app_lock/    # PIN + biometric gate
│   ├── hidden/      # Hidden album
│   ├── archive/     # Archived items
│   ├── trash/       # Trash with 30-day retention
│   └── settings/    # Storage, privacy, notifications, appearance, …
├── shared/          # Lumo design-system widgets, shared providers
└── main.dart

packages/workmanager_android/  # Vendored plugin, patched to register plugins
                               # on the background isolate
test/                          # Unit + widget tests (mirrors lib/)
```

### Testing & quality

```sh
flutter test          # 721 tests (unit + widget)
dart format --output=none --set-exit-if-changed .
dart analyze
```

### CI

`.github/workflows/ci.yml` runs on push/PR to `main` and `develop`:

1. **Analyze** — format check + `dart analyze --fatal-infos`
2. **Test** — `flutter test --coverage`, uploaded to Codecov
3. **Build APK** — debug APK, uploaded as an artifact

The build job needs two repository secrets:
`LUMOVAULT_TELEGRAM_API_ID` and `LUMOVAULT_TELEGRAM_API_HASH`
(Settings → Secrets and variables → Actions).

## 📍 Status

Early stage (v1.0.0). Current focus areas:

- 🔧 Reliability hardening of the backup/scan pipeline and background sync
- 🖼️ Thumbnail handling in the timeline and gallery views
- 🔄 Cross-device metadata restore
