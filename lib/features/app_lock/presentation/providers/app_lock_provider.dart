import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/production_providers.dart';
import '../../../../core/security/biometric_service.dart';
import '../../../settings/presentation/providers/settings_providers.dart';

/// Whether the app lock is armed at all.
final appLockEnabledProvider = Provider<bool>((ref) {
  final s = ref.watch(appSettingsProvider);
  return s.biometricLockEnabled || (s.pinLockEnabled && s.pinHash != null);
});

/// State of the app lock screen.
@immutable
class AppLockState {
  const AppLockState({
    required this.locked,
    this.checking = false,
    this.error,
    this.lockedOutUntil,
  });

  /// True while the vault contents must stay hidden.
  final bool locked;

  /// True while a biometric prompt or PIN verification is running.
  final bool checking;

  /// User-facing error from the last attempt.
  final String? error;

  /// When the PIN throttle's cooldown expires, if any.
  final DateTime? lockedOutUntil;

  AppLockState copyWith({
    bool? locked,
    bool? checking,
    String? error,
    bool clearError = false,
    DateTime? lockedOutUntil,
    bool clearLockout = false,
  }) {
    return AppLockState(
      locked: locked ?? this.locked,
      checking: checking ?? this.checking,
      error: clearError ? null : (error ?? this.error),
      lockedOutUntil: clearLockout
          ? null
          : (lockedOutUntil ?? this.lockedOutUntil),
    );
  }
}

/// Drives the app lock: biometric prompt, PIN verification, and re-locking.
class AppLockController extends StateNotifier<AppLockState> {
  AppLockController(this._ref, {required bool initiallyLocked})
    : super(AppLockState(locked: initiallyLocked));

  final Ref _ref;

  /// Lock the app — called when it goes to the background.
  void lock() {
    if (state.locked) return;
    state = const AppLockState(locked: true);
  }

  /// Unlock without a challenge. Only for the case where the lock was
  /// disabled while the lock screen was showing.
  void unlockWithoutChallenge() {
    state = const AppLockState(locked: false);
  }

  /// Prompt for biometrics. Returns true if the app was unlocked.
  Future<bool> authenticateWithBiometrics() async {
    if (state.checking) return false;
    state = state.copyWith(checking: true, clearError: true);

    final result = await _ref
        .read(biometricServiceProvider)
        .authenticateWithResult(reason: 'Unlock LumoVault');

    if (result.succeeded) {
      state = const AppLockState(locked: false);
      return true;
    }

    state = state.copyWith(checking: false, error: _describe(result.failure));
    return false;
  }

  /// Verify [pin] against the stored hash, honouring the attempt throttle.
  Future<bool> submitPin(String pin) async {
    if (state.checking) return false;

    final throttle = _ref.read(pinAttemptThrottleProvider);
    final lockout = await throttle.getState();
    final now = DateTime.now().toUtc();
    if (lockout.isLockedOutAt(now)) {
      state = state.copyWith(
        error: _lockoutMessage(lockout.remainingAt(now)),
        lockedOutUntil: lockout.lockedUntil,
      );
      return false;
    }

    state = state.copyWith(checking: true, clearError: true);

    final settings = _ref.read(appSettingsProvider);
    final pinService = _ref.read(pinServiceProvider);
    final ok = await pinService.verifyPin(pin: pin, encoded: settings.pinHash);

    if (!ok) {
      final updated = await throttle.recordFailure(now: now);
      final remaining = updated.remainingAt(now);
      state = state.copyWith(
        checking: false,
        error: remaining > Duration.zero
            ? _lockoutMessage(remaining)
            : 'Incorrect PIN.',
        lockedOutUntil: updated.lockedUntil,
        clearLockout: updated.lockedUntil == null,
      );
      return false;
    }

    await throttle.recordSuccess();

    // Transparently upgrade hashes created with weaker parameters.
    if (pinService.needsRehash(settings.pinHash)) {
      await _ref
          .read(appSettingsProvider.notifier)
          .updateField((s) => s.copyWith(pinHash: pinService.hashPin(pin)));
    }

    state = const AppLockState(locked: false);
    return true;
  }

  String _describe(BiometricFailure? failure) {
    switch (failure) {
      case BiometricFailure.rejected:
      case null:
        return 'Authentication cancelled.';
      case BiometricFailure.noCredentialsSet:
        return 'No device credentials are set up.';
      case BiometricFailure.noHardware:
        return 'No usable biometric hardware on this device.';
      case BiometricFailure.temporaryLockout:
        return 'Too many attempts. Try again shortly.';
      case BiometricFailure.biometricLockout:
        return 'Biometrics locked. Unlock your device first.';
      case BiometricFailure.fallbackRequested:
        return 'Use your PIN instead.';
      case BiometricFailure.unsupported:
        return 'Biometric unlock is unavailable on this device.';
      case BiometricFailure.error:
        return 'Authentication failed. Try again.';
    }
  }

  String _lockoutMessage(Duration remaining) {
    final seconds = remaining.inSeconds;
    if (seconds >= 60) {
      final minutes = (seconds / 60).ceil();
      return 'Too many attempts. Try again in $minutes min.';
    }
    return 'Too many attempts. Try again in $seconds s.';
  }
}

/// App lock state provider.
///
/// Starts locked whenever a lock is configured, so the very first frame after
/// launch is the lock screen rather than the timeline.
final appLockProvider = StateNotifierProvider<AppLockController, AppLockState>((
  ref,
) {
  final settings = ref.read(appSettingsProvider);
  final enabled =
      settings.biometricLockEnabled ||
      (settings.pinLockEnabled && settings.pinHash != null);
  return AppLockController(
    ref,
    initiallyLocked: enabled && settings.requireAuthOnAppOpen,
  );
});
