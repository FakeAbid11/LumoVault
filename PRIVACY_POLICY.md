# Privacy Policy

**Effective Date:** September 2026  
**Last Updated:** September 2026

LumoVault ("the App") is an open-source Android application that provides original-quality photo and video backup powered by Telegram. This Privacy Policy explains what data the App accesses, how it is used, and your rights.

---

## 1. Data We Collect

LumoVault accesses the following data on your device:

### a. Photos and Videos
- The App reads your device's photo and video library to display media and back them up to your personal Telegram account.
- Thumbnails are generated locally for grid display.
- Full-resolution files are read only when you initiate a backup or view a specific item.

### b. GPS / Location Data
- The App reads GPS coordinates embedded in photo/video metadata (EXIF) to display media on a map.
- Location access is optional. If granted, the App uses your device location to center the map.
- Location data never leaves your device.

### c. Telegram Credentials
- The App connects to Telegram's servers via the TDLib library to back up your media to your own Telegram account.
- Your Telegram phone number and authentication tokens are stored locally using Android's secure storage (encrypted with device credentials).
- The App does not access or store your Telegram password unless you enable Two-Step Verification, in which case it is processed locally and transmitted only to Telegram.

### d. Biometric Data
- If you enable App Lock, the App uses your device's biometric sensor (fingerprint or face) for authentication.
- Biometric data is processed entirely by your device's operating system. The App never accesses, stores, or transmits biometric data.

### e. Device Information
- The App collects basic device information (model, OS version, battery status) to manage background backup scheduling and optimize performance.
- This data is stored locally and is not transmitted to any third party.

---

## 2. How We Use Your Data

| Data | Purpose |
|---|---|
| Photos & Videos | Display in gallery, backup to your Telegram account |
| GPS coordinates | Display media on a map within the App |
| Telegram credentials | Authenticate with Telegram for backup |
| Biometric data | Unlock the App (processed by your device only) |
| Device information | Manage background backup scheduling |

**We do not use your data for advertising, analytics, profiling, or any purpose other than those described above.**

---

## 3. Data Storage and Security

- All data is stored locally on your device in an encrypted SQLite database.
- Telegram authentication tokens are stored using Android's `flutter_secure_storage`, which uses the Android Keystore system.
- Photos and videos backed up to Telegram are stored in your personal Telegram cloud, under your account.
- The App does not maintain any external servers. There is no cloud database or backend controlled by the App developer.

---

## 4. Third-Party Services

### Telegram (TDLib)
- Used as the backup destination for your photos and videos.
- Your media is stored in your own Telegram account.
- Subject to [Telegram's Privacy Policy](https://telegram.org/privacy).

### Sentry (Crash Reporting)
- The App optionally sends crash reports to Sentry to help identify and fix bugs.
- Crash reports include stack traces, device information, and error messages. They do **not** include your photos, videos, location, or Telegram credentials.
- Crash reporting is opt-in: it only activates if the developer provides a Sentry DSN at build time. If no DSN is configured, no crash data is sent.
- Subject to [Sentry's Privacy Policy](https://sentry.io/privacy/).

### OpenStreetMap
- Map tiles are fetched from OpenStreetMap servers when you view the map.
- Tile requests reveal your approximate map viewport (zoom level and coordinates) to OpenStreetMap.
- Subject to [OpenStreetMap's Privacy Policy](https://wiki.openstreetmap.org/wiki/Privacy_Policy).

---

## 5. Data Sharing

**We do not sell, trade, or share your personal data with any third parties** beyond what is described in Section 4.

The App does not contain third-party advertising SDKs, analytics trackers, or data broker integrations.

---

## 6. Data Retention

- Your photos, videos, and associated data remain on your device until you delete them.
- Backed-up media remains in your Telegram account according to Telegram's retention policies.
- Crash reports (if enabled) are retained by Sentry for up to 90 days.
- The App does not retain any data on external servers.

---

## 7. Your Rights

Depending on your jurisdiction, you may have the following rights:

- **Access:** View all data the App stores about your media and settings.
- **Deletion:** Delete any backed-up media from Telegram and remove local data by uninstalling the App or using the App's Trash feature.
- **Export:** Export your media files at any time (they are your original files).
- **Revoke Permissions:** Revoke photo, location, or biometric permissions at any time through Android Settings.

### GDPR (European Economic Area)
You have the right to access, rectify, erase, restrict processing, and port your data. The App processes data locally; no data is transferred to the developer's servers.

### CCPA (California)
The App does not sell personal information. You have the right to know what data is collected, request deletion, and opt out of any sale (the App does not sell data).

---

## 8. Children's Privacy

The App is not directed at children under 13 (or under 16 in the EU). The App does not knowingly collect data from children.

---

## 9. Changes to This Policy

We may update this Privacy Policy from time to time. Changes will be reflected in the App's About screen and on this page. Continued use of the App after changes constitutes acceptance of the updated policy.

---

## 10. Contact

If you have questions about this Privacy Policy, contact us at:

**Email:** [your-email@example.com]

---

## 11. Open Source

LumoVault is open-source software licensed under the MIT License. You can review the source code at:

**Repository:** [github.com/FakeAbid11/LumoVault](https://github.com/FakeAbid11/LumoVault)
