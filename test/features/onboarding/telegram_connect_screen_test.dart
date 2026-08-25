import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import 'package:lumovault/core/auth/auth_service.dart';
import 'package:lumovault/core/di/backup_providers.dart';
import 'package:lumovault/core/di/tdlib_providers.dart';
import 'package:lumovault/features/restore/presentation/providers/restore_providers.dart';
import 'package:lumovault/features/settings/data/repositories/settings_repository.dart';
import 'package:lumovault/features/settings/presentation/providers/settings_providers.dart';

import '../../helpers/fake_backup_engine.dart';
import '../../helpers/stub_auth_service.dart';
import 'package:lumovault/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:lumovault/features/onboarding/presentation/screens/telegram_connect_screen.dart';

void main() {
  Widget buildScreen({
    required AuthService authService,
    bool onboardingCompleted = false,
  }) {
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        onboardingCompletedProvider.overrideWith((ref) => onboardingCompleted),
      ],
      child: const MaterialApp(home: TelegramConnectScreen()),
    );
  }

  Widget buildScreenWithGoRouter({
    required AuthService authService,
    bool onboardingCompleted = false,
  }) {
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        onboardingCompletedProvider.overrideWith((ref) => onboardingCompleted),
        // _onAuthSuccess() reads these before navigating; their real
        // implementations need TDLib/plugins and never resolve in a widget
        // test, so navigation to /local would never fire without these stubs.
        // settingsRepositoryProvider: updateField() awaits
        // flutter_secure_storage, whose method channel never completes in the
        // flutter test VM; the in-memory storage lets that await resolve so
        // _onAuthSuccess can reach context.go('/local').
        settingsRepositoryProvider.overrideWithValue(
          SettingsRepository(storage: _InMemorySecureStorage()),
        ),
        backupEngineProvider.overrideWith((ref) => FakeBackupEngineNotifier()),
        shouldShowRestoreProvider.overrideWith((ref) => false),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/onboarding/telegram-connect',
          routes: [
            GoRoute(
              path: '/onboarding/telegram-connect',
              builder: (context, state) => const TelegramConnectScreen(),
            ),
            GoRoute(
              path: '/local',
              builder: (context, state) =>
                  const Scaffold(body: Center(child: Text('Local'))),
            ),
          ],
        ),
      ),
    );
  }

  group('TelegramConnectScreen', () {
    testWidgets('shows phone input initially', (tester) async {
      await tester.pumpWidget(
        buildScreen(authService: StubAuthService(simulateDelay: Duration.zero)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter your phone number'), findsOneWidget);
      expect(find.text('Send Code'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows loading when sending code', (tester) async {
      final authService = StubAuthService(simulateDelay: Duration.zero);

      await tester.pumpWidget(buildScreen(authService: authService));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Send Code'));
      await tester.enterText(find.byType(TextField), '2345678900');
      await tester.tap(find.text('Send Code'));
      await tester.pumpAndSettle();

      expect(find.text('Enter verification code'), findsOneWidget);
    });

    testWidgets('shows code input after code sent', (tester) async {
      final authService = StubAuthService(simulateDelay: Duration.zero);

      await tester.pumpWidget(buildScreen(authService: authService));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Send Code'));
      await tester.enterText(find.byType(TextField), '2345678900');
      await tester.tap(find.text('Send Code'));
      await tester.pumpAndSettle();

      expect(find.text('Enter verification code'), findsOneWidget);
      expect(find.text('Verify'), findsOneWidget);
    });

    testWidgets('shows error state on failure', (tester) async {
      final authService = StubAuthService(
        simulateDelay: Duration.zero,
        shouldFail: true,
      );

      await tester.pumpWidget(buildScreen(authService: authService));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Send Code'));
      await tester.enterText(find.byType(TextField), '2345678900');
      await tester.tap(find.text('Send Code'));
      await tester.pumpAndSettle();

      expect(find.text('Connection Error'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('Try Again resets to phone input', (tester) async {
      final authService = StubAuthService(
        simulateDelay: Duration.zero,
        shouldFail: true,
      );

      await tester.pumpWidget(buildScreen(authService: authService));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Send Code'));
      await tester.enterText(find.byType(TextField), '2345678900');
      await tester.tap(find.text('Send Code'));
      await tester.pumpAndSettle();

      expect(find.text('Connection Error'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your phone number'), findsOneWidget);
      expect(find.text('Send Code'), findsOneWidget);
    });

    testWidgets('shows 2FA password input when required', (tester) async {
      final authService = StubAuthService(
        simulateDelay: Duration.zero,
        requirePassword: true,
      );

      await tester.pumpWidget(buildScreen(authService: authService));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Send Code'));
      await tester.enterText(find.byType(TextField), '2345678900');
      await tester.tap(find.text('Send Code'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Verify'));
      await tester.enterText(find.byType(TextField), '12345');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(find.text('Two-factor authentication'), findsOneWidget);
      expect(find.text('Enter your Telegram password.'), findsOneWidget);
    });

    testWidgets('shows back button when not authenticated', (tester) async {
      await tester.pumpWidget(
        buildScreen(authService: StubAuthService(simulateDelay: Duration.zero)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('shows authenticated state with GoRouter', (tester) async {
      final authService = StubAuthService(simulateDelay: Duration.zero);

      await tester.pumpWidget(
        buildScreenWithGoRouter(authService: authService),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Send Code'));
      await tester.enterText(find.byType(TextField), '2345678900');
      await tester.tap(find.text('Send Code'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Verify'));
      await tester.enterText(find.byType(TextField), '12345');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      // After auth success, GoRouter navigates to /local
      expect(find.text('Local'), findsOneWidget);
    });

    testWidgets('wrong number link resets to phone input', (tester) async {
      final authService = StubAuthService(simulateDelay: Duration.zero);

      await tester.pumpWidget(buildScreen(authService: authService));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Send Code'));
      await tester.enterText(find.byType(TextField), '2345678900');
      await tester.tap(find.text('Send Code'));
      await tester.pumpAndSettle();

      expect(find.text('Enter verification code'), findsOneWidget);

      await tester.ensureVisible(find.text('Wrong number?'));
      await tester.tap(find.text('Wrong number?'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your phone number'), findsOneWidget);
    });

    testWidgets('shows privacy note', (tester) async {
      await tester.pumpWidget(
        buildScreen(authService: StubAuthService(simulateDelay: Duration.zero)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Your phone number is used only for Telegram authentication.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows secure backup header', (tester) async {
      await tester.pumpWidget(
        buildScreen(authService: StubAuthService(simulateDelay: Duration.zero)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Secure Backup'), findsOneWidget);
      expect(
        find.text(
          'Your photos are stored in a private channel in your own Telegram account — only you can access them.',
        ),
        findsOneWidget,
      );
    });
  });
}

/// In-memory [FlutterSecureStorage] so [SettingsRepository.updateField] resolves
/// in the flutter test VM, where the real secure-storage method channel never
/// responds. Mirrors the fake used in the settings screen tests.
class _InMemorySecureStorage implements FlutterSecureStorage {
  final Map<String, String?> _data = {};

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
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
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
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
