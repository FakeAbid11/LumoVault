import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/auth_service.dart';
import '../auth/telegram_auth_repository.dart';
import '../storage/storage_channel_service.dart';
import '../tdlib/tdlib_client.dart';
import '../tdlib/tdlib_config.dart';
import '../tdlib/tdlib_connection_manager.dart';

/// Secure storage key under which the TDLib database encryption key is stored.
const String kTdLibDatabaseKeyName = 'lumovault_tdlib_db_key';

/// Secure storage instance for TDLib database key.
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

/// TDLib client singleton provider.
///
/// Initialized once and shared across the app.
final tdLibClientProvider = Provider<TdLibClient>((ref) {
  final client = TdLibClient.instance;
  ref.onDispose(() async {
    await client.close();
  });
  return client;
});

/// TDLib database encryption key.
///
/// Stored in Android Keystore via flutter_secure_storage.
/// Generated on first launch, reused on subsequent launches.
final tdLibDatabaseKeyProvider = FutureProvider<String>((ref) async {
  final storage = ref.read(secureStorageProvider);
  return _readOrCreateDatabaseKey(storage);
});

/// TDLib connection manager with auto-reconnect and state tracking.
///
/// Wraps the raw [TdLibClient] with production-grade connection management.
/// The persisted database key is passed in so reconnects reuse the exact
/// same key rather than regenerating one (which would corrupt the DB).
final tdLibConnectionManagerProvider = Provider<TdLibConnectionManager>((ref) {
  final client = ref.read(tdLibClientProvider);
  final manager = TdLibConnectionManager(
    client: client,
    databaseKeyProvider: () =>
        _readOrCreateDatabaseKey(ref.read(secureStorageProvider)),
  );
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// Stream of TDLib connection status changes.
final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  final manager = ref.watch(tdLibConnectionManagerProvider);
  return manager.statusStream;
});

/// Initialize the TDLib client with the database key via the connection manager.
///
/// This provider depends on [tdLibDatabaseKeyProvider] and ensures
/// the client is properly connected before any auth operations.
final tdLibInitializedProvider = FutureProvider<bool>((ref) async {
  final manager = ref.read(tdLibConnectionManagerProvider);
  final databaseKey = await ref.watch(tdLibDatabaseKeyProvider.future);

  await manager.connect(databaseKey: databaseKey);
  return true;
});

/// Auth service provider.
///
/// Returns [TelegramAuthRepository] which implements [AuthService].
/// Uses the connection manager for all TDLib communication.
final authServiceProvider = Provider<AuthService>((ref) {
  final manager = ref.read(tdLibConnectionManagerProvider);
  final service = TelegramAuthRepository(
    manager.client,
    () => ref.read(tdLibInitializedProvider.future),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

/// Storage channel service provider.
final storageChannelServiceProvider = Provider<StorageChannelService>((ref) {
  final manager = ref.read(tdLibConnectionManagerProvider);
  return StorageChannelService(client: manager.client);
});

/// Whether the user is currently authenticated.
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authStateAsync = ref.watch(_authStateStreamProvider);

  // While the stream hasn't emitted yet, fall back to the synchronous value.
  if (authStateAsync is AsyncLoading) {
    final authService = ref.watch(authServiceProvider);
    return authService.currentState == AuthState.authenticated;
  }

  return authStateAsync.value == AuthState.authenticated;
});

/// Internal stream provider that bridges the auth service's stateStream.
final _authStateStreamProvider = StreamProvider<AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.stateStream;
});

/// In-flight (or completed) database-key resolution.
///
/// Two call sites consume the key — [tdLibDatabaseKeyProvider] and the
/// connection manager's reconnect key provider — and both can run
/// concurrently (e.g. a reconnect while the initial connect is still
/// bootstrapping). Without single-flight, both would read null, generate
/// two different keys, and the second write would orphan the first key's
/// encrypted TDLib database. The key never legitimately changes, so
/// memoizing it for the process lifetime is safe.
Future<String>? _databaseKeyFuture;

/// Read the persisted TDLib database key, creating one on first run.
///
/// The key is a cryptographically random [TdLibConfig.databaseKeyLength]-byte
/// value, base64-encoded for storage. It is generated once and reused on every
/// subsequent launch and reconnect so the encrypted TDLib database remains
/// readable.
Future<String> _readOrCreateDatabaseKey(FlutterSecureStorage storage) {
  return _databaseKeyFuture ??= _doReadOrCreateDatabaseKey(storage);
}

Future<String> _doReadOrCreateDatabaseKey(FlutterSecureStorage storage) async {
  try {
    final existing = await storage.read(key: kTdLibDatabaseKeyName);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final key = _generateSecureKey();
    await storage.write(key: kTdLibDatabaseKeyName, value: key);
    return key;
  } catch (e) {
    // A failed attempt must not poison the memo for the rest of the
    // process — let the next caller retry.
    _databaseKeyFuture = null;
    rethrow;
  }
}

/// Generate a cryptographically secure random key.
///
/// Uses [Random.secure] to produce [TdLibConfig.databaseKeyLength] random
/// bytes, returned base64-encoded. Standard base64 (not URL-safe) — TDLib's
/// JSON interface expects `bytes` fields in standard base64 and can reject
/// the '-'/'_' characters base64Url produces.
String _generateSecureKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(
    TdLibConfig.databaseKeyLength,
    (_) => random.nextInt(256),
  );
  return base64.encode(bytes);
}
