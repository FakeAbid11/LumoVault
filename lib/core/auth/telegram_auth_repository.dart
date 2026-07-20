import 'dart:async';

import '../tdlib/tdlib_client.dart';
import '../tdlib/tdlib_exception.dart';
import 'auth_service.dart';

/// Real Telegram authentication implementation using TDLib.
///
/// Replaces [StubAuthService] from Prompt 3. Handles the complete
/// Telegram login flow: phone → code → 2FA → authenticated.
///
/// TDLib communicates via an async update stream. This class maps
/// TDLib authorization state updates to [AuthState] transitions.
class TelegramAuthRepository implements AuthService {
  TelegramAuthRepository(this._client, [this._ensureConnected]);

  final TdLibClient _client;

  /// Establishes the underlying TDLib connection (client creation +
  /// `setTdlibParameters`) before this repository relies on it being ready.
  ///
  /// Optional so tests can construct this repository directly against a
  /// fake [TdLibClient] without a real connection manager. Wired to
  /// [tdLibInitializedProvider] in production via [authServiceProvider].
  final Future<void> Function()? _ensureConnected;
  AuthState _currentState = AuthState.unauthenticated;
  final _stateController = StreamController<AuthState>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _updateSubscription;

  @override
  AuthState get currentState => _currentState;

  @override
  Stream<AuthState> get stateStream => _stateController.stream;

  @override
  Future<void> initialize() async {
    if (_ensureConnected != null) {
      await _ensureConnected();
    }

    // Guard against double-subscription if initialize() is called again
    // (e.g. the user retries after a connection failure).
    await _updateSubscription?.cancel();
    // Listen for TDLib authorization state updates.
    _updateSubscription = _client.updates.listen(_handleUpdate);

    // Check current authorization state.
    final state = await _client.getAuthorizationState();
    _syncAuthState(state);

    // `TdLibClient.initialize` returns as soon as its receive loop starts
    // — it does not wait for `setTdlibParameters` to actually be applied,
    // let alone for TDLib to finish validating/restoring a persisted
    // session. So the state just read here can still be the transient
    // `authorizationStateWaitTdlibParameters`, which falls through
    // `_syncAuthState`'s switch to "leave state unchanged" — i.e. stays
    // at the fresh-repository default of `unauthenticated`, even when a
    // valid session is about to be restored a moment later. That race is
    // exactly why the Account screen would show signed-in once (when the
    // handshake happened to finish before this ran) and "Not signed in"
    // another time (when it didn't). Wait for the real settled state
    // instead of trusting this snapshot when it's still transient.
    if (state['@type'] == 'authorizationStateWaitTdlibParameters') {
      try {
        final settled = await _client.updates
            .where((u) => u['@type'] == 'updateAuthorizationState')
            .map((u) => u['authorization_state'] as Map<String, dynamic>?)
            .where(
              (s) =>
                  s != null &&
                  s['@type'] != 'authorizationStateWaitTdlibParameters',
            )
            .cast<Map<String, dynamic>>()
            .first
            .timeout(const Duration(seconds: 10));
        _syncAuthState(settled);
      } on TimeoutException {
        // Bootstrap is taking unusually long — leave the state as last
        // synced rather than blocking the caller indefinitely.
      }
    }
    // Deliberately no catch-all here anymore: a genuine failure to reach
    // TDLib (e.g. a request timeout) used to be swallowed and mapped
    // straight to `unauthenticated`, which told an actually-signed-in user
    // they were signed out and offered a "Sign In" button that could start
    // a redundant second login. Letting it propagate lets callers
    // (accountInfoProvider) surface it as a retryable error instead of a
    // false "not signed in".
  }

  @override
  Future<AuthResult> sendCode(String phoneNumber) async {
    _updateState(AuthState.loading);

    try {
      await _client.sendRequest(
        method: 'setAuthenticationPhoneNumber',
        params: {
          'phone_number': phoneNumber,
          'allow_flash_call': false,
          'is_current_phone_number': true,
        },
      );

      // TDLib will emit authorizationStateWaitCode update.
      // We transition to codeSent optimistically.
      _updateState(AuthState.codeSent);
      return AuthCodeSent(phoneNumber: phoneNumber);
    } on TdLibException catch (e) {
      _updateState(AuthState.error);
      return AuthError(message: e.displayMessage, code: e.code);
    }
  }

  @override
  Future<AuthResult> verifyCode(String code) async {
    _updateState(AuthState.loading);

    try {
      await _client.sendRequest(
        method: 'checkAuthenticationCode',
        params: {'code': code},
      );

      // TDLib will emit the next auth state update.
      // If 2FA is needed, it emits authorizationStateWaitPassword.
      // If auth is complete, it emits authorizationStateReady.
      return const AuthSuccess();
    } on TdLibException catch (e) {
      if (e.code == 'PASSWORD_HASH_INVALID') {
        _updateState(AuthState.passwordRequired);
        return const AuthPasswordRequired();
      }

      _updateState(AuthState.error);
      return AuthError(message: e.displayMessage, code: e.code);
    }
  }

  @override
  Future<AuthResult> submitPassword(String password) async {
    _updateState(AuthState.loading);

    try {
      await _client.sendRequest(
        method: 'checkAuthenticationPassword',
        params: {'password': password},
      );

      return const AuthSuccess();
    } on TdLibException catch (e) {
      _updateState(AuthState.error);
      return AuthError(message: e.displayMessage, code: e.code);
    }
  }

  @override
  Future<void> logout() async {
    _updateState(AuthState.loading);
    try {
      await _client.logOut();
      _updateState(AuthState.unauthenticated);
    } catch (e) {
      _updateState(AuthState.unauthenticated);
    }
  }

  @override
  void dispose() {
    _updateSubscription?.cancel();
    _stateController.close();
  }

  /// Handle TDLib authorization state updates.
  void _handleUpdate(Map<String, dynamic> update) {
    final updateType = update['@type'] as String?;
    if (updateType == null) return;

    // Map TDLib auth state to our AuthState.
    if (updateType == 'updateAuthorizationState') {
      final authState = update['authorization_state'] as Map<String, dynamic>?;
      if (authState != null) {
        _syncAuthState(authState);
      }
    }
  }

  /// Synchronize our AuthState with TDLib's authorization state.
  void _syncAuthState(Map<String, dynamic> tdLibState) {
    final stateType = tdLibState['@type'] as String?;

    final newState = switch (stateType) {
      'authorizationStateWaitPhoneNumber' => AuthState.unauthenticated,
      'authorizationStateWaitCode' => AuthState.codeSent,
      'authorizationStateWaitPassword' => AuthState.passwordRequired,
      'authorizationStateReady' => AuthState.authenticated,
      'authorizationStateLoggingOut' => AuthState.loading,
      'authorizationStateClosing' => AuthState.loading,
      'authorizationStateClosed' => AuthState.unauthenticated,
      _ => _currentState,
    };

    _updateState(newState);
  }

  void _updateState(AuthState newState) {
    if (_currentState == newState) return;
    _currentState = newState;
    _stateController.add(newState);
  }
}
