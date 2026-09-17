import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/tdlib/tdlib_client.dart';
import 'package:lumovault/core/tdlib/tdlib_connection_manager.dart';
import 'package:lumovault/core/tdlib/tdlib_exception.dart';

void main() {
  group('ConnectionStatus', () {
    test('has all expected values', () {
      expect(ConnectionStatus.values.length, equals(5));
      expect(
        ConnectionStatus.values.toSet(),
        equals({
          ConnectionStatus.disconnected,
          ConnectionStatus.connecting,
          ConnectionStatus.connected,
          ConnectionStatus.reconnecting,
          ConnectionStatus.failed,
        }),
      );
    });
  });

  group('TdLibConnectionManager', () {
    test('initial status is disconnected', () {
      final client = TdLibClient.instance;
      final manager = TdLibConnectionManager(client: client);

      expect(manager.status, equals(ConnectionStatus.disconnected));
      expect(manager.isConnected, isFalse);

      manager.dispose();
    });

    test('dispose cleans up resources', () {
      final client = TdLibClient.instance;
      final manager = TdLibConnectionManager(client: client);

      // Should not throw.
      manager.dispose();

      // Double dispose should not throw.
      manager.dispose();
    });

    test('sendRequest throws when not connected', () async {
      final client = TdLibClient.instance;
      final manager = TdLibConnectionManager(client: client);

      expect(
        () => manager.sendRequest(method: 'test'),
        throwsA(isA<TdLibException>()),
      );

      manager.dispose();
    });

    test('disconnect sets status to disconnected', () async {
      final client = TdLibClient.instance;
      final manager = TdLibConnectionManager(client: client);

      await manager.disconnect();

      expect(manager.status, equals(ConnectionStatus.disconnected));
      expect(manager.isConnected, isFalse);

      manager.dispose();
    });

    test('connect marks failed and rethrows on TdLibException', () async {
      final manager = TdLibConnectionManager(
        client: _ThrowingTdLibClient(
          const TdLibException(message: 'init failed', code: 'INIT_FAILED'),
        ),
      );

      await expectLater(
        manager.connect(databaseKey: 'key'),
        throwsA(isA<TdLibException>()),
      );
      expect(manager.status, ConnectionStatus.failed);
      expect(manager.isConnected, isFalse);

      manager.dispose();
    });

    test(
      'connect marks failed and wraps non-TdLib initialize errors',
      () async {
        // e.g. an Isolate.spawn failure is a StateError, not a TdLibException.
        // Before the fix the status stayed stuck on "connecting" forever.
        final manager = TdLibConnectionManager(
          client: _ThrowingTdLibClient(StateError('isolate spawn failed')),
        );

        await expectLater(
          manager.connect(databaseKey: 'key'),
          throwsA(
            isA<TdLibException>().having(
              (e) => e.code,
              'code',
              'CONNECT_FAILED',
            ),
          ),
        );
        expect(manager.status, ConnectionStatus.failed);
        expect(manager.isConnected, isFalse);

        manager.dispose();
      },
    );

    test(
      'a transient failure schedules a reconnect that retries initialize',
      () async {
        final client = _ControllableClient()
          ..sendRequestError = const TdLibException(
            message: 'network gone',
            code: 'NETWORK_ERROR',
          );
        final manager = TdLibConnectionManager(client: client);
        addTearDown(manager.dispose);

        await manager.connect(databaseKey: 'key');
        expect(client.initializeCalls, 1);
        expect(manager.isConnected, isTrue);

        // A transient request failure arms the reconnect instead of leaving the
        // manager quietly disconnected.
        await expectLater(
          manager.sendRequest(method: 'getCurrentUser'),
          throwsA(isA<TdLibException>()),
        );
        expect(manager.status, ConnectionStatus.reconnecting);
        expect(client.initializeCalls, 1);

        // The timer fires (~1s backoff) and reconnect re-runs initialize against
        // the cached key.
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        expect(client.initializeCalls, 2);
      },
    );

    test('connectionStateReady cancels an armed reconnect', () async {
      final client = _ControllableClient()
        ..sendRequestError = const TdLibException(
          message: 'network gone',
          code: 'NETWORK_ERROR',
        );
      final manager = TdLibConnectionManager(client: client);
      addTearDown(manager.dispose);

      await manager.connect(databaseKey: 'key');
      await expectLater(
        manager.sendRequest(method: 'getCurrentUser'),
        throwsA(isA<TdLibException>()),
      );
      expect(manager.status, ConnectionStatus.reconnecting);

      // The connection recovers before the backoff elapses.
      client.sendRequestError = null;
      client.emit(const {
        '@type': 'updateConnectionState',
        'state': {'@type': 'connectionStateReady'},
      });
      await pumpEventQueue();
      expect(manager.status, ConnectionStatus.connected);

      // Wait past the whole backoff window: a timer left armed would have
      // fired reconnect() and bumped the initialize count.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(client.initializeCalls, 1);
    });
  });

  group('TdLibException', () {
    test('displayMessage returns userFacingMessage when set', () {
      const exception = TdLibException(
        message: 'Technical message',
        code: 'ERROR_CODE',
        userFacingMessage: 'User friendly message',
      );

      expect(exception.displayMessage, equals('User friendly message'));
    });

    test('displayMessage falls back to message', () {
      const exception = TdLibException(
        message: 'Technical message',
        code: 'ERROR_CODE',
      );

      expect(exception.displayMessage, equals('Technical message'));
    });

    test('toString includes code and message', () {
      const exception = TdLibException(
        message: 'Something went wrong',
        code: 'MY_ERROR',
      );

      expect(exception.toString(), contains('MY_ERROR'));
      expect(exception.toString(), contains('Something went wrong'));
    });
  });

  group('TdLibErrorMapper', () {
    test('maps known error codes to user messages', () {
      expect(
        TdLibErrorMapper.mapErrorToUserMessage('PHONE_INVALID'),
        contains('phone number'),
      );

      expect(
        TdLibErrorMapper.mapErrorToUserMessage('CODE_INVALID'),
        contains('code'),
      );

      expect(
        TdLibErrorMapper.mapErrorToUserMessage('NETWORK_ERROR'),
        contains('Network error'),
      );

      expect(
        TdLibErrorMapper.mapErrorToUserMessage('FLOOD_WAIT'),
        contains('Too many'),
      );

      expect(
        TdLibErrorMapper.mapErrorToUserMessage('STORAGE_FULL'),
        contains('storage is full'),
      );
    });

    test('returns default message for unknown codes', () {
      final message = TdLibErrorMapper.mapErrorToUserMessage('UNKNOWN_XYZ');

      expect(message, isNotEmpty);
      expect(message, isNot(contains('UNKNOWN_XYZ')));
    });

    test('fromResponse creates TdLibException from error map', () {
      final error = TdLibErrorMapper.fromResponse({
        'code': 400,
        'message': 'PHONE_NUMBER_INVALID',
      });

      expect(error.code, equals('PHONE_NUMBER_INVALID'));
      expect(error.message, equals('PHONE_NUMBER_INVALID'));
      expect(error.displayMessage, isNotEmpty);
    });

    test('fromResponse falls back to numeric status when message is empty', () {
      final error = TdLibErrorMapper.fromResponse({'code': 400, 'message': ''});

      expect(error.code, equals('400'));
    });
  });
}

/// TDLib client whose [initialize] always throws the configured error, for
/// exercising connection-manager failure handling without an FFI instance.
class _ThrowingTdLibClient implements TdLibClient {
  _ThrowingTdLibClient(this.error);

  final Object error;

  @override
  Stream<Map<String, dynamic>> get updates => const Stream.empty();

  @override
  bool get isInitialized => false;

  @override
  int get clientId => 0;

  @override
  Future<void> initialize({required String databaseKey}) async {
    throw error;
  }

  @override
  Future<Map<String, dynamic>> sendRequest({
    required String method,
    Map<String, dynamic>? params,
  }) async {
    return {'@type': 'ok'};
  }

  @override
  void processUpdates() {}

  @override
  Future<bool> isAuthenticated() async => false;

  @override
  Future<Map<String, dynamic>> getAuthorizationState() async {
    return {'@type': 'authorizationStateWaitTdlibParameters'};
  }

  @override
  Future<void> logOut() async {}

  @override
  Future<void> close() async {}
}

/// TDLib client whose update stream and [sendRequest] failures are directly
/// controllable, so the connection manager's reconnect machinery — which only
/// becomes reachable once a connection exists — can be exercised without an
/// FFI instance.
class _ControllableClient implements TdLibClient {
  _ControllableClient();

  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  /// Number of times [initialize] has run.
  int initializeCalls = 0;

  /// Thrown by the next [sendRequest] (one-shot, so a later retry succeeds).
  TdLibException? sendRequestError;

  /// Push an update onto [updates].
  void emit(Map<String, dynamic> update) => _controller.add(update);

  @override
  Stream<Map<String, dynamic>> get updates => _controller.stream;

  @override
  bool get isInitialized => true;

  @override
  int get clientId => 0;

  @override
  Future<void> initialize({required String databaseKey}) async {
    initializeCalls++;
  }

  @override
  Future<Map<String, dynamic>> sendRequest({
    required String method,
    Map<String, dynamic>? params,
  }) async {
    final error = sendRequestError;
    if (error != null) {
      sendRequestError = null;
      throw error;
    }
    return {'@type': 'ok'};
  }

  @override
  void processUpdates() {}

  @override
  Future<bool> isAuthenticated() async => false;

  @override
  Future<Map<String, dynamic>> getAuthorizationState() async => {
    '@type': 'authorizationStateWaitTdlibParameters',
  };

  @override
  Future<void> logOut() async {}

  @override
  Future<void> close() async {}
}
