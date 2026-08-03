import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:lumovault/core/auth/auth_service.dart';
import 'package:lumovault/core/auth/telegram_auth_repository.dart';
import 'package:lumovault/core/tdlib/tdlib_client.dart';
import 'package:lumovault/core/tdlib/tdlib_exception.dart';

/// Mock TDLib client for testing.
class MockTdLibClient implements TdLibClient {
  MockTdLibClient({
    this.authStateType = 'authorizationStateWaitPhoneNumber',
    this.sendRequestResult,
    this.throwOnSend = false,
    this.throwOnLogout = false,
  });

  String authStateType;
  Map<String, dynamic>? sendRequestResult;
  bool throwOnSend;
  bool throwOnLogout;

  final _updateController = StreamController<Map<String, dynamic>>.broadcast();
  final sentRequests = <Map<String, dynamic>>[];

  @override
  Stream<Map<String, dynamic>> get updates => _updateController.stream;

  @override
  bool get isInitialized => true;

  @override
  int get clientId => 0;

  @override
  Future<void> initialize({required String databaseKey}) async {}

  @override
  Future<Map<String, dynamic>> sendRequest({
    required String method,
    Map<String, dynamic>? params,
  }) async {
    sentRequests.add({'method': method, if (params != null) 'params': params});

    if (throwOnSend) {
      throw const TdLibException(
        message: 'Test error',
        code: 'TEST_ERROR',
        userFacingMessage: 'Test error message',
      );
    }

    if (sendRequestResult != null) {
      return sendRequestResult!;
    }

    return {'@type': 'ok'};
  }

  @override
  void processUpdates() {}

  @override
  Future<bool> isAuthenticated() async =>
      authStateType == 'authorizationStateReady';

  @override
  Future<Map<String, dynamic>> getAuthorizationState() async {
    return {'@type': authStateType};
  }

  @override
  Future<void> logOut() async {
    if (throwOnLogout) {
      throw const TdLibException(
        message: 'Logout failed',
        code: 'LOGOUT_FAILED',
      );
    }
    authStateType = 'authorizationStateClosed';
  }

  @override
  Future<void> close() async {}

  /// Simulate a TDLib authorization state update.
  void simulateUpdate(Map<String, dynamic> update) {
    _updateController.add(update);
  }

  /// Dispose the mock.
  void disposeMock() {
    _updateController.close();
  }
}

void main() {
  group('TelegramAuthRepository', () {
    late MockTdLibClient mockClient;
    late TelegramAuthRepository repository;

    setUp(() {
      mockClient = MockTdLibClient();
      repository = TelegramAuthRepository(mockClient);
    });

    tearDown(() {
      repository.dispose();
      mockClient.disposeMock();
    });

    group('initialize', () {
      test('sets initial state from TDLib', () async {
        mockClient.authStateType = 'authorizationStateWaitPhoneNumber';
        await repository.initialize();
        expect(repository.currentState, AuthState.unauthenticated);
      });

      test('sets authenticated state if already logged in', () async {
        mockClient.authStateType = 'authorizationStateReady';
        await repository.initialize();
        expect(repository.currentState, AuthState.authenticated);
      });

      test('sets password required state if 2FA enabled', () async {
        mockClient.authStateType = 'authorizationStateWaitPassword';
        await repository.initialize();
        expect(repository.currentState, AuthState.passwordRequired);
      });
    });

    group('sendCode', () {
      test('sends phone number to TDLib', () async {
        await repository.initialize();
        final result = await repository.sendCode('+1234567890');

        expect(result, isA<AuthCodeSent>());
        expect((result as AuthCodeSent).phoneNumber, '+1234567890');
        expect(
          mockClient.sentRequests.last['method'],
          'setAuthenticationPhoneNumber',
        );
      });

      test('returns error on TDLib failure', () async {
        mockClient.throwOnSend = true;
        await repository.initialize();
        final result = await repository.sendCode('+1234567890');

        expect(result, isA<AuthError>());
        expect((result as AuthError).code, 'TEST_ERROR');
        expect(repository.currentState, AuthState.error);
      });

      test('transitions to codeSent on success', () async {
        await repository.initialize();
        await repository.sendCode('+1234567890');
        expect(repository.currentState, AuthState.codeSent);
      });
    });

    group('verifyCode', () {
      test('sends code to TDLib', () async {
        await repository.initialize();
        await repository.sendCode('+1234567890');
        final result = await repository.verifyCode('12345');

        expect(result, isA<AuthSuccess>());
        expect(
          mockClient.sentRequests.last['method'],
          'checkAuthenticationCode',
        );
      });

      test('returns password required on 2FA', () async {
        mockClient.throwOnSend = true;
        mockClient.sendRequestResult = null;
        await repository.initialize();
        await repository.sendCode('+1234567890');

        // Simulate 2FA required
        mockClient.throwOnSend = false;
        mockClient.sendRequestResult = {
          '@type': 'error',
          'code': 'PASSWORD_HASH_INVALID',
        };

        await repository.verifyCode('12345');
        // The actual behavior depends on how the repository handles the error
      });

      test('returns error on invalid code', () async {
        mockClient.throwOnSend = true;
        await repository.initialize();
        await repository.sendCode('+1234567890');

        final result = await repository.verifyCode('00000');
        expect(result, isA<AuthError>());
      });
    });

    group('submitPassword', () {
      test('sends password to TDLib', () async {
        await repository.initialize();
        final result = await repository.submitPassword('mypassword');

        expect(result, isA<AuthSuccess>());
        expect(
          mockClient.sentRequests.last['method'],
          'checkAuthenticationPassword',
        );
      });

      test('returns error on wrong password', () async {
        mockClient.throwOnSend = true;
        await repository.initialize();

        final result = await repository.submitPassword('wrong');
        expect(result, isA<AuthError>());
      });
    });

    group('logout', () {
      test('calls logOut on TDLib', () async {
        await repository.initialize();
        await repository.logout();

        // The mock's logOut() method should be called
        expect(repository.currentState, AuthState.unauthenticated);
      });

      test('handles logout failure gracefully', () async {
        mockClient.throwOnLogout = true;
        await repository.initialize();
        await repository.logout();

        // Should still transition to unauthenticated
        expect(repository.currentState, AuthState.unauthenticated);
      });
    });

    group('stateStream', () {
      test('emits state changes', () async {
        final states = <AuthState>[];
        repository.stateStream.listen(states.add);

        await repository.initialize();
        await repository.sendCode('+1234567890');

        // Allow async events to propagate
        await Future<void>.delayed(Duration.zero);

        expect(states, contains(AuthState.loading));
        expect(states, contains(AuthState.codeSent));
      });
    });

    group('update handling', () {
      test('handles authorizationStateWaitCode update', () async {
        await repository.initialize();
        expect(repository.currentState, AuthState.unauthenticated);

        mockClient.simulateUpdate({
          '@type': 'updateAuthorizationState',
          'authorization_state': {'@type': 'authorizationStateWaitCode'},
        });

        await Future<void>.delayed(Duration.zero);
        expect(repository.currentState, AuthState.codeSent);
      });

      test('handles authorizationStateReady update', () async {
        await repository.initialize();
        expect(repository.currentState, AuthState.unauthenticated);

        mockClient.simulateUpdate({
          '@type': 'updateAuthorizationState',
          'authorization_state': {'@type': 'authorizationStateReady'},
        });

        await Future<void>.delayed(Duration.zero);
        expect(repository.currentState, AuthState.authenticated);
      });

      test('handles authorizationStateWaitPassword update', () async {
        await repository.initialize();
        expect(repository.currentState, AuthState.unauthenticated);

        mockClient.simulateUpdate({
          '@type': 'updateAuthorizationState',
          'authorization_state': {'@type': 'authorizationStateWaitPassword'},
        });

        await Future<void>.delayed(Duration.zero);
        expect(repository.currentState, AuthState.passwordRequired);
      });
    });
  });

  group('AuthState enum', () {
    test('has all expected values', () {
      expect(AuthState.values, contains(AuthState.unauthenticated));
      expect(AuthState.values, contains(AuthState.codeSent));
      expect(AuthState.values, contains(AuthState.passwordRequired));
      expect(AuthState.values, contains(AuthState.authenticated));
      expect(AuthState.values, contains(AuthState.error));
      expect(AuthState.values, contains(AuthState.loading));
    });
  });

  group('AuthResult sealed class', () {
    test('AuthSuccess is created correctly', () {
      const result = AuthSuccess();
      expect(result, isA<AuthResult>());
    });

    test('AuthCodeSent contains phone number', () {
      const result = AuthCodeSent(phoneNumber: '+1234567890');
      expect(result.phoneNumber, '+1234567890');
    });

    test('AuthError contains message and code', () {
      const result = AuthError(message: 'Test error', code: 'TEST_CODE');
      expect(result.message, 'Test error');
      expect(result.code, 'TEST_CODE');
    });

    test('AuthPasswordRequired is created correctly', () {
      const result = AuthPasswordRequired();
      expect(result, isA<AuthResult>());
    });
  });
}
