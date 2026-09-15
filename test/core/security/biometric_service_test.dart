import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lumovault/core/security/biometric_service.dart';

void main() {
  group('BiometricService availability', () {
    test(
      'isAvailable is true when supported and biometrics can be checked',
      () async {
        final service = BiometricService(
          backend: _FakeBackend(deviceSupported: true, canCheck: true),
        );

        expect(await service.isAvailable(), isTrue);
      },
    );

    test('isAvailable is false when the device is unsupported', () async {
      final service = BiometricService(
        backend: _FakeBackend(deviceSupported: false, canCheck: true),
      );

      expect(await service.isAvailable(), isFalse);
    });

    test('isAvailable is false when biometrics cannot be checked', () async {
      final service = BiometricService(
        backend: _FakeBackend(deviceSupported: true, canCheck: false),
      );

      expect(await service.isAvailable(), isFalse);
    });

    test('isAvailable is false on a platform exception', () async {
      final service = BiometricService(
        backend: _FakeBackend(error: PlatformException(code: 'NOT_AVAILABLE')),
      );

      expect(await service.isAvailable(), isFalse);
    });

    test('isAvailable is false when the plugin is missing', () async {
      // MissingPluginException does not extend PlatformException, so this is
      // the case that used to escape uncaught.
      final service = BiometricService(
        backend: _FakeBackend(error: MissingPluginException('no impl')),
      );

      expect(await service.isAvailable(), isFalse);
    });

    test('isAvailable is false on a LocalAuthException', () async {
      final service = BiometricService(
        backend: _FakeBackend(
          error: const LocalAuthException(
            code: LocalAuthExceptionCode.deviceError,
          ),
        ),
      );

      expect(await service.isAvailable(), isFalse);
    });
  });

  group('BiometricService enrolled types', () {
    test('getAvailableTypes maps plugin types to BiometricKind', () async {
      final service = BiometricService(
        backend: _FakeBackend(
          enrolled: const [BiometricType.fingerprint, BiometricType.face],
        ),
      );

      expect(await service.getAvailableTypes(), [
        BiometricKind.fingerprint,
        BiometricKind.face,
      ]);
    });

    test('getAvailableTypes is empty on a platform exception', () async {
      final service = BiometricService(
        backend: _FakeBackend(error: PlatformException(code: 'ERROR')),
      );

      expect(await service.getAvailableTypes(), isEmpty);
    });

    test('getAvailableTypes is empty when the plugin is missing', () async {
      final service = BiometricService(
        backend: _FakeBackend(error: MissingPluginException('no impl')),
      );

      expect(await service.getAvailableTypes(), isEmpty);
    });

    test('hasFaceId is true only when face is enrolled', () async {
      expect(
        await BiometricService(
          backend: _FakeBackend(enrolled: const [BiometricType.face]),
        ).hasFaceId(),
        isTrue,
      );
      expect(
        await BiometricService(
          backend: _FakeBackend(enrolled: const [BiometricType.fingerprint]),
        ).hasFaceId(),
        isFalse,
      );
    });

    test('hasFingerprint is true only when fingerprint is enrolled', () async {
      expect(
        await BiometricService(
          backend: _FakeBackend(enrolled: const [BiometricType.fingerprint]),
        ).hasFingerprint(),
        isTrue,
      );
      expect(
        await BiometricService(
          backend: _FakeBackend(enrolled: const [BiometricType.face]),
        ).hasFingerprint(),
        isFalse,
      );
    });
  });

  group('BiometricService authenticate', () {
    test('returns true when the platform authenticates', () async {
      final service = BiometricService(
        backend: _FakeBackend(authenticates: true),
      );

      expect(await service.authenticate(reason: 'Unlock'), isTrue);
    });

    test('returns false when the user fails the prompt', () async {
      final service = BiometricService(
        backend: _FakeBackend(authenticates: false),
      );

      final result = await service.authenticateWithResult(reason: 'Unlock');
      expect(result.succeeded, isFalse);
      expect(result.failure, BiometricFailure.rejected);
    });

    test('reports unsupported when the plugin is missing', () async {
      final service = BiometricService(
        backend: _FakeBackend(error: MissingPluginException('no impl')),
      );

      final result = await service.authenticateWithResult(reason: 'Unlock');
      expect(result.succeeded, isFalse);
      expect(result.failure, BiometricFailure.unsupported);
    });

    test('reports error on a platform exception', () async {
      final service = BiometricService(
        backend: _FakeBackend(error: PlatformException(code: 'AUTH_FAILED')),
      );

      final result = await service.authenticateWithResult(reason: 'Unlock');
      expect(result.succeeded, isFalse);
      expect(result.failure, BiometricFailure.error);
    });

    test('maps LocalAuthException codes to failure reasons', () async {
      Future<BiometricFailure?> failureFor(LocalAuthExceptionCode code) async {
        final service = BiometricService(
          backend: _FakeBackend(error: LocalAuthException(code: code)),
        );
        final result = await service.authenticateWithResult(reason: 'Unlock');
        return result.failure;
      }

      expect(
        await failureFor(LocalAuthExceptionCode.userCanceled),
        BiometricFailure.rejected,
      );
      expect(
        await failureFor(LocalAuthExceptionCode.noCredentialsSet),
        BiometricFailure.noCredentialsSet,
      );
      expect(
        await failureFor(LocalAuthExceptionCode.noBiometricHardware),
        BiometricFailure.noHardware,
      );
      expect(
        await failureFor(LocalAuthExceptionCode.temporaryLockout),
        BiometricFailure.temporaryLockout,
      );
      expect(
        await failureFor(LocalAuthExceptionCode.biometricLockout),
        BiometricFailure.biometricLockout,
      );
      expect(
        await failureFor(LocalAuthExceptionCode.userRequestedFallback),
        BiometricFailure.fallbackRequested,
      );
      expect(
        await failureFor(LocalAuthExceptionCode.deviceError),
        BiometricFailure.error,
      );
    });

    test('passes biometricOnly through to the backend', () async {
      final backend = _FakeBackend(authenticates: true);
      final service = BiometricService(backend: backend);

      await service.authenticate(reason: 'Unlock', biometricOnly: true);
      expect(backend.lastBiometricOnly, isTrue);
      expect(backend.lastReason, 'Unlock');

      await service.authenticate(reason: 'Unlock');
      expect(backend.lastBiometricOnly, isFalse);
    });
  });
}

class _FakeBackend implements LocalAuthBackend {
  _FakeBackend({
    this.deviceSupported = true,
    this.canCheck = true,
    this.enrolled = const [],
    this.authenticates = true,
    this.error,
  });

  final bool deviceSupported;
  final bool canCheck;
  final List<BiometricType> enrolled;
  final bool authenticates;

  /// Thrown by every method when set, modelling a failing platform.
  final Object? error;

  String? lastReason;
  bool? lastBiometricOnly;

  @override
  Future<bool> isDeviceSupported() async {
    if (error != null) throw error!;
    return deviceSupported;
  }

  @override
  Future<bool> canCheckBiometrics() async {
    if (error != null) throw error!;
    return canCheck;
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (error != null) throw error!;
    return enrolled;
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required bool biometricOnly,
  }) async {
    lastReason = localizedReason;
    lastBiometricOnly = biometricOnly;
    if (error != null) throw error!;
    return authenticates;
  }
}
