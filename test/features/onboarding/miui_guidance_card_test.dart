import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/onboarding/presentation/widgets/miui_guidance_card.dart';
import 'package:material_symbols_icons/symbols.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const settingsChannel = MethodChannel('lumo.app/settings');

  // Drive the REAL channel the card exercises through BrandSettings —
  // the old override-hook seam tested a path production never took, which
  // is how the broken url_launcher chain stayed green for months.
  void mockSettingsLaunches(bool succeed) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(settingsChannel, (_) async => succeed);
  }

  void clearMocks() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(settingsChannel, null);
  }

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MiuiGuidanceCard(packageName: 'com.lumovault.app'),
          ),
        ),
      ),
    );
  }

  tearDown(clearMocks);

  testWidgets('shows a fallback hint when every launch path fails', (
    tester,
  ) async {
    mockSettingsLaunches(false);

    await pumpCard(tester);
    await tester.tap(find.text('Open Settings').first);
    await tester.pump(); // resolve the launch future
    await tester.pump(); // snackbar entrance

    expect(find.text(kOpenSettingsFallbackHint), findsOneWidget);
  });

  testWidgets('shows no hint when the settings page opens', (tester) async {
    mockSettingsLaunches(true);

    await pumpCard(tester);
    await tester.tap(find.text('Open Settings').first);
    await tester.pump(); // resolve the launch future
    await tester.pump();

    expect(find.text(kOpenSettingsFallbackHint), findsNothing);
  });

  testWidgets('tapping a step number marks the step complete', (tester) async {
    await pumpCard(tester);

    await tester.tap(find.text('1'));
    await tester.pump();

    expect(find.byIcon(Symbols.check), findsOneWidget);
  });
}
