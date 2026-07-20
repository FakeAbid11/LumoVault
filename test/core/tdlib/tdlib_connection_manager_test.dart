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

    test('dispose cleans up resources', () {
      final client = TdLibClient.instance;
      final manager = TdLibConnectionManager(client: client);

      // Should not throw.
      manager.dispose();

      // Double dispose should not throw.
      manager.dispose();
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
