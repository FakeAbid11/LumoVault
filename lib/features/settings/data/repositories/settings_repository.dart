import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_settings.dart';

/// Repository for persisting and retrieving app settings.
///
/// Uses flutter_secure_storage for encrypted persistence.
/// Maintains an in-memory cache for fast synchronous reads.
class SettingsRepository {
  SettingsRepository({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _settingsKey = 'lumovault_settings';
  final FlutterSecureStorage _storage;
  AppSettings? _cache;
  final _changeController = StreamController<AppSettings>.broadcast();

  /// Stream of settings changes.
  Stream<AppSettings> get changes => _changeController.stream;

  /// Get current settings (from cache or storage).
  Future<AppSettings> getSettings() async {
    if (_cache != null) return _cache!;

    try {
      final json = await _storage.read(key: _settingsKey);
      if (json != null) {
        _cache = AppSettings.fromJsonString(json);
        return _cache!;
      }
    } catch (e) {
      // Fall through to defaults on storage error.
    }

    _cache = const AppSettings();
    return _cache!;
  }

  /// Get current settings synchronously (from cache only).
  AppSettings get current => _cache ?? const AppSettings();

  /// Update the full settings object.
  Future<void> updateSettings(AppSettings settings) async {
    _cache = settings;
    await _persist(settings);
    _changeController.add(settings);
  }

  /// Update a single field by applying a transform.
  Future<void> updateField(
    AppSettings Function(AppSettings current) updater,
  ) async {
    final current = await getSettings();
    final updated = updater(current);
    await updateSettings(updated);
  }

  /// Persist settings to secure storage.
  Future<void> _persist(AppSettings settings) async {
    try {
      await _storage.write(key: _settingsKey, value: settings.toJsonString());
    } catch (e) {
      // Storage write failed — settings are still in memory.
    }
  }

  /// Clear all persisted settings and reset to defaults.
  Future<void> resetToDefaults() async {
    try {
      await _storage.delete(key: _settingsKey);
    } catch (e) {
      // Ignore storage errors on delete.
    }
    _cache = const AppSettings();
    _changeController.add(_cache!);
  }

  /// Check if onboarding has been completed.
  Future<bool> isOnboardingCompleted() async {
    final settings = await getSettings();
    return settings.onboardingCompleted;
  }

  /// Mark onboarding as completed.
  Future<void> completeOnboarding() async {
    await updateField((s) => s.copyWith(onboardingCompleted: true));
  }

  /// Persist the resolved backup storage channel id, so restarts reuse the
  /// same Telegram channel instead of creating a new one each time.
  Future<void> setStorageChannelId(int channelId) async {
    await updateField((s) => s.copyWith(storageChannelId: channelId));
  }

  void dispose() {
    _changeController.close();
  }
}
