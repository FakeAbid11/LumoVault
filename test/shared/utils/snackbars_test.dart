import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumovault/shared/utils/snackbars.dart';

void main() {
  Future<void> pumpAndShow(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showLumoSnackBar(context, 'Done'),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
  }

  testWidgets('anchors above the floating nav capsule on phone surfaces', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpAndShow(tester);

    final snackbar = tester.widget<SnackBar>(find.byType(SnackBar));
    final margin = snackbar.margin! as EdgeInsets;
    // Capsule zone ≈ 28 (SafeArea minimum) + 56 (NavigationBar) = 84; the
    // snackbar must clear it even when no system inset is reported.
    expect(margin.bottom, greaterThanOrEqualTo(92));
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('keeps a normal floating margin on wide (rail/drawer) surfaces', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpAndShow(tester);

    final snackbar = tester.widget<SnackBar>(find.byType(SnackBar));
    final margin = snackbar.margin! as EdgeInsets;
    // No capsule at rail/drawer widths — just the usual floating inset.
    expect(margin.bottom, 16);
  });

  testWidgets('clears the capsule zone when a system bottom inset exists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(
      bottom: 24.0,
      top: 0.0,
      left: 0.0,
      right: 0.0,
    );
    addTearDown(tester.view.reset);

    await pumpAndShow(tester);

    final snackbar = tester.widget<SnackBar>(find.byType(SnackBar));
    final margin = snackbar.margin! as EdgeInsets;
    // max(24 + 16, 92) — the capsule floor wins over the inset-based value.
    expect(margin.bottom, 92);
  });
}
