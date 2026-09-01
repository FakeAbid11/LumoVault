import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/device/brand_settings.dart';
import 'package:lumovault/features/onboarding/presentation/widgets/miui_guidance_card.dart';
import 'package:material_symbols_icons/symbols.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetBrandSettingsOverrides);
  tearDown(resetBrandSettingsOverrides);

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

  testWidgets('shows a fallback hint when every launch path fails', (
    tester,
  ) async {
    nativeAutostartOverride = () async => false;
    openAppInfoOverride = () => throw Exception('no settings activity');

    await pumpCard(tester);
    await tester.tap(find.text('Open Settings').first);
    await tester.pump(); // resolve the launch future
    await tester.pump(); // snackbar entrance

    expect(find.text(kOpenSettingsFallbackHint), findsOneWidget);
  });

  testWidgets('shows no hint when the settings page opens', (tester) async {
    nativeAutostartOverride = () async => true;

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
