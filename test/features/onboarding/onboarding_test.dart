import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:lumovault/core/auth/auth_service.dart';
import 'package:lumovault/core/auth/stub_auth_service.dart';
import 'package:lumovault/core/di/providers.dart';
import 'package:lumovault/core/permissions/permission_service.dart';
import 'package:lumovault/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:lumovault/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:lumovault/features/onboarding/presentation/screens/permissions_screen.dart';
import 'package:lumovault/features/onboarding/presentation/screens/folder_selection_screen.dart';
import 'package:lumovault/features/onboarding/presentation/screens/telegram_connect_screen.dart';
import 'package:lumovault/features/onboarding/presentation/widgets/feature_card.dart';
import 'package:lumovault/features/onboarding/presentation/widgets/permission_card.dart';
import 'package:lumovault/features/onboarding/presentation/widgets/onboarding_progress_indicator.dart';

/// Simple mock PermissionService for onboarding screen tests.
class _MockPermissionService implements PermissionService {
  @override
  Future<PermissionStatus> checkMediaPermissionStatus() async =>
      PermissionStatus.notDetermined;
  @override
  Future<PermissionStatus> checkNotificationPermissionStatus() async =>
      PermissionStatus.notDetermined;
  @override
  Future<bool> isBatteryOptimizationDisabled() async => false;
  @override
  Future<PermissionRequestResult> requestMediaPermission() async =>
      const PermissionRequestResult(
        status: PermissionStatus.granted,
        previousStatus: PermissionStatus.notDetermined,
      );
  @override
  Future<PermissionRequestResult> requestNotificationPermission() async =>
      const PermissionRequestResult(
        status: PermissionStatus.granted,
        previousStatus: PermissionStatus.notDetermined,
      );
  @override
  Future<bool> requestIgnoreBatteryOptimizations() async => true;
  @override
  Future<bool> openAppSettings() async => true;
  @override
  Future<bool> areAllCriticalPermissionsGranted() async => false;
  @override
  Stream<void> get onPermissionsChanged => const Stream.empty();
}

void main() {
  group('OnboardingProvider', () {
    test('starts at welcome step', () {
      final notifier = OnboardingNotifier();
      expect(notifier.state.currentStep, OnboardingStep.welcome);
      expect(notifier.state.isCompleted, isFalse);
    });

    test('nextStep advances to next step', () {
      final notifier = OnboardingNotifier();
      notifier.nextStep();
      expect(notifier.state.currentStep, OnboardingStep.permissions);
    });

    test('previousStep goes back', () {
      final notifier = OnboardingNotifier();
      notifier.nextStep();
      notifier.previousStep();
      expect(notifier.state.currentStep, OnboardingStep.welcome);
    });

    test('nextStep does not go beyond last step', () {
      final notifier = OnboardingNotifier();
      for (var i = 0; i < 10; i++) {
        notifier.nextStep();
      }
      expect(notifier.state.currentStep, OnboardingStep.values.last);
    });

    test('previousStep does not go before first step', () {
      final notifier = OnboardingNotifier();
      notifier.previousStep();
      expect(notifier.state.currentStep, OnboardingStep.welcome);
    });

    test('toggleFolder adds and removes folders', () {
      final notifier = OnboardingNotifier();
      notifier.toggleFolder('/path/to/folder');
      expect(notifier.state.selectedFolders, contains('/path/to/folder'));
      notifier.toggleFolder('/path/to/folder');
      expect(notifier.state.selectedFolders, isEmpty);
    });

    test('selectAllFolders selects all', () {
      final notifier = OnboardingNotifier();
      notifier.selectAllFolders(['/a', '/b', '/c']);
      expect(notifier.state.selectedFolders.length, 3);
    });

    test('deselectAllFolders clears selection', () {
      final notifier = OnboardingNotifier();
      notifier.selectAllFolders(['/a', '/b']);
      notifier.deselectAllFolders();
      expect(notifier.state.selectedFolders, isEmpty);
    });

    test('completeOnboarding sets isCompleted', () {
      final notifier = OnboardingNotifier();
      notifier.completeOnboarding();
      expect(notifier.state.isCompleted, isTrue);
    });

    test('progress calculates correctly', () {
      final notifier = OnboardingNotifier();
      expect(notifier.state.progress, closeTo(0.2, 0.01));
      notifier.nextStep();
      expect(notifier.state.progress, closeTo(0.4, 0.01));
    });

    test('reset returns to initial state', () {
      final notifier = OnboardingNotifier();
      notifier.nextStep();
      notifier.toggleFolder('/test');
      notifier.reset();
      expect(notifier.state.currentStep, OnboardingStep.welcome);
      expect(notifier.state.selectedFolders, isEmpty);
    });
  });

  group('StubAuthService', () {
    test('initializes to unauthenticated', () async {
      final service = StubAuthService();
      await service.initialize();
      expect(service.currentState, AuthState.unauthenticated);
      service.dispose();
    });

    test('sendCode transitions to codeSent', () async {
      final service = StubAuthService();
      await service.initialize();
      final result = await service.sendCode('+1234567890');
      expect(result, isA<AuthCodeSent>());
      expect(service.currentState, AuthState.codeSent);
      service.dispose();
    });

    test(
      'verifyCode with requirePassword transitions to passwordRequired',
      () async {
        final service = StubAuthService(requirePassword: true);
        await service.initialize();
        await service.sendCode('+1234567890');
        final result = await service.verifyCode('12345');
        expect(result, isA<AuthPasswordRequired>());
        expect(service.currentState, AuthState.passwordRequired);
        service.dispose();
      },
    );

    test(
      'verifyCode without requirePassword transitions to authenticated',
      () async {
        final service = StubAuthService();
        await service.initialize();
        await service.sendCode('+1234567890');
        final result = await service.verifyCode('12345');
        expect(result, isA<AuthSuccess>());
        expect(service.currentState, AuthState.authenticated);
        service.dispose();
      },
    );

    test('submitPassword transitions to authenticated', () async {
      final service = StubAuthService(requirePassword: true);
      await service.initialize();
      await service.sendCode('+1234567890');
      await service.verifyCode('12345');
      final result = await service.submitPassword('password');
      expect(result, isA<AuthSuccess>());
      expect(service.currentState, AuthState.authenticated);
      service.dispose();
    });

    test('shouldFail returns error states', () async {
      final service = StubAuthService(shouldFail: true);
      await service.initialize();
      final result = await service.sendCode('+1234567890');
      expect(result, isA<AuthError>());
      expect(service.currentState, AuthState.error);
      service.dispose();
    });

    test('logout returns to unauthenticated', () async {
      final service = StubAuthService();
      await service.initialize();
      await service.sendCode('+1234567890');
      await service.verifyCode('12345');
      await service.logout();
      expect(service.currentState, AuthState.unauthenticated);
      service.dispose();
    });

    test('stateStream emits state changes', () async {
      final service = StubAuthService();
      await service.initialize();
      final states = <AuthState>[];
      service.stateStream.listen(states.add);

      await service.sendCode('+1234567890');
      await service.verifyCode('12345');

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(states, contains(AuthState.loading));
      expect(states, contains(AuthState.codeSent));
      expect(states, contains(AuthState.authenticated));
      service.dispose();
    });

    test('full auth flow completes successfully', () async {
      final service = StubAuthService();
      await service.initialize();

      final sendResult = await service.sendCode('+1234567890');
      expect(sendResult, isA<AuthCodeSent>());

      final verifyResult = await service.verifyCode('12345');
      expect(verifyResult, isA<AuthSuccess>());

      expect(service.currentState, AuthState.authenticated);
      service.dispose();
    });

    test('2FA flow completes successfully', () async {
      final service = StubAuthService(requirePassword: true);
      await service.initialize();

      await service.sendCode('+1234567890');
      final verifyResult = await service.verifyCode('12345');
      expect(verifyResult, isA<AuthPasswordRequired>());

      final passwordResult = await service.submitPassword('mypassword');
      expect(passwordResult, isA<AuthSuccess>());

      expect(service.currentState, AuthState.authenticated);
      service.dispose();
    });
  });

  group('FeatureCard', () {
    testWidgets('renders icon, title, and description', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FeatureCard(
              icon: Icons.cloud_upload,
              title: 'Cloud Backup',
              description: 'Back up your photos',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.cloud_upload), findsOneWidget);
      expect(find.text('Cloud Backup'), findsOneWidget);
      expect(find.text('Back up your photos'), findsOneWidget);
    });
  });

  group('PermissionCard', () {
    testWidgets('shows grant button when not granted', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermissionCard(
              icon: Icons.photo_library,
              title: 'Storage',
              description: 'Access photos',
              status: PermissionStatus.denied,
              onGrant: () {},
            ),
          ),
        ),
      );

      expect(find.text('Grant'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('shows check icon when granted', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermissionCard(
              icon: Icons.photo_library,
              title: 'Storage',
              description: 'Access photos',
              status: PermissionStatus.granted,
              onGrant: () {},
            ),
          ),
        ),
      );

      expect(find.text('Grant'), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });

  group('OnboardingProgressIndicator', () {
    testWidgets('renders correct number of dots', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OnboardingProgressIndicator(
              currentStep: OnboardingStep.welcome,
            ),
          ),
        ),
      );

      expect(find.byType(AnimatedContainer), findsNWidgets(5));
    });
  });

  group('Onboarding Screens', () {
    testWidgets('welcome screen shows app name and tagline', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: WelcomeScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('LumoVault'), findsOneWidget);
      expect(
        find.text('Your photos, your cloud, your control'),
        findsOneWidget,
      );
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('I already have an account'), findsOneWidget);
    });

    testWidgets('welcome screen has at least two feature cards', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: WelcomeScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FeatureCard), findsAtLeast(2));
    });

    testWidgets('permissions screen shows permission cards', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            permissionServiceProvider.overrideWithValue(
              _MockPermissionService(),
            ),
          ],
          child: const MaterialApp(home: PermissionsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PermissionCard), findsAtLeast(2));
    });

    testWidgets('folder selection screen shows folders', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: FolderSelectionScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Screenshots'), findsOneWidget);
      expect(find.text('Select All'), findsOneWidget);
    });

    testWidgets('telegram connect screen shows phone input', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: TelegramConnectScreen())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter your phone number'), findsOneWidget);
      expect(find.text('Send Code'), findsOneWidget);
      expect(find.text('Secure Backup'), findsOneWidget);
    });
  });

  group('First-Launch Routing', () {
    testWidgets('onboardingCompleted false shows onboarding', (tester) async {
      final router = GoRouter(
        initialLocation: '/onboarding/welcome',
        routes: [
          GoRoute(
            path: '/onboarding/welcome',
            builder: (_, __) => const WelcomeScreen(),
          ),
          GoRoute(
            path: '/timeline',
            builder: (_, __) => const Scaffold(body: Text('Timeline')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();

      expect(find.text('LumoVault'), findsOneWidget);
      router.dispose();
    });

    testWidgets('onboardingCompleted true shows main shell', (tester) async {
      final router = GoRouter(
        initialLocation: '/timeline',
        routes: [
          GoRoute(
            path: '/timeline',
            builder: (_, __) => const Scaffold(body: Text('Timeline')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Timeline'), findsOneWidget);
      router.dispose();
    });
  });
}
