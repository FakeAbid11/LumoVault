import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/logging/app_logger.dart';
import '../../data/models/app_settings.dart';
import '../../data/repositories/settings_repository.dart';

/// Platform package info (version, build number) resolved once at runtime.
///
/// Replaces the hardcoded version strings the About/Developer screens used to
/// carry, so they always reflect the actual installed build.
final appPackageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

/// Provider for the settings repository instance.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final repo = SettingsRepository();
  ref.onDispose(() => repo.dispose());
  return repo;
});

/// Notifier for managing app settings state.
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._repository) : super(const AppSettings()) {
    _init();
  }

  final SettingsRepository _repository;
  StreamSubscription<AppSettings>? _subscription;

  Future<void> _init() async {
    state = await _repository.getSettings();
    AppLogger.verboseEnabled = state.debugMode;
    _subscription = _repository.changes.listen((settings) {
      state = settings;
      AppLogger.verboseEnabled = settings.debugMode;
    });
  }

  /// Update the full settings object.
  Future<void> update(AppSettings settings) async {
    await _repository.updateSettings(settings);
  }

  /// Update a single field.
  Future<void> updateField(
    AppSettings Function(AppSettings current) updater,
  ) async {
    await _repository.updateField(updater);
  }

  /// Mark onboarding as completed.
  Future<void> completeOnboarding() async {
    await _repository.completeOnboarding();
  }

  /// Persist the resolved backup storage channel id.
  Future<void> setStorageChannelId(int channelId) async {
    await _repository.setStorageChannelId(channelId);
  }

  /// Reset all settings to defaults.
  Future<void> resetToDefaults() async {
    await _repository.resetToDefaults();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Central settings provider — the single source of truth for all settings.
final appSettingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
      final repository = ref.watch(settingsRepositoryProvider);
      return SettingsNotifier(repository);
    });

// -- Convenience providers for specific settings --

/// Current theme mode.
final settingsThemeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(appSettingsProvider).themeMode;
});

/// Whether dynamic color is enabled.
final settingsDynamicColorProvider = Provider<bool>((ref) {
  return ref.watch(appSettingsProvider).useDynamicColor;
});

/// Current grid size.
final settingsGridSizeProvider = Provider<GridSize>((ref) {
  return ref.watch(appSettingsProvider).gridSize;
});

/// Whether compact mode is enabled.
final settingsCompactModeProvider = Provider<bool>((ref) {
  return ref.watch(appSettingsProvider).compactMode;
});

/// Whether animations are enabled.
final settingsAnimationsProvider = Provider<bool>((ref) {
  return ref.watch(appSettingsProvider).animationsEnabled;
});

/// Whether privacy lock is enabled (biometric or PIN).
final settingsPrivacyLockProvider = Provider<bool>((ref) {
  final s = ref.watch(appSettingsProvider);
  return s.biometricLockEnabled || s.pinLockEnabled;
});

/// Whether onboarding is completed.
final settingsOnboardingCompletedProvider = Provider<bool>((ref) {
  return ref.watch(appSettingsProvider).onboardingCompleted;
});
