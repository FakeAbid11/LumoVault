import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal key-value contract the throttle needs from secure storage.
///
/// Narrowing it to three methods keeps [PinAttemptThrottle] testable without
/// a platform channel or a full [FlutterSecureStorage] stand-in.
abstract class ThrottleStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// [ThrottleStore] backed by encrypted platform storage.
class SecureThrottleStore implements ThrottleStore {
  SecureThrottleStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Outcome of asking the throttle whether a PIN attempt may proceed.
class PinLockoutState {
  const PinLockoutState({
    required this.failedAttempts,
    required this.lockedUntil,
  });

  /// Consecutive failed attempts since the last success.
  final int failedAttempts;

  /// When the current lockout expires, or null if not locked out.
  final DateTime? lockedUntil;

  /// Whether attempts are currently refused.
  bool isLockedOutAt(DateTime now) {
    final until = lockedUntil;
    return until != null && now.isBefore(until);
  }

  /// Remaining lockout duration at [now], or [Duration.zero].
  Duration remainingAt(DateTime now) {
    final until = lockedUntil;
    if (until == null || !now.isBefore(until)) return Duration.zero;
    return until.difference(now);
  }
}

/// Rate limits PIN entry so a 6-digit secret can't be brute-forced.
///
/// After [attemptsBeforeLockout] consecutive failures the lock enters a cooldown
/// that doubles with each further failed attempt, capped at [maxLockout]. State
/// is persisted so force-quitting the app doesn't reset the counter.
class PinAttemptThrottle {
  PinAttemptThrottle({
    ThrottleStore? store,
    this.attemptsBeforeLockout = 5,
    this.baseLockout = const Duration(seconds: 30),
    this.maxLockout = const Duration(minutes: 30),
  }) : _store = store ?? SecureThrottleStore();

  static const String _storageKey = 'lumovault_pin_throttle';

  final ThrottleStore _store;

  /// Failures tolerated before the first lockout kicks in.
  final int attemptsBeforeLockout;

  /// Cooldown applied at the first lockout; doubles on each later failure.
  final Duration baseLockout;

  /// Upper bound on the cooldown.
  final Duration maxLockout;

  PinLockoutState? _cache;

  /// Read the current lockout state.
  Future<PinLockoutState> getState() async {
    final cached = _cache;
    if (cached != null) return cached;

    try {
      final raw = await _store.read(_storageKey);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final until = map['lockedUntil'] as String?;
        return _cache = PinLockoutState(
          failedAttempts: map['failedAttempts'] as int? ?? 0,
          lockedUntil: until == null ? null : DateTime.tryParse(until),
        );
      }
    } catch (e) {
      debugPrint('[PinAttemptThrottle] Corrupt throttle state, resetting: $e');
    }

    return _cache = const PinLockoutState(failedAttempts: 0, lockedUntil: null);
  }

  /// Record a failed attempt and return the resulting state.
  Future<PinLockoutState> recordFailure({DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc();
    final current = await getState();
    final attempts = current.failedAttempts + 1;

    DateTime? lockedUntil;
    if (attempts >= attemptsBeforeLockout) {
      final overshoot = attempts - attemptsBeforeLockout;
      var cooldown = baseLockout * (1 << overshoot.clamp(0, 16));
      if (cooldown > maxLockout) cooldown = maxLockout;
      lockedUntil = at.add(cooldown);
    }

    return _write(
      PinLockoutState(failedAttempts: attempts, lockedUntil: lockedUntil),
    );
  }

  /// Clear all failure history after a successful unlock.
  Future<void> recordSuccess() async {
    _cache = const PinLockoutState(failedAttempts: 0, lockedUntil: null);
    try {
      await _store.delete(_storageKey);
    } catch (e) {
      debugPrint('[PinAttemptThrottle] Failed to delete stale throttle blob: $e');
    }
  }

  Future<PinLockoutState> _write(PinLockoutState state) async {
    _cache = state;
    try {
      await _store.write(
        _storageKey,
        jsonEncode({
          'failedAttempts': state.failedAttempts,
          'lockedUntil': state.lockedUntil?.toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('[PinAttemptThrottle] Persistence failed (session-only throttle): $e');
    }
    return state;
  }
}
