import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The app's secure-storage configuration, shared by every call site.
///
/// flutter_secure_storage's Android default is `encryptedSharedPreferences:
/// false`. Constructing it with no options at all — which every call site here
/// used to do — therefore writes straight into a plaintext
/// `FlutterSecureStorage.xml` shared-preferences file, so the TDLib database
/// key, the app-lock PIN blob and the whole settings document (including
/// `storageChannelId`) sat unencrypted on disk despite comments claiming
/// Keystore backing.
///
/// The plugin migrates existing plaintext values into the Keystore-backed
/// store the first time it is constructed with the flag set — it decodes each
/// one, writes it to the encrypted file and removes the plaintext copy — so an
/// existing install keeps its database key rather than being orphaned into a
/// re-login and a duplicate backup channel.
///
/// Kept as a single `const` rather than three inline constructors so no future
/// call site can silently drift back to the insecure default.
const FlutterSecureStorage lumoSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
