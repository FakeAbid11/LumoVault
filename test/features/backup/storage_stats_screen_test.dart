import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumovault/core/di/backup_providers.dart';
import 'package:lumovault/features/backup/engine/backup_engine.dart';
import 'package:lumovault/features/backup/presentation/screens/storage_stats_screen.dart';

void main() {
  Widget wrap(BackupStats stats) {
    return ProviderScope(
      overrides: [backupStatsProvider.overrideWithValue(stats)],
      child: const MaterialApp(home: StorageStatsScreen()),
    );
  }

  testWidgets('shows formatted backed-up bytes and empty state', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const BackupStats()));

    expect(find.text('0 B'), findsOneWidget);
    expect(find.text('No items backed up yet'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('Backed Up'), findsOneWidget);
  });

  testWidgets('shows backed-up size, counts, and last backup time', (
    tester,
  ) async {
    final stats = BackupStats(
      totalMediaItems: 120,
      backedUpCount: 80,
      pendingCount: 35,
      failedCount: 5,
      totalBytes: 10 * 1024 * 1024,
      backedUpBytes: 5 * 1024 * 1024,
      lastBackupAt: DateTime(2026, 7, 14, 9, 30),
    );

    await tester.pumpWidget(wrap(stats));

    expect(find.text('5.0 MB'), findsOneWidget);
    expect(find.text('80 of 120 items backed up'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(find.text('35'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.textContaining('Last backup:'), findsOneWidget);
  });

  testWidgets('shows 1 KB formatting for small backups', (tester) async {
    const stats = BackupStats(backedUpCount: 1, backedUpBytes: 2048);

    await tester.pumpWidget(wrap(stats));

    expect(find.text('2.0 KB'), findsOneWidget);
  });
}
