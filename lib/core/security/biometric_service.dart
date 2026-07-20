import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Provides biometric authentication for app lock.
///
/// Wraps platform channels to check availability and authenticate.
class BiometricService {
  BiometricService();

  static const _channel = MethodChannel('com.lumovault/biometric');

  /// Check if biometric authentication is available on the device.
  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isBiometricAvailable');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] Platform error: ${e.message}');
      return false;
    }
  }

  /// Get available biometric types.
  Future<List<String>> getAvailableTypes() async {
    try {
      final result = await _channel.invokeMethod<List>(
        'getAvailableBiometrics',
      );
      return result?.cast<String>() ?? [];
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] Platform error: ${e.message}');
      return [];
    }
  }

  /// Prompt the user for biometric authentication.
  ///
  /// [reason] is the message shown to the user explaining why
  /// authentication is required.
  /// Returns true if authentication succeeded.
  Future<bool> authenticate({required String reason}) async {
    try {
      final result = await _channel.invokeMethod<bool>('authenticate', {
        'reason': reason,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] Platform error: ${e.message}');
      return false;
    }
  }

  /// Check if the device has face recognition.
  Future<bool> hasFaceId() async {
    final types = await getAvailableTypes();
    return types.contains('face') || types.contains('FaceID');
  }

  /// Check if the device has fingerprint sensor.
  Future<bool> hasFingerprint() async {
    final types = await getAvailableTypes();
    return types.contains('fingerprint') || types.contains('TouchID');
  }
}
