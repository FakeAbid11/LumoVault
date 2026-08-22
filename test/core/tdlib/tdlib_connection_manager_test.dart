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
