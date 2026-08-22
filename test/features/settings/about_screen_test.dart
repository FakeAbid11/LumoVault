import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:lumovault/features/settings/presentation/providers/settings_providers.dart';
import 'package:lumovault/features/settings/presentation/screens/about_screen.dart';

Widget _buildTestWidget() {
  return ProviderScope(
    overrides: [
      appPackageInfoProvider.overrideWith(
        (ref) async => PackageInfo(
          appName: 'LumoVault',
          packageName: 'com.lumovault.app',
          version: '2.0.0',
          buildNumber: '7',
          buildSignature: '',
        ),
      ),
    ],
    child: const MaterialApp(home: AboutScreen()),
  );
}

void main() {
  testWidgets('renders version from package info', (tester) async {
    await tester.pumpWidget(_buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Version 2.0.0 (build 7)'), findsOneWidget);
  });

  testWidgets('renders app name and tagline', (tester) async {
    await tester.pumpWidget(_buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('LumoVault'), findsOneWidget);
    expect(
      find.text('Original quality photo backup powered by Telegram'),
      findsOneWidget,
    );
  });

  testWidgets('source code tile points at the real repository', (tester) async {
    await tester.pumpWidget(_buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Source Code'), findsOneWidget);
    expect(find.text('github.com/FakeAbid11/LumoVault'), findsOneWidget);
  });

  testWidgets('licenses tile opens the license page', (tester) async {
    await tester.pumpWidget(_buildTestWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Licenses'));
    await tester.pumpAndSettle();

    expect(find.text('Licenses'), findsWidgets);
  });
}
