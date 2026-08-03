import 'dart:async';

import 'package:lumovault/core/auth/auth_service.dart';

/// Stub implementation of [AuthService] for development and testing.
///
/// Simulates the Telegram authentication flow with realistic delays
/// and state transitions.
class StubAuthService implements AuthService {
  StubAuthService({
    this.simulateDelay = const Duration(milliseconds: 800),
    this.shouldFail = false,
    this.requirePassword = false,
  });

  /// Simulated network delay for each operation.
  final Duration simulateDelay;

  /// If true, all operations will fail with an error.
  final bool shouldFail;

  /// If true, verifyCode will return password required.
  final bool requirePassword;

  AuthState _currentState = AuthState.unauthenticated;
  bool _initialized = false;
  final _stateController = StreamController<AuthState>.broadcast();

  @override
  AuthState get currentState => _currentState;

  @override
  Stream<AuthState> get stateStream => _stateController.stream;

  void _updateState(AuthState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  @override
  Future<void> initialize() async {
    await Future<void>.delayed(simulateDelay);
    if (!_initialized) {
      _initialized = true;
      _updateState(AuthState.unauthenticated);
    }
  }

  @override
  Future<AuthResult> sendCode(String phoneNumber) async {
    _updateState(AuthState.loading);
    await Future<void>.delayed(simulateDelay);

    if (shouldFail) {
      _updateState(AuthState.error);
      return const AuthError(
        message: 'Failed to send code. Please check your phone number.',
        code: 'PHONE_INVALID',
      );
    }

    _updateState(AuthState.codeSent);
    return AuthCodeSent(phoneNumber: phoneNumber);
  }

  @override
  Future<AuthResult> verifyCode(String code) async {
    _updateState(AuthState.loading);
    await Future<void>.delayed(simulateDelay);

    if (shouldFail) {
      _updateState(AuthState.error);
      return const AuthError(
        message: 'Invalid code. Please try again.',
        code: 'CODE_INVALID',
      );
    }

    if (requirePassword) {
      _updateState(AuthState.passwordRequired);
      return const AuthPasswordRequired();
    }

    _updateState(AuthState.authenticated);
    return const AuthSuccess();
  }

  @override
  Future<AuthResult> submitPassword(String password) async {
    _updateState(AuthState.loading);
    await Future<void>.delayed(simulateDelay);

    if (shouldFail) {
      _updateState(AuthState.error);
      return const AuthError(
        message: 'Incorrect password. Please try again.',
        code: 'PASSWORD_INVALID',
      );
    }

    _updateState(AuthState.authenticated);
    return const AuthSuccess();
  }

  @override
  Future<void> logout() async {
    _updateState(AuthState.loading);
    await Future<void>.delayed(simulateDelay);
    _updateState(AuthState.unauthenticated);
  }

  @override
  void dispose() {
    _stateController.close();
  }
}
