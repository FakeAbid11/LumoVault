import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// The biometric capabilities the app cares about.
enum BiometricKind { face, fingerprint, iris, strong, weak }

/// Why an authentication attempt did not succeed.
enum BiometricFailure {
  /// The user was shown the prompt and dismissed or failed it.
  rejected,

  /// No biometrics, PIN, pattern or passcode is configured on the device.
  noCredentialsSet,

  /// The device has no usable biometric hardware.
  noHardware,

  /// Too many failed attempts; retry later.
  temporaryLockout,

  /// Biometrics are locked until the device credential is entered.
  biometricLockout,

  /// The user asked for the non-biometric fallback.
  fallbackRequested,

  /// Biometric auth is not available at all on this platform/build.
  unsupported,

  /// Anything else, including device-level errors.
  error,
}

/// Result of an authentication attempt.
class BiometricAuthResult {
  const BiometricAuthResult.success()
    : succeeded = true,
      failure = null,
      message = null;

  const BiometricAuthResult.failed(this.failure, {this.message})
    : succeeded = false;

  final bool succeeded;

  /// Null when [succeeded] is true.
  final BiometricFailure? failure;

  /// Platform-supplied detail, for logs — not for display.
  final String? message;
}

/// Abstraction over the `local_auth` plugin.
///
/// Exists so [BiometricService] can be unit tested without a platform
/// implementation; production uses [PluginLocalAuthBackend].
abstract class LocalAuthBackend {
  Future<bool> isDeviceSupported();

  Future<bool> canCheckBiometrics();

  Future<List<BiometricType>> getAvailableBiometrics();

  Future<bool> authenticate({
    required String localizedReason,
    required bool biometricOnly,
  });
}

/// [LocalAuthBackend] backed by the real `local_auth` plugin.
class PluginLocalAuthBackend implements LocalAuthBackend {
  PluginLocalAuthBackend({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isDeviceSupported() => _auth.isDeviceSupported();

  @override
  Future<bool> canCheckBiometrics() => _auth.canCheckBiometrics;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() =>
      _auth.getAvailableBiometrics();

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required bool biometricOnly,
  }) => _auth.authenticate(
    localizedReason: localizedReason,
    biometricOnly: biometricOnly,
  );
}

/// Provides biometric authentication for app lock.
///
/// Backed by the `local_auth` plugin. Every entry point degrades gracefully:
/// platform errors, and a [MissingPluginException] on builds or platforms
/// without a native implementation, are reported as an unavailable/failed
/// result rather than propagating to the caller.
class BiometricService {
  BiometricService({LocalAuthBackend? backend})
    : _backend = backend ?? PluginLocalAuthBackend();

  final LocalAuthBackend _backend;

  /// Check if biometric authentication is available on the device.
  ///
  /// True only when the hardware exists, credentials are enrolled, and the
  /// platform implementation is present.
  Future<bool> isAvailable() async {
    try {
      if (!await _backend.isDeviceSupported()) return false;
      return await _backend.canCheckBiometrics();
    } on MissingPluginException catch (e) {
      // Thrown on platforms with no local_auth implementation. It does NOT
      // extend PlatformException, so it needs its own clause.
      debugPrint('[BiometricService] Plugin unavailable: ${e.message}');
      return false;
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] Platform error: ${e.message}');
      return false;
    } on LocalAuthException catch (e) {
      debugPrint('[BiometricService] Auth error: ${e.description}');
      return false;
    }
  }

  /// Get available biometric types enrolled on this device.
  Future<List<BiometricKind>> getAvailableTypes() async {
    try {
      final types = await _backend.getAvailableBiometrics();
      return types.map(_toKind).toList();
    } on MissingPluginException catch (e) {
      debugPrint('[BiometricService] Plugin unavailable: ${e.message}');
      return const [];
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] Platform error: ${e.message}');
      return const [];
    } on LocalAuthException catch (e) {
      debugPrint('[BiometricService] Auth error: ${e.description}');
      return const [];
    }
  }

  /// Prompt the user for biometric authentication.
  ///
  /// [reason] is shown to the user explaining why authentication is required.
  /// Set [biometricOnly] to false to let the user fall back to their device
  /// PIN/pattern/passcode.
  Future<BiometricAuthResult> authenticateWithResult({
    required String reason,
    bool biometricOnly = false,
  }) async {
    try {
      final ok = await _backend.authenticate(
        localizedReason: reason,
        biometricOnly: biometricOnly,
      );
      return ok
          ? const BiometricAuthResult.success()
          : const BiometricAuthResult.failed(BiometricFailure.rejected);
    } on MissingPluginException catch (e) {
      debugPrint('[BiometricService] Plugin unavailable: ${e.message}');
      return BiometricAuthResult.failed(
        BiometricFailure.unsupported,
        message: e.message,
      );
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] Platform error: ${e.message}');
      return BiometricAuthResult.failed(
        BiometricFailure.error,
        message: e.message,
      );
    } on LocalAuthException catch (e) {
      debugPrint('[BiometricService] Auth error: ${e.code.name}');
      return BiometricAuthResult.failed(
        _toFailure(e.code),
        message: e.description,
      );
    }
  }

  /// Prompt the user for biometric authentication.
  ///
  /// Returns true if authentication succeeded. Use [authenticateWithResult]
  /// when the caller needs to distinguish *why* it failed.
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
    final result = await authenticateWithResult(
      reason: reason,
      biometricOnly: biometricOnly,
    );
    return result.succeeded;
  }

  /// Check if the device has face recognition enrolled.
  Future<bool> hasFaceId() async {
    final types = await getAvailableTypes();
    return types.contains(BiometricKind.face);
  }

  /// Check if the device has a fingerprint enrolled.
  Future<bool> hasFingerprint() async {
    final types = await getAvailableTypes();
    return types.contains(BiometricKind.fingerprint);
  }

  BiometricKind _toKind(BiometricType type) {
    switch (type) {
      case BiometricType.face:
        return BiometricKind.face;
      case BiometricType.fingerprint:
        return BiometricKind.fingerprint;
      case BiometricType.iris:
        return BiometricKind.iris;
      case BiometricType.strong:
        return BiometricKind.strong;
      case BiometricType.weak:
        return BiometricKind.weak;
    }
  }

  BiometricFailure _toFailure(LocalAuthExceptionCode code) {
    switch (code) {
      case LocalAuthExceptionCode.userCanceled:
      case LocalAuthExceptionCode.systemCanceled:
      case LocalAuthExceptionCode.timeout:
        return BiometricFailure.rejected;
      case LocalAuthExceptionCode.noCredentialsSet:
        return BiometricFailure.noCredentialsSet;
      case LocalAuthExceptionCode.noBiometricHardware:
      case LocalAuthExceptionCode.noBiometricsEnrolled:
      case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
        return BiometricFailure.noHardware;
      case LocalAuthExceptionCode.temporaryLockout:
        return BiometricFailure.temporaryLockout;
      case LocalAuthExceptionCode.biometricLockout:
        return BiometricFailure.biometricLockout;
      case LocalAuthExceptionCode.userRequestedFallback:
        return BiometricFailure.fallbackRequested;
      case LocalAuthExceptionCode.uiUnavailable:
      case LocalAuthExceptionCode.authInProgress:
      case LocalAuthExceptionCode.deviceError:
      case LocalAuthExceptionCode.unknownError:
        return BiometricFailure.error;
    }
  }
}
