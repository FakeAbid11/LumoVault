import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/security/pin_attempt_throttle.dart';

void main() {
  group('PinAttemptThrottle', () {
    late _MemoryThrottleStore store;
    late PinAttemptThrottle throttle;
    final now = DateTime.utc(2026, 7, 30, 12);

    setUp(() {
      store = _MemoryThrottleStore();
      throttle = PinAttemptThrottle(
        store: store,
        attemptsBeforeLockout: 3,
        baseLockout: const Duration(seconds: 30),
        maxLockout: const Duration(minutes: 5),
      );
    });

    test('starts unlocked with no failures', () async {
      final state = await throttle.getState();

      expect(state.failedAttempts, 0);
      expect(state.lockedUntil, isNull);
      expect(state.isLockedOutAt(now), isFalse);
      expect(state.remainingAt(now), Duration.zero);
    });

    test('failures below the threshold do not lock out', () async {
      await throttle.recordFailure(now: now);
      final state = await throttle.recordFailure(now: now);

      expect(state.failedAttempts, 2);
      expect(state.isLockedOutAt(now), isFalse);
    });

    test('the threshold failure starts a base-duration lockout', () async {
      await throttle.recordFailure(now: now);
      await throttle.recordFailure(now: now);
      final state = await throttle.recordFailure(now: now);

      expect(state.failedAttempts, 3);
      expect(state.isLockedOutAt(now), isTrue);
      expect(state.remainingAt(now), const Duration(seconds: 30));
    });

    test('the lockout expires once its deadline passes', () async {
      await throttle.recordFailure(now: now);
      await throttle.recordFailure(now: now);
      final state = await throttle.recordFailure(now: now);

      final later = now.add(const Duration(seconds: 31));
      expect(state.isLockedOutAt(later), isFalse);
      expect(state.remainingAt(later), Duration.zero);
    });

    test('each further failure doubles the lockout', () async {
      for (var i = 0; i < 3; i++) {
        await throttle.recordFailure(now: now);
      }
      final fourth = await throttle.recordFailure(now: now);
      expect(fourth.remainingAt(now), const Duration(minutes: 1));

      final fifth = await throttle.recordFailure(now: now);
      expect(fifth.remainingAt(now), const Duration(minutes: 2));
    });

    test('the lockout is capped at maxLockout', () async {
      for (var i = 0; i < 12; i++) {
        await throttle.recordFailure(now: now);
      }
      final state = await throttle.getState();

      expect(state.remainingAt(now), const Duration(minutes: 5));
    });

    test('recordSuccess clears the failure history', () async {
      for (var i = 0; i < 4; i++) {
        await throttle.recordFailure(now: now);
      }
      await throttle.recordSuccess();
      final state = await throttle.getState();

      expect(state.failedAttempts, 0);
      expect(state.isLockedOutAt(now), isFalse);
      expect(store.values, isEmpty);
    });

    test('state survives a restart via the store', () async {
      for (var i = 0; i < 3; i++) {
        await throttle.recordFailure(now: now);
      }

      // A fresh instance sharing the same store models an app restart.
      final restarted = PinAttemptThrottle(
        store: store,
        attemptsBeforeLockout: 3,
        baseLockout: const Duration(seconds: 30),
        maxLockout: const Duration(minutes: 5),
      );
      final state = await restarted.getState();

      expect(state.failedAttempts, 3);
      expect(state.isLockedOutAt(now), isTrue);
    });

    test('a corrupt stored blob degrades to a clean slate', () async {
      store.values['lumovault_pin_throttle'] = 'not json';

      final state = await PinAttemptThrottle(store: store).getState();

      expect(state.failedAttempts, 0);
      expect(state.lockedUntil, isNull);
    });

    test('a store that throws does not break throttling', () async {
      final failing = PinAttemptThrottle(
        store: _ThrowingThrottleStore(),
        attemptsBeforeLockout: 3,
      );

      await failing.recordFailure(now: now);
      await failing.recordFailure(now: now);
      final state = await failing.recordFailure(now: now);

      expect(state.failedAttempts, 3);
      expect(state.isLockedOutAt(now), isTrue);
    });
  });
}

class _MemoryThrottleStore implements ThrottleStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _ThrowingThrottleStore implements ThrottleStore {
  @override
  Future<String?> read(String key) async => throw StateError('unavailable');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('unavailable');

  @override
  Future<void> delete(String key) async => throw StateError('unavailable');
}
