import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:lumovault/features/settings/data/models/app_settings.dart';
import 'package:lumovault/features/settings/data/repositories/settings_repository.dart';

/// In-memory mock of FlutterSecureStorage for testing.
/// Uses noSuchMethod to handle any unimplemented members gracefully.
class _MockFlutterSecureStorage implements FlutterSecureStorage {
  final Map<String, String?> _store = {};

  @override
  Future<void> write({
    required String key,
    String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _store[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    // Handle any unimplemented members by returning sensible defaults.
    return null;
  }
}

void main() {
  late _MockFlutterSecureStorage mockStorage;
  late SettingsRepository repository;

  setUp(() {
    mockStorage = _MockFlutterSecureStorage();
    repository = SettingsRepository(storage: mockStorage);
  });

  tearDown(() {
    repository.dispose();
  });

  group('getSettings', () {
    test('returns defaults when no persisted data', () async {
      final settings = await repository.getSettings();

      expect(settings, equals(const AppSettings()));
    });

    test('returns cached settings on subsequent calls', () async {
      final first = await repository.getSettings();
      final second = await repository.getSettings();

      expect(identical(first, second), isTrue);
    });

    test('loads persisted settings from storage', () async {
      const custom = AppSettings(languageCode: 'es', autoBackupEnabled: false);
      await mockStorage.write(
        key: 'lumovault_settings',
        value: custom.toJsonString(),
      );

      final settings = await repository.getSettings();

      expect(settings.languageCode, 'es');
      expect(settings.autoBackupEnabled, false);
    });
  });

  group('updateSettings', () {
    test('persists and caches settings', () async {
      const custom = AppSettings(maxParallelUploads: 8);
      await repository.updateSettings(custom);

      final stored = await repository.getSettings();
      expect(stored.maxParallelUploads, 8);

      // Should also persist to storage
      final raw = await mockStorage.read(key: 'lumovault_settings');
      expect(raw, isNotNull);
    });

    test('emits on changes stream', () async {
      final emitted = <AppSettings>[];
      repository.changes.listen(emitted.add);

      const custom = AppSettings(wifiOnly: false);
      await repository.updateSettings(custom);

      // Allow stream to deliver
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(1));
      expect(emitted.first.wifiOnly, false);
    });
  });

  group('updateField', () {
    test('applies transform to current settings', () async {
      await repository.updateField((s) => s.copyWith(maxParallelUploads: 10));

      final settings = await repository.getSettings();
      expect(settings.maxParallelUploads, 10);
    });

    test('preserves other fields', () async {
      const initial = AppSettings(languageCode: 'fr', maxParallelUploads: 2);
      await repository.updateSettings(initial);

      await repository.updateField((s) => s.copyWith(maxParallelUploads: 8));

      final settings = await repository.getSettings();
      expect(settings.languageCode, 'fr');
      expect(settings.maxParallelUploads, 8);
    });
  });

  group('resetToDefaults', () {
    test('clears storage and resets to defaults', () async {
      const custom = AppSettings(
        languageCode: 'es',
        autoBackupEnabled: false,
        maxParallelUploads: 10,
      );
      await repository.updateSettings(custom);

      await repository.resetToDefaults();

      final settings = await repository.getSettings();
      expect(settings, equals(const AppSettings()));

      // Storage should be cleared
      final raw = await mockStorage.read(key: 'lumovault_settings');
      expect(raw, isNull);
    });

    test('emits defaults on changes stream', () async {
      final emitted = <AppSettings>[];
      repository.changes.listen(emitted.add);

      await repository.updateField((s) => s.copyWith(autoBackupEnabled: false));
      await repository.resetToDefaults();

      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(2));
      expect(emitted.last, equals(const AppSettings()));
    });
  });

  group('onboarding', () {
    test('isOnboardingCompleted returns false by default', () async {
      final completed = await repository.isOnboardingCompleted();
      expect(completed, isFalse);
    });

    test('completeOnboarding marks onboarding as completed', () async {
      await repository.completeOnboarding();

      final completed = await repository.isOnboardingCompleted();
      expect(completed, isTrue);
    });

    test('completeOnboarding preserves other settings', () async {
      await repository.updateField((s) => s.copyWith(maxParallelUploads: 7));
      await repository.completeOnboarding();

      final settings = await repository.getSettings();
      expect(settings.onboardingCompleted, isTrue);
      expect(settings.maxParallelUploads, 7);
    });
  });

  group('setStorageChannelId', () {
    test('persists storage channel id', () async {
      await repository.setStorageChannelId(12345);

      final settings = await repository.getSettings();
      expect(settings.storageChannelId, 12345);
    });

    test('preserves other settings', () async {
      await repository.updateField((s) => s.copyWith(languageCode: 'de'));
      await repository.setStorageChannelId(99999);

      final settings = await repository.getSettings();
      expect(settings.languageCode, 'de');
      expect(settings.storageChannelId, 99999);
    });
  });

  group('current', () {
    test('returns defaults before first getSettings', () {
      final current = repository.current;
      expect(current, equals(const AppSettings()));
    });

    test('returns cached value after updateSettings', () async {
      await repository.updateSettings(const AppSettings(wifiOnly: false));

      expect(repository.current.wifiOnly, false);
    });
  });

  group('error handling', () {
    test('getSettings returns defaults when storage read fails', () async {
      // Create a repository with a storage that throws
      final repo = SettingsRepository(storage: _ThrowingStorage());

      final settings = await repo.getSettings();
      expect(settings, equals(const AppSettings()));
      repo.dispose();
    });

    test('updateSettings does not throw on storage write failure', () async {
      final repo = SettingsRepository(storage: _ThrowingStorage());

      // Should not throw
      await repo.updateSettings(const AppSettings(wifiOnly: false));
      expect(repo.current.wifiOnly, false);
      repo.dispose();
    });
  });

  group('errors stream', () {
    test('emits on failed read', () async {
      final repo = SettingsRepository(storage: _ThrowingStorage());
      final errors = <Object>[];
      repo.errors.listen(errors.add);

      await repo.getSettings();
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      repo.dispose();
    });

    test('emits on failed write', () async {
      final repo = SettingsRepository(storage: _ThrowingStorage());
      final errors = <Object>[];
      repo.errors.listen(errors.add);

      // _persist swallows, but the failure must surface on the errors stream.
      await repo.updateSettings(const AppSettings(wifiOnly: false));
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      repo.dispose();
    });

    test('emits on failed delete during resetToDefaults', () async {
      final repo = SettingsRepository(storage: _ThrowingStorage());
      final errors = <Object>[];
      repo.errors.listen(errors.add);

      await repo.resetToDefaults();
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(repo.current, equals(const AppSettings()));
      repo.dispose();
    });

    test('does not emit on successful operations', () async {
      final errors = <Object>[];
      repository.errors.listen(errors.add);

      await repository.getSettings();
      await repository.updateSettings(const AppSettings(wifiOnly: false));
      await repository.resetToDefaults();
      await Future<void>.delayed(Duration.zero);

      expect(errors, isEmpty);
    });
  });
}

/// Storage that throws on every operation.
class _ThrowingStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw Exception('Storage failure');
  }
}
