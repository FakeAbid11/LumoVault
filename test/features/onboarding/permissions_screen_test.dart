import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lumovault/core/di/providers.dart';
import 'package:lumovault/core/permissions/permission_service.dart';
import 'package:lumovault/features/onboarding/presentation/screens/permissions_screen.dart';
import 'package:lumovault/features/onboarding/presentation/widgets/permission_card.dart';
import 'package:lumovault/shared/widgets/permission_blocked_widget.dart';

/// Mock PermissionService for testing.
class MockPermissionService implements PermissionService {
  MockPermissionService({
    this.mediaStatus = PermissionStatus.notDetermined,
    this.notificationStatus = PermissionStatus.notDetermined,
    this.batteryDisabled = false,
    this.requestMediaResult,
    this.requestNotificationResult,
    this.requestBatteryResult = true,
    this.openSettingsResult = true,
  });

  PermissionStatus mediaStatus;
  PermissionStatus notificationStatus;
  bool batteryDisabled;
  PermissionRequestResult? requestMediaResult;
  PermissionRequestResult? requestNotificationResult;
  bool requestBatteryResult;
  bool openSettingsResult;

  @override
  Future<PermissionStatus> checkMediaPermissionStatus() async => mediaStatus;

  @override
  Future<PermissionStatus> checkNotificationPermissionStatus() async =>
      notificationStatus;

  @override
  Future<bool> isBatteryOptimizationDisabled() async => batteryDisabled;

  @override
  Future<PermissionRequestResult> requestMediaPermission() async {
    return requestMediaResult ??
        PermissionRequestResult(
          status: PermissionStatus.granted,
          previousStatus: mediaStatus,
        );
  }

  @override
  Future<PermissionRequestResult> requestNotificationPermission() async {
    return requestNotificationResult ??
        PermissionRequestResult(
          status: PermissionStatus.granted,
          previousStatus: notificationStatus,
        );
  }

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async =>
      requestBatteryResult;

  @override
  Future<bool> openAppSettings() async => openSettingsResult;

  @override
  Future<bool> areAllCriticalPermissionsGranted() async =>
      mediaStatus == PermissionStatus.granted ||
      mediaStatus == PermissionStatus.limited;

  @override
  Stream<void> get onPermissionsChanged => const Stream.empty();
}

void main() {
  group('PermissionCard', () {
    testWidgets('shows grant button when status is denied', (tester) async {
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

    testWidgets('shows check icon when status is granted', (tester) async {
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

    testWidgets('shows Open Settings when permanently denied', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermissionCard(
              icon: Icons.photo_library,
              title: 'Storage',
              description: 'Access photos',
              status: PermissionStatus.permanentlyDenied,
              onGrant: () {},
              onOpenSettings: () {},
            ),
          ),
        ),
      );

      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows Manage Access when limited', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermissionCard(
              icon: Icons.photo_library,
              title: 'Storage',
              description: 'Access photos',
              status: PermissionStatus.limited,
              onGrant: () {},
              onManageLimited: () {},
            ),
          ),
        ),
      );

      expect(find.text('Manage Access'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('simple factory creates correct states', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermissionCard.simple(
              icon: Icons.photo_library,
              title: 'Storage',
              description: 'Access photos',
              isGranted: true,
              onGrant: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });

  group('PermissionsScreen', () {
    late MockPermissionService mockService;

    setUp(() {
      mockService = MockPermissionService();
    });

    Widget buildScreen() {
      return ProviderScope(
        overrides: [permissionServiceProvider.overrideWithValue(mockService)],
        child: const MaterialApp(home: PermissionsScreen()),
      );
    }

    testWidgets('shows loading indicator initially', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows permission cards after loading', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(PermissionCard), findsAtLeast(2));
    });

    testWidgets('shows correct permission titles', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Storage Access'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('continue button is disabled when media permission denied', (
      tester,
    ) async {
      mockService = MockPermissionService(mediaStatus: PermissionStatus.denied);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      final button = tester.widget<FilledButton>(continueButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('continue button is enabled when media permission granted', (
      tester,
    ) async {
      mockService = MockPermissionService(
        mediaStatus: PermissionStatus.granted,
      );

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      final button = tester.widget<FilledButton>(continueButton);
      expect(button.onPressed, isNotNull);
    });

    testWidgets('continue button is enabled when media permission limited', (
      tester,
    ) async {
      mockService = MockPermissionService(
        mediaStatus: PermissionStatus.limited,
      );

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      final button = tester.widget<FilledButton>(continueButton);
      expect(button.onPressed, isNotNull);
    });

    testWidgets('skip button is visible', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('back button is visible', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('shows explanation text', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(
        find.text(
          'LumoVault needs access to your photos and videos to back them up.',
        ),
        findsOneWidget,
      );
    });
  });

  group('PermissionBlockedWidget', () {
    testWidgets('shows grant button when denied', (tester) async {
      bool grantPressed = false;
      bool settingsPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermissionBlockedWidget(
              status: PermissionStatus.denied,
              onGrantPressed: () => grantPressed = true,
              onSettingsPressed: () => settingsPressed = true,
            ),
          ),
        ),
      );

      expect(find.text('Grant Permission'), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);

      await tester.tap(find.text('Grant Permission'));
      expect(grantPressed, isTrue);
      expect(settingsPressed, isFalse);
    });

    testWidgets('shows settings button when permanently denied', (
      tester,
    ) async {
      bool grantPressed = false;
      bool settingsPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermissionBlockedWidget(
              status: PermissionStatus.permanentlyDenied,
              onGrantPressed: () => grantPressed = true,
              onSettingsPressed: () => settingsPressed = true,
            ),
          ),
        ),
      );

      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Grant Permission'), findsNothing);

      await tester.tap(find.text('Open Settings'));
      expect(settingsPressed, isTrue);
      expect(grantPressed, isFalse);
    });

    testWidgets('shows custom title and icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermissionBlockedWidget(
              status: PermissionStatus.denied,
              onGrantPressed: () {},
              onSettingsPressed: () {},
              icon: Icons.videocam,
              title: 'Camera access required',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.videocam), findsOneWidget);
      expect(find.text('Camera access required'), findsOneWidget);
    });
  });
}
