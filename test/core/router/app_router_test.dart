import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:lumovault/core/di/gallery_providers.dart';
import 'package:lumovault/core/di/providers.dart';
import 'package:lumovault/core/permissions/permission_service.dart';
import 'package:lumovault/core/router/app_router.dart';
import 'package:lumovault/features/gallery/presentation/screens/local_screen.dart';
import 'package:lumovault/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:lumovault/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:lumovault/features/settings/data/repositories/settings_repository.dart';
import 'package:lumovault/features/settings/presentation/providers/settings_providers.dart';
import 'package:lumovault/features/settings/presentation/screens/settings_screen.dart';

/// Permission service that reports everything as granted so the real
/// `LocalScreen` can be rendered without platform channels.
class _GrantedPermissionService implements PermissionService {
  @override
  Future<PermissionStatus> checkMediaPermissionStatus() async =>
      PermissionStatus.granted;
  @override
  Future<PermissionStatus> checkNotificationPermissionStatus() async =>
      PermissionStatus.granted;
  @override
  Future<bool> isBatteryOptimizationDisabled() async => true;
  @override
  Future<PermissionRequestResult> requestMediaPermission() async =>
      const PermissionRequestResult(
        status: PermissionStatus.granted,
        previousStatus: PermissionStatus.granted,
      );
  @override
  Future<PermissionRequestResult> requestNotificationPermission() async =>
      const PermissionRequestResult(
        status: PermissionStatus.granted,
        previousStatus: PermissionStatus.granted,
      );
  @override
  Future<bool> requestIgnoreBatteryOptimizations() async => true;
  @override
  Future<bool> openAppSettings() async => true;
  @override
  Future<bool> areAllCriticalPermissionsGranted() async => true;
  @override
  Stream<void> get onPermissionsChanged => const Stream.empty();
}

/// Secure-storage stand-in so the real settings repository can load
/// (SettingsScreen reads appSettingsProvider, which persists through it).
class _InMemorySecureStorage implements FlutterSecureStorage {
  final Map<String, String?> _data = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data[key];

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
    _data[key] = value;
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
    _data.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

ProviderContainer _container({bool onboardingCompleted = false}) {
  return ProviderContainer(
    overrides: [
      permissionServiceProvider.overrideWithValue(_GrantedPermissionService()),
      deviceAssetsProvider.overrideWith((_) async => <AssetEntity>[]),
      settingsRepositoryProvider.overrideWithValue(
        SettingsRepository(storage: _InMemorySecureStorage()),
      ),
      if (onboardingCompleted)
        onboardingCompletedProvider.overrideWith((_) => true),
    ],
  );
}

Widget _buildApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: container.read(routerProvider)),
  );
}

void main() {
  group('routerProvider', () {
    test('keeps a single stable router instance across onboarding changes', () {
      final container = _container();
      addTearDown(container.dispose);

      final first = container.read(routerProvider);
      container.read(onboardingCompletedProvider.notifier).state = true;
      final second = container.read(routerProvider);

      expect(identical(first, second), isTrue);
    });

    testWidgets('starts on welcome when onboarding is incomplete', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(
        container.read(routerProvider).state.uri.path,
        '/onboarding/welcome',
      );
    });

    testWidgets(
      'redirects app routes to welcome when onboarding is incomplete',
      (tester) async {
        final container = _container();
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildApp(container));
        await tester.pumpAndSettle();

        container.read(routerProvider).go('/settings');
        await tester.pumpAndSettle();

        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(
          container.read(routerProvider).state.uri.path,
          '/onboarding/welcome',
        );
      },
    );

    testWidgets('lands on /local once onboarding completes', (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);

      container.read(onboardingCompletedProvider.notifier).state = true;
      await tester.pumpAndSettle();

      expect(find.byType(LocalScreen), findsOneWidget);
      expect(find.text('No photos found'), findsOneWidget);
      expect(container.read(routerProvider).state.uri.path, '/local');
    });

    testWidgets('starts on /local when onboarding is already complete', (
      tester,
    ) async {
      final container = _container(onboardingCompleted: true);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      expect(find.byType(LocalScreen), findsOneWidget);
      expect(container.read(routerProvider).state.uri.path, '/local');
    });

    testWidgets('opens Settings from the top-right gear as a pushed page', (
      tester,
    ) async {
      final container = _container(onboardingCompleted: true);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(container.read(routerProvider).state.uri.path, '/settings');

      // Settings is a pushed page now — back returns to the gallery.
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(LocalScreen), findsOneWidget);
      expect(container.read(routerProvider).state.uri.path, '/local');
    });

    testWidgets('the overflow menu no longer offers Settings', (tester) async {
      final container = _container(onboardingCompleted: true);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();

      expect(find.text('Restore'), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets(
      'admits the flagged telegram login route after onboarding completed',
      (tester) async {
        // Simulates a user who skipped login during onboarding coming back
        // via the Timeline tab's sign-in prompt.
        final container = _container(onboardingCompleted: true);
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildApp(container));
        await tester.pumpAndSettle();

        container.read(routerProvider).go('/onboarding/telegram?reentry=true');
        await tester.pumpAndSettle();

        expect(
          container.read(routerProvider).state.uri.path,
          '/onboarding/telegram',
        );
      },
    );

    testWidgets(
      'still redirects unflagged onboarding routes after completion',
      (tester) async {
        final container = _container(onboardingCompleted: true);
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildApp(container));
        await tester.pumpAndSettle();

        container.read(routerProvider).go('/onboarding/welcome');
        await tester.pumpAndSettle();

        expect(container.read(routerProvider).state.uri.path, '/local');
      },
    );
  });
}
