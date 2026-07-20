/// Authentication service interface for Telegram login.
///
/// Defines the contract for TDLib-based authentication.
/// Prompt 4/5 will replace the stub with real TDLib implementation.
abstract class AuthService {
  /// Current authentication state.
  AuthState get currentState;

  /// Stream of authentication state changes.
  Stream<AuthState> get stateStream;

  /// Initialize the auth service and TDLib client.
  Future<void> initialize();

  /// Send a login code to the provided phone number.
  ///
  /// Returns [AuthCodeSent] on success, or [AuthError] on failure.
  Future<AuthResult> sendCode(String phoneNumber);

  /// Verify the login code.
  ///
  /// Returns [AuthSuccess] on success, [AuthPasswordRequired] if 2FA is
  /// needed, or [AuthError] on failure.
  Future<AuthResult> verifyCode(String code);

  /// Submit the 2FA password.
  ///
  /// Returns [AuthSuccess] on success, or [AuthError] on failure.
  Future<AuthResult> submitPassword(String password);

  /// Log out the current user.
  Future<void> logout();

  /// Dispose of resources.
  void dispose();
}

/// Authentication states.
enum AuthState {
  /// Initial state, not yet authenticated.
  unauthenticated,

  /// Code has been sent, awaiting user input.
  codeSent,

  /// 2FA password required.
  passwordRequired,

  /// Successfully authenticated.
  authenticated,

  /// An error occurred.
  error,

  /// Loading/processing.
  loading,
}

/// Result of an authentication operation.
sealed class AuthResult {
  const AuthResult();
}

/// Authentication was successful.
class AuthSuccess extends AuthResult {
  const AuthSuccess();
}

/// Login code was sent successfully.
class AuthCodeSent extends AuthResult {
  const AuthCodeSent({required this.phoneNumber});

  final String phoneNumber;
}

/// 2FA password is required.
class AuthPasswordRequired extends AuthResult {
  const AuthPasswordRequired();
}

/// Authentication error.
class AuthError extends AuthResult {
  const AuthError({required this.message, this.code});

  final String message;
  final String? code;
}
