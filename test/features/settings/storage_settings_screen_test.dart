import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumovault/features/settings/presentation/providers/storage_providers.dart';
import 'package:lumovault/features/settings/presentation/screens/storage_settings_screen.dart';

void main() {
  const usage = StorageUsage(
    deviceMediaBytes: 12 * 1024 * 1024,
    deviceMediaCount: 120,
    telegramBytes: 5 * 1024 * 1024,
    telegramItemCount: 80,
    localCacheBytes: 2 * 1024 * 1024,
    thumbnailCacheBytes: 3 * 1024 * 1024,
    metadataBytes: 4096,
    databaseBytes: 1 * 1024 * 1024 * 1024,
  );

  Widget wrap() {
    return ProviderScope(
      overrides: [storageUsageProvider.overrideWith((ref) async => usage)],
      child: const MaterialApp(home: StorageSettingsScreen()),
    );
  }

  testWidgets('shows real usage values on the tiles', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Telegram Storage'), findsOneWidget);
    expect(find.text('5.0 MB'), findsOneWidget);
    expect(find.text('80 items backed up'), findsOneWidget);
    expect(find.text('Photos & Videos'), findsOneWidget);
    expect(find.text('12.0 MB'), findsOneWidget);
    expect(find.text('120 items on device'), findsOneWidget);
    expect(find.text('Local Cache'), findsOneWidget);
    expect(find.text('2.0 MB'), findsOneWidget);
    expect(find.text('Thumbnail Cache'), findsOneWidget);
    expect(find.text('3.0 MB'), findsOneWidget);
    expect(find.text('Metadata'), findsOneWidget);
    expect(find.text('4.0 KB'), findsOneWidget);
    expect(find.text('Database'), findsOneWidget);
    expect(find.text('1.0 GB'), findsOneWidget);
  });

  testWidgets('clear cache confirm dialog completes and clears', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear Cache'));
    await tester.pumpAndSettle();
    expect(find.text('Clear Cache?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Cache cleared'), findsOneWidget);
  });

  testWidgets('rebuild thumbnails confirm dialog completes', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Rebuild Thumbnails'),
      120,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('Rebuild Thumbnails'));
    await tester.pumpAndSettle();
    expect(find.text('Rebuild Thumbnails?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Rebuild'));
    await tester.pumpAndSettle();

    expect(
      find.text('Thumbnails will be rebuilt on next view'),
      findsOneWidget,
    );
  });
}
