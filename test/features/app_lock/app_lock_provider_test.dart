import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lumovault/core/di/production_providers.dart';
import 'package:lumovault/core/security/biometric_service.dart';
import 'package:lumovault/core/security/pin_attempt_throttle.dart';
import 'package:lumovault/core/security/pin_service.dart';
import 'package:lumovault/features/app_lock/presentation/providers/app_lock_provider.dart';
import 'package:lumovault/features/settings/data/models/app_settings.dart';
import 'package:lumovault/features/settings/data/repositories/settings_repository.dart';
import 'package:lumovault/features/settings/presentation/providers/settings_providers.dart';

void main() {
  // Low iterations keep the PBKDF2 work negligible in tests.
  final pinService = PinService(iterations: 1000);
  final validHash = pinService.hashPin('135790');

  /// Build a container with [settings] already applied.
  ///
  /// The repository cache is primed *before* the container is built, so
  /// SettingsNotifier's async `_init()` reads the seeded value from cache
  /// instead of racing us and falling back to defaults. SettingsRepository
  /// swallows its own storage errors, so this needs no plugin registrant.
  Future<ProviderContainer> makeContainer({
    AppSettings settings = const AppSettings(),
    BiometricService? biometrics,
    PinAttemptThrottle? throttle,
  }) async {
    final repository = SettingsRepository();
    addTearDown(repository.dispose);
    await repository.updateSettings(settings);

    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repository),
        pinServiceProvider.overrideWithValue(pinService),
        pinAttemptThrottleProvider.overrideWithValue(
          throttle ??
              PinAttemptThrottle(
                store: _MemoryThrottleStore(),
                attemptsBeforeLockout: 3,
                baseLockout: const Duration(seconds: 30),
              ),
        ),
        biometricServiceProvider.overrideWithValue(
          biometrics ??
              BiometricService(backend: _FakeBackend(authenticates: true)),
        ),
      ],
    );
    addTearDown(container.dispose);

    // appLockProvider reads settings synchronously at construction, so make
    // sure the notifier has hydrated from the primed cache first.
    container.read(appSettingsProvider);
    await Future<void>.delayed(Duration.zero);

    return container;
  }

  group('appLockEnabledProvider', () {
    test('is false when no lock is configured', () async {
      final container = await makeContainer();
      expect(container.read(appLockEnabledProvider), isFalse);
    });

    test('is true when biometric lock is on', () async {
      final container = await makeContainer(
        settings: const AppSettings(biometricLockEnabled: true),
      );
      expect(container.read(appLockEnabledProvider), isTrue);
    });

    test('PIN lock without a stored hash does not count as enabled', () async {
      final container = await makeContainer(
        settings: const AppSettings(pinLockEnabled: true),
      );
      expect(container.read(appLockEnabledProvider), isFalse);
    });

    test('is true when PIN lock is on and a hash exists', () async {
      final container = await makeContainer(
        settings: AppSettings(pinLockEnabled: true, pinHash: validHash),
      );
      expect(container.read(appLockEnabledProvider), isTrue);
    });
  });

  group('AppLockController initial state', () {
    test('starts unlocked when no lock is configured', () async {
      final container = await makeContainer();
      expect(container.read(appLockProvider).locked, isFalse);
    });

    test('starts locked when a lock is armed for app open', () async {
      final container = await makeContainer(
        settings: AppSettings(
          pinLockEnabled: true,
          pinHash: validHash,
          requireAuthOnAppOpen: true,
        ),
      );
      expect(container.read(appLockProvider).locked, isTrue);
    });

    test('starts unlocked when the lock is not required on app open', () async {
      final container = await makeContainer(
        settings: AppSettings(pinLockEnabled: true, pinHash: validHash),
      );
      expect(container.read(appLockProvider).locked, isFalse);
    });
  });

  group('AppLockController.submitPin', () {
    Future<ProviderContainer> lockedContainer({PinAttemptThrottle? throttle}) {
      return makeContainer(
        settings: AppSettings(
          pinLockEnabled: true,
          pinHash: validHash,
          requireAuthOnAppOpen: true,
        ),
        throttle: throttle,
      );
    }

    test('the correct PIN unlocks', () async {
      final container = await lockedContainer();

      final ok = await container
          .read(appLockProvider.notifier)
          .submitPin('135790');

      expect(ok, isTrue);
      expect(container.read(appLockProvider).locked, isFalse);
      expect(container.read(appLockProvider).error, isNull);
    });

    test('a wrong PIN stays locked and reports an error', () async {
      final container = await lockedContainer();

      final ok = await container
          .read(appLockProvider.notifier)
          .submitPin('000000');

      expect(ok, isFalse);
      expect(container.read(appLockProvider).locked, isTrue);
      expect(container.read(appLockProvider).error, 'Incorrect PIN.');
    });

    test('repeated wrong PINs trigger the throttle', () async {
      final container = await lockedContainer();
      final notifier = container.read(appLockProvider.notifier);

      for (var i = 0; i < 3; i++) {
        await notifier.submitPin('000000');
      }

      final state = container.read(appLockProvider);
      expect(state.locked, isTrue);
      expect(state.error, contains('Too many attempts'));
      expect(state.lockedOutUntil, isNotNull);
    });

    test('the correct PIN is refused while throttled', () async {
      final container = await lockedContainer();
      final notifier = container.read(appLockProvider.notifier);

      for (var i = 0; i < 3; i++) {
        await notifier.submitPin('000000');
      }

      final ok = await notifier.submitPin('135790');

      expect(ok, isFalse);
      expect(container.read(appLockProvider).locked, isTrue);
    });

    test('a successful unlock resets the failure count', () async {
      final throttle = PinAttemptThrottle(
        store: _MemoryThrottleStore(),
        attemptsBeforeLockout: 3,
      );
      final container = await lockedContainer(throttle: throttle);
      final notifier = container.read(appLockProvider.notifier);

      await notifier.submitPin('000000');
      await notifier.submitPin('135790');

      expect((await throttle.getState()).failedAttempts, 0);
    });

    test('a PIN is refused when no hash is stored', () async {
      final container = await makeContainer(
        settings: const AppSettings(
          biometricLockEnabled: true,
          requireAuthOnAppOpen: true,
        ),
      );

      final ok = await container
          .read(appLockProvider.notifier)
          .submitPin('135790');

      expect(ok, isFalse);
    });
  });

  group('AppLockController.authenticateWithBiometrics', () {
    Future<ProviderContainer> biometricContainer(BiometricService service) {
      return makeContainer(
        settings: const AppSettings(
          biometricLockEnabled: true,
          requireAuthOnAppOpen: true,
        ),
        biometrics: service,
      );
    }

    test('a successful prompt unlocks', () async {
      final container = await biometricContainer(
        BiometricService(backend: _FakeBackend(authenticates: true)),
      );

      final ok = await container
          .read(appLockProvider.notifier)
          .authenticateWithBiometrics();

      expect(ok, isTrue);
      expect(container.read(appLockProvider).locked, isFalse);
    });

    test('a rejected prompt stays locked with a message', () async {
      final container = await biometricContainer(
        BiometricService(backend: _FakeBackend(authenticates: false)),
      );

      final ok = await container
          .read(appLockProvider.notifier)
          .authenticateWithBiometrics();

      expect(ok, isFalse);
      expect(container.read(appLockProvider).locked, isTrue);
      expect(container.read(appLockProvider).error, isNotNull);
      expect(container.read(appLockProvider).checking, isFalse);
    });
  });

  group('AppLockController.lock', () {
    test('lock re-arms the challenge', () async {
      final container = await makeContainer(
        settings: AppSettings(pinLockEnabled: true, pinHash: validHash),
      );
      expect(container.read(appLockProvider).locked, isFalse);

      container.read(appLockProvider.notifier).lock();

      expect(container.read(appLockProvider).locked, isTrue);
    });

    test('unlockWithoutChallenge clears the lock', () async {
      final container = await makeContainer(
        settings: AppSettings(
          pinLockEnabled: true,
          pinHash: validHash,
          requireAuthOnAppOpen: true,
        ),
      );

      container.read(appLockProvider.notifier).unlockWithoutChallenge();

      expect(container.read(appLockProvider).locked, isFalse);
    });
  });
}

class _MemoryThrottleStore implements ThrottleStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _FakeBackend implements LocalAuthBackend {
  _FakeBackend({required this.authenticates});

  final bool authenticates;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> canCheckBiometrics() async => true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [];

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required bool biometricOnly,
  }) async => authenticates;
}
