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
    if (_status == ConnectionStatus.connected) return;

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
    }
  }

  /// Disconnect from TDLib gracefully.
  Future<void> disconnect() async {
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

    _retryCount = 0;
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
    if (_status == ConnectionStatus.connected) {
      await disconnect();
    }
    _retryCount = 0;

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
