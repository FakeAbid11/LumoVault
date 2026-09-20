import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tdlib_client.dart';
import 'tdlib_exception.dart';

/// Connection states for the TDLib client.
enum ConnectionStatus {
  /// Not connected.
  disconnected,

  /// Connecting or reconnecting.
  connecting,

  /// Connected and ready.
  connected,

  /// Connection lost, waiting to reconnect.
  reconnecting,

  /// Permanently failed after max retries.
  failed,
}

/// Manages TDLib connection lifecycle with auto-reconnect and state tracking.
///
/// Wraps [TdLibClient] to provide:
/// - Exponential backoff reconnection on transient failures
/// - Connection state tracking with stream notifications
/// - Heartbeat monitoring to detect stale connections
/// - Graceful degradation during network interruptions
class TdLibConnectionManager {
  // Named params are backed by private fields; Dart forbids private named
  // parameters, so initializing formals (this._client) can't be used here.
  // ignore_for_file: prefer_initializing_formals
  TdLibConnectionManager({
    required TdLibClient client,
    Future<String> Function()? databaseKeyProvider,
  }) : _client = client,
       _databaseKeyProvider = databaseKeyProvider;

  final TdLibClient _client;

  /// Supplies the persisted database encryption key.
  ///
  /// Used on reconnect so the same key is reused rather than regenerating a
  /// fresh one (which would leave the encrypted TDLib database unreadable).
  final Future<String> Function()? _databaseKeyProvider;

  /// The database key used for the last successful connect, reused on reconnect.
  String? _databaseKey;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  int _retryCount = 0;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  StreamSubscription? _updatesSubscription;

  static const int _maxRetries = 10;
  static const Duration _initialBackoff = Duration(seconds: 1);
  static const Duration _maxBackoff = Duration(minutes: 2);
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  final _statusController = StreamController<ConnectionStatus>.broadcast();

  /// Stream of connection status changes.
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  /// Current connection status.
  ConnectionStatus get status => _status;

  /// Whether the client is currently connected.
  bool get isConnected => _status == ConnectionStatus.connected;

  /// The underlying TDLib client.
  TdLibClient get client => _client;

  /// Initialize the connection manager and establish initial connection.
  ///
  /// [databaseKey] is passed to the underlying [TdLibClient.initialize].
  /// Throws [TdLibException] if initialization fails permanently.
  Future<void> connect({required String databaseKey}) async {
    if (_status == ConnectionStatus.connected ||
        _status == ConnectionStatus.connecting) {
      return;
    }

    // Cancel any pending reconnect so it doesn't race with this connect.
    _stopReconnect();

    // Remember the key so reconnects reuse the exact same value.
    _databaseKey = databaseKey;
    _updateStatus(ConnectionStatus.connecting);

    try {
      await _client.initialize(databaseKey: databaseKey);
      _retryCount = 0;
      _updateStatus(ConnectionStatus.connected);
      _startHeartbeat();
      _listenForUpdates();
    } on TdLibException {
      _updateStatus(ConnectionStatus.failed);
      rethrow;
    } catch (e) {
      // initialize() can fail with non-TdLib errors too (isolate spawn
      // failures, IO errors). Without this branch the status stayed stuck on
      // "connecting" forever while the caller got an untyped error.
      debugPrint('[TdLibConnectionManager] connect failed: $e');
      _updateStatus(ConnectionStatus.failed);
      throw TdLibException(
        message: 'Failed to connect to TDLib: $e',
        code: 'CONNECT_FAILED',
        userFacingMessage: 'Could not connect to Telegram. Please try again.',
      );
    }
  }

  /// Disconnect from TDLib gracefully.
  /// Close the client and stop all timers.
  ///
  /// [resetRetryCount] is false when called from [reconnect]: the backoff
  /// ladder is what stops a permanently-dead Telegram from being retried once
  /// a second forever, and clearing it mid-retry would flatten every attempt
  /// back to the 1s initial delay.
  Future<void> disconnect({bool resetRetryCount = true}) async {
    _stopHeartbeat();
    _stopReconnect();
    _cancelUpdateListener();

    if (_client.isInitialized) {
      try {
        await _client.close();
      } catch (_) {
        // Ignore errors during graceful close.
      }
    }

    if (resetRetryCount) _retryCount = 0;
    _updateStatus(ConnectionStatus.disconnected);
  }

  /// Send a request through the connection manager.
  ///
  /// Automatically handles transient failures by retrying with backoff.
  /// Throws [TdLibException] if the request fails permanently.
  Future<Map<String, dynamic>> sendRequest({
    required String method,
    Map<String, dynamic>? params,
  }) async {
    if (!isConnected) {
      throw const TdLibException(
        message: 'Not connected to TDLib',
        code: 'NOT_CONNECTED',
      );
    }

    try {
      return await _client.sendRequest(method: method, params: params);
    } on TdLibException catch (e) {
      if (_isTransientError(e)) {
        _scheduleReconnect();
        rethrow;
      }
      rethrow;
    }
  }

  /// Force an immediate reconnection attempt.
  ///
  /// Reuses the persisted database key so the encrypted TDLib database stays
  /// readable. Falls back to the key supplied at first [connect] if the
  /// provider is unavailable.
  Future<void> reconnect() async {
    // Always close the client before reconnecting. This was conditioned on the
    // status reading `connected`, but a reconnect is scheduled exactly when the
    // session has wedged — so the client stayed open, initialize() short-
    // circuited on its own `_initialized` guard, and the manager announced
    // `connected` over a dead session: every request then timed out at 30s,
    // forever, with a healthy-looking UI and backup silently stalled.
    //
    // retryCount survives the disconnect for the same reason as before:
    // _scheduleReconnect computes backoff from it before the timer fires, so a
    // reset here would pin every attempt to the 1s initial delay. It only
    // resets on a real connection (connectionStateReady in _listenForUpdates).
    await disconnect(resetRetryCount: false);

    final key = await _resolveDatabaseKey();
    if (key == null) {
      _updateStatus(ConnectionStatus.failed);
      throw const TdLibException(
        message: 'No database key available for reconnect',
        code: 'NO_DATABASE_KEY',
      );
    }
    await connect(databaseKey: key);
  }

  /// Resolve the database key for a reconnect: prefer the persisted key from
  /// the provider, then the key cached from the last successful connect.
  Future<String?> _resolveDatabaseKey() async {
    if (_databaseKeyProvider != null) {
      try {
        return await _databaseKeyProvider();
      } catch (e) {
        debugPrint('[TdLibConnectionManager] Key provider failed: $e');
      }
    }
    return _databaseKey;
  }

  /// Dispose of all resources.
  void dispose() {
    _stopHeartbeat();
    _stopReconnect();
    _cancelUpdateListener();
    _statusController.close();
  }

  // --- Internal methods ---

  void _updateStatus(ConnectionStatus newStatus) {
    if (_status == newStatus) return;
    _status = newStatus;
    if (!_statusController.isClosed) {
      _statusController.add(newStatus);
    }
    debugPrint('[TdLibConnectionManager] Status: $newStatus');
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      if (!isConnected) return;
      try {
        await _client.sendRequest(method: 'getAuthorizationState');
      } catch (e) {
        debugPrint('[TdLibConnectionManager] Heartbeat failed: $e');
        _scheduleReconnect();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _listenForUpdates() {
    _cancelUpdateListener();
    _updatesSubscription = _client.updates.listen(
      (update) {
        // Reset retry count on successful update reception.
        final type = update['@type'] as String?;
        if (type == 'updateConnectionState') {
          final state = update['state'] as Map<String, dynamic>?;
          final stateType = state?['@type'] as String?;
          if (stateType == 'connectionStateReady') {
            _retryCount = 0;
            _updateStatus(ConnectionStatus.connected);
          } else if (stateType == 'connectionStateConnecting') {
            _updateStatus(ConnectionStatus.connecting);
          } else if (stateType == 'connectionStateUpdating') {
            // TDLib is updating — keep connected.
          } else if (stateType == 'connectionStateError') {
            // The one state that has to trigger a reconnect: TDLib has given up
            // on the session. It used to be ignored entirely, which left the
            // manager reporting `connected` over a dead connection with no path
            // that ever closed the client.
            final message = state?['message'] as String?;
            debugPrint(
              '[TdLibConnectionManager] TDLib reported a connection error: '
              '${message ?? 'no detail'}',
            );
            _updateStatus(ConnectionStatus.disconnected);
            _scheduleReconnect();
          }
        }
      },
      onError: (error) {
        debugPrint('[TdLibConnectionManager] Update stream error: $error');
        _scheduleReconnect();
      },
    );
  }

  void _cancelUpdateListener() {
    _updatesSubscription?.cancel();
    _updatesSubscription = null;
  }

  void _scheduleReconnect() {
    if (_status == ConnectionStatus.reconnecting) return;
    if (_retryCount >= _maxRetries) {
      _updateStatus(ConnectionStatus.failed);
      debugPrint('[TdLibConnectionManager] Max retries reached, giving up.');
      return;
    }

    _updateStatus(ConnectionStatus.reconnecting);
    final backoff = _calculateBackoff();
    _retryCount++;

    debugPrint(
      '[TdLibConnectionManager] Reconnecting in ${backoff.inSeconds}s '
      '(attempt $_retryCount/$_maxRetries)',
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(backoff, () async {
      try {
        await reconnect();
      } catch (e) {
        debugPrint('[TdLibConnectionManager] Reconnect failed: $e');
        _scheduleReconnect();
      }
    });
  }

  void _stopReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Duration _calculateBackoff() {
    // Exponential backoff: 1s, 2s, 4s, 8s, ..., capped at 2 minutes.
    final seconds = _initialBackoff.inSeconds * (1 << _retryCount);
    final capped = seconds > _maxBackoff.inSeconds
        ? _maxBackoff.inSeconds
        : seconds;
    return Duration(seconds: capped);
  }

  bool _isTransientError(TdLibException error) {
    const transientCodes = {
      'NETWORK_ERROR',
      'TIMEOUT',
      'REQUEST_TIMEOUT',
      'NOT_CONNECTED',
    };
    return transientCodes.contains(error.code);
  }
}
