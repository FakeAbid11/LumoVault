import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tdlib/tdlib.dart';
// ignore: implementation_imports
import 'package:tdlib/src/tdclient/platform_interfaces/td_native_plugin_real.dart'
    as tdlib_native;

import 'tdlib_config.dart';
import 'tdlib_exception.dart';

/// `TdPlugin.instance`/`TdPlugin.initialize` default to no-op stubs
/// (see `td_plugin.dart`) until [tdlib_native.TdNativePlugin.registerWith]
/// overwrites them with the real FFI implementation. The `tdlib` package
/// declares `dartPluginClass: TdNativePlugin` in its pubspec, which makes
/// Flutter's engine bootstrap call that automatically — but only for the
/// main, Flutter-attached isolate. A background isolate spawned via
/// `Isolate.spawn()` never goes through that bootstrap, so it's left with
/// the stub, and every native call silently no-ops or throws
/// `UnimplementedError` from `td_native_plugin_stub.dart`. Calling
/// `registerWith()` ourselves before initializing makes both isolates
/// behave identically regardless of Flutter's implicit registration.
void _ensureRealPluginRegistered() {
  tdlib_native.TdNativePlugin.registerWith();
}

/// The native TDLib library never gets `dlopen`'d automatically on Android
/// when [TdPlugin.initialize] is called with no argument — it falls back to
/// `DynamicLibrary.process()`, which can only see symbols from libraries
/// already loaded into the process. Since nothing loads `libtdjson.so`,
/// that lookup fails with "undefined symbol: td_json_client_create" even
/// though the library is bundled correctly. Passing the library name
/// explicitly makes it do a real `DynamicLibrary.open()` instead, which
/// Android resolves against the app's native library directory.
String? _tdJsonLibraryPath() {
  if (Platform.isAndroid) return 'libtdjson.so';
  if (Platform.isLinux) return 'libtdjson.so';
  if (Platform.isMacOS) return 'libtdjson.dylib';
  if (Platform.isWindows) return 'tdjson.dll';
  return null;
}

/// Low-level wrapper around TDLib's JSON interface.
///
/// Manages TDLib client lifecycle, request/response handling,
/// and exposes updates as a Dart [Stream]. Runs TDLib operations
/// in a background isolate to avoid blocking the UI.
class TdLibClient {
  TdLibClient._();

  static TdLibClient? _instance;

  /// Singleton instance.
  static TdLibClient get instance => _instance ??= TdLibClient._();

  /// Whether [TdPlugin.initialize] has been called in this isolate.
  ///
  /// Loading the native TDLib library is only safe/necessary once per
  /// isolate; the receive-loop isolate calls this again on its own.
  static bool _pluginInitialized = false;

  int? _clientId;
  bool _initialized = false;
  Directory? _databaseDir;
  Directory? _filesDir;

  /// Database encryption key supplied at [initialize]. Sourced from
  /// flutter_secure_storage via the DI layer — never hardcoded here.
  String? _databaseKey;

  Isolate? _receiveIsolate;
  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _receivePortSubscription;

  final _updateController = StreamController<Map<String, dynamic>>.broadcast();
  final _requestCompleters = <int, Completer<Map<String, dynamic>>>{};
  int _requestId = 0;

  /// Stream of TDLib updates (auth state changes, messages, etc.).
  Stream<Map<String, dynamic>> get updates => _updateController.stream;

  /// Whether the client has been initialized.
  bool get isInitialized => _initialized;

  /// The TDLib client ID.
  int get clientId {
    final id = _clientId;
    if (id == null) {
      throw const TdLibException(
        message: 'TDLib client not initialized',
        code: 'CLIENT_NOT_INITIALIZED',
      );
    }
    return id;
  }

  /// Initialize the TDLib client with the given database encryption key.
  ///
  /// [databaseKey] is used to encrypt the TDLib session database.
  /// Must be called before any other methods.
  Future<void> initialize({required String databaseKey}) async {
    if (_initialized) return;

    if (databaseKey.isEmpty) {
      throw const TdLibException(
        message: 'Database encryption key must not be empty',
        code: 'INVALID_DATABASE_KEY',
      );
    }
    _databaseKey = databaseKey;

    debugPrint('[TdLibClient] initialize: getting app documents directory');
    final appDir = await getApplicationDocumentsDirectory();

    _databaseDir = Directory('${appDir.path}/tdlib_db');
    _filesDir = Directory('${appDir.path}/tdlib_files');

    if (!await _databaseDir!.exists()) {
      await _databaseDir!.create(recursive: true);
    }
    if (!await _filesDir!.exists()) {
      await _filesDir!.create(recursive: true);
    }
    debugPrint('[TdLibClient] initialize: directories ready, loading plugin');

    await _ensurePluginInitialized();
    debugPrint('[TdLibClient] initialize: plugin loaded, creating client');
    _clientId = await _createClient();
    debugPrint('[TdLibClient] initialize: client created (id=$_clientId)');
    _initialized = true;

    // TDLib will start the auth flow by emitting
    // authorizationStateWaitTdlibParameters — respond to it automatically
    // so callers only need to deal with phone/code/password states.
    _updateController.stream.listen(_maybeBootstrapAuth);

    debugPrint('[TdLibClient] initialize: starting receive loop');
    await _startReceiveLoop();
    debugPrint('[TdLibClient] initialize: receive loop started');

    debugPrint('[TdLibClient] Initialized with client ID: $_clientId');
  }

  /// Load the native TDLib library. Safe to call more than once.
  static Future<void> _ensurePluginInitialized() async {
    if (_pluginInitialized) return;
    _ensureRealPluginRegistered();
    await TdPlugin.initialize(_tdJsonLibraryPath());
    _pluginInitialized = true;
  }

  /// Send a TDLib request and wait for the response.
  ///
  /// [method] is the TDLib method name (e.g., 'setAuthenticationPhoneNumber').
  /// [params] is the method parameters as a JSON-encodable map.
  /// Returns the response as a decoded JSON map.
  Future<Map<String, dynamic>> sendRequest({
    required String method,
    Map<String, dynamic>? params,
  }) async {
    if (!_initialized) {
      throw const TdLibException(
        message: 'TDLib client not initialized',
        code: 'CLIENT_NOT_INITIALIZED',
      );
    }

    final id = ++_requestId;
    final request = <String, dynamic>{
      '@type': method,
      if (params != null) ...params,
      '@extra': id,
    };

    final completer = Completer<Map<String, dynamic>>();
    _requestCompleters[id] = completer;

    final jsonRequest = jsonEncode(request);
    await _sendJson(jsonRequest);

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _requestCompleters.remove(id);
        throw TdLibException(
          message: 'TDLib request timed out: $method',
          code: 'REQUEST_TIMEOUT',
        );
      },
    );
  }

  /// Process incoming TDLib updates.
  ///
  /// Kept as a no-op for interface compatibility — responses now arrive
  /// automatically via the background receive-loop isolate started in
  /// [initialize], so callers no longer need to pump this manually.
  void processUpdates() {}

  /// Check if the client is currently authenticated.
  Future<bool> isAuthenticated() async {
    try {
      final result = await sendRequest(method: 'getAuthorizationState');
      final stateType = result['@type'] as String?;
      return stateType == 'authorizationStateReady';
    } catch (e) {
      return false;
    }
  }

  /// Get the current authorization state.
  Future<Map<String, dynamic>> getAuthorizationState() async {
    return sendRequest(method: 'getAuthorizationState');
  }

  /// Log out the current session.
  Future<void> logOut() async {
    await sendRequest(method: 'logOut');
  }

  /// Close the TDLib client and clean up resources.
  Future<void> close() async {
    if (_clientId != null) {
      try {
        await sendRequest(method: 'close');
      } catch (_) {
        // Ignore errors during close
      }
      try {
        TdPlugin.instance.tdJsonClientDestroy(_clientId!);
      } catch (_) {
        // Ignore errors freeing native resources on shutdown.
      }
    }

    await _receivePortSubscription?.cancel();
    _receivePort?.close();
    _receiveIsolate?.kill(priority: Isolate.immediate);
    _receiveIsolate = null;
    _receivePort = null;
    _receivePortSubscription = null;

    await _updateController.close();
    _requestCompleters.clear();
    _initialized = false;
    _clientId = null;
    _databaseKey = null;
    _instance = null;
  }

  /// Create a new TDLib client via the native tdlib plugin.
  Future<int> _createClient() async {
    return TdPlugin.instance.tdJsonClientCreate();
  }

  /// Send a JSON string to TDLib.
  Future<void> _sendJson(String json) async {
    TdPlugin.instance.tdJsonClientSend(_clientId!, json);
  }

  /// Start the background isolate that polls TDLib for responses/updates.
  ///
  /// [TdPlugin.tdJsonClientReceive] is a blocking native call, so it's run
  /// on a dedicated isolate to avoid freezing the UI thread. Results are
  /// forwarded back to this isolate over a [ReceivePort].
  Future<void> _startReceiveLoop() async {
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    _receivePortSubscription = receivePort.listen((message) {
      if (message is String) {
        _handleIncomingJson(message);
      }
    });

    _receiveIsolate = await Isolate.spawn(_tdReceiveIsolateEntry, (
      clientId: _clientId!,
      sendPort: receivePort.sendPort,
    ));
  }

  /// Parse and dispatch one incoming JSON message from TDLib.
  void _handleIncomingJson(String response) {
    try {
      final data = jsonDecode(response) as Map<String, dynamic>;
      final extra = data['@extra'] as int?;

      if (extra != null && _requestCompleters.containsKey(extra)) {
        final completer = _requestCompleters.remove(extra)!;
        if (data['@type'] == 'error') {
          completer.completeError(TdLibErrorMapper.fromResponse(data));
        } else {
          completer.complete(data);
        }
      } else {
        _updateController.add(data);
      }
    } catch (e) {
      debugPrint('[TdLibClient] Error parsing response: $e');
    }
  }

  /// Auto-respond to TDLib's request for local parameters.
  ///
  /// TDLib starts every session by asking for connection/storage
  /// parameters via `authorizationStateWaitTdlibParameters`. This is
  /// infrastructure, not part of the phone/code/password auth flow, so
  /// [TdLibClient] handles it internally rather than surfacing it to
  /// [TelegramAuthRepository].
  void _maybeBootstrapAuth(Map<String, dynamic> update) {
    if (update['@type'] != 'updateAuthorizationState') return;
    final state = update['authorization_state'] as Map<String, dynamic>?;
    if (state?['@type'] != 'authorizationStateWaitTdlibParameters') return;
    unawaited(_sendTdlibParameters());
  }

  Future<void> _sendTdlibParameters() async {
    if (!TdLibConfig.hasCredentials) {
      debugPrint(
        '[TdLibClient] Missing Telegram API credentials — TDLib will '
        'reject setTdlibParameters. Pass '
        '--dart-define=LUMOVAULT_TELEGRAM_API_ID=<id> and '
        '--dart-define=LUMOVAULT_TELEGRAM_API_HASH=<hash> when building/'
        'running (see .env.example).',
      );
    }

    try {
      await sendRequest(
        method: 'setTdlibParameters',
        params: {
          'database_directory': _databaseDir!.path,
          'files_directory': _filesDir!.path,
          // Field name per TDLib's JSON API — NOT 'database_key'.
          'database_encryption_key': _databaseKey!,
          'use_file_database': true,
          'use_chat_info_database': true,
          'use_message_database': true,
          'use_secret_chats': false,
          'api_id': TdLibConfig.apiId,
          'api_hash': TdLibConfig.apiHash,
          'system_language_code': Platform.localeName.split('_').first,
          'device_model': 'LumoVault',
          'system_version': Platform.operatingSystemVersion,
          'application_version': '1.0.0',
          'enable_storage_optimizer': true,
        },
      );
    } on TdLibException catch (e) {
      debugPrint('[TdLibClient] setTdlibParameters failed: ${e.message}');
    }
  }
}

/// Entry point for the background TDLib receive-loop isolate.
///
/// Runs in its own isolate since [TdPlugin.tdJsonClientReceive] blocks
/// synchronously for up to the given timeout. Loads the native library
/// again here — FFI bindings are resolved per-isolate, not shared from
/// the spawning isolate.
Future<void> _tdReceiveIsolateEntry(
  ({int clientId, SendPort sendPort}) args,
) async {
  _ensureRealPluginRegistered();
  await TdPlugin.initialize(_tdJsonLibraryPath());

  while (true) {
    final response = TdPlugin.instance.tdJsonClientReceive(args.clientId, 1.0);
    if (response != null) {
      args.sendPort.send(response);
    }
    // Yield to the isolate's event loop between iterations so it can
    // process its own shutdown signal (isolate.kill()) promptly.
    await Future<void>.delayed(Duration.zero);
  }
}
