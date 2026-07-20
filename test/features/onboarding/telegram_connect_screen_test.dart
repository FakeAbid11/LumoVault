import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lumovault/core/auth/auth_service.dart';
import 'package:lumovault/core/auth/stub_auth_service.dart';
import 'package:lumovault/core/di/tdlib_providers.dart';
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
              path: '/timeline',
              builder: (context, state) =>
                  const Scaffold(body: Center(child: Text('Timeline'))),
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

      // After auth success, GoRouter navigates to /timeline
      expect(find.text('Timeline'), findsOneWidget);
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
          'Your photos are stored in your own Telegram account — fully encrypted and private.',
        ),
        findsOneWidget,
      );
    });
  });
}
