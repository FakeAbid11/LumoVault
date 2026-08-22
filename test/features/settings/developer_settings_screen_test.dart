import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:lumovault/features/metadata/data/repositories/conflict_resolver.dart';
import 'package:lumovault/features/metadata/data/repositories/manifest_service.dart';
import 'package:lumovault/features/metadata/data/repositories/metadata_repository.dart'
    show MetadataRepository, MetadataSyncStatus;
import 'package:lumovault/features/metadata/data/repositories/partition_service.dart';
import 'package:lumovault/features/metadata/data/repositories/search_index_service.dart';
import 'package:lumovault/features/metadata/data/repositories/sync_service.dart';
import 'package:lumovault/features/metadata/presentation/providers/metadata_providers.dart';
import 'package:lumovault/features/settings/data/repositories/settings_repository.dart';
import 'package:lumovault/features/settings/presentation/providers/settings_providers.dart';
import 'package:lumovault/features/settings/presentation/screens/developer_settings_screen.dart';

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

/// Minimal [Ref] that hands back a memory-only [MetadataRepository] so the
/// real [MetadataSyncStatusNotifier] can attach its change listener without
/// any platform services.
class _StubRef implements Ref {
  final MetadataRepository _repo = MetadataRepository(
    manifestService: ManifestService(),
    partitionService: PartitionService(),
    searchIndexService: SearchIndexService(),
    syncService: SyncService(),
    conflictResolver: ConflictResolver(),
  );

  @override
  T read<T>(ProviderListenable<T> provider) => _repo as T;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSyncNotifier extends MetadataSyncStatusNotifier {
  _FakeSyncNotifier() : super(_StubRef()) {
    state = const MetadataSyncStatus(
      pendingChangesCount: 7,
      syncInProgress: true,
    );
  }
}

Widget _buildTestWidget() {
  return ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(
        SettingsRepository(storage: _InMemorySecureStorage()),
      ),
      appPackageInfoProvider.overrideWith(
        (ref) async => PackageInfo(
          appName: 'LumoVault',
          packageName: 'com.lumovault.app',
          version: '2.0.0',
          buildNumber: '7',
          buildSignature: '',
        ),
      ),
      metadataSyncStatusProvider.overrideWith((ref) => _FakeSyncNotifier()),
    ],
    child: const MaterialApp(home: DeveloperSettingsScreen()),
  );
}

/// Tall viewport so every tile (including the Debug Mode switch at the
/// bottom) is on screen without scrolling.
void useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('renders debug info from package info and platform', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(_buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('App Version'), findsOneWidget);
    expect(find.text('2.0.0 (build 7)'), findsOneWidget);
    expect(find.text('Dart SDK'), findsOneWidget);
    expect(find.text('Database Engine'), findsOneWidget);
    expect(find.text('Drift (SQLite)'), findsOneWidget);
    expect(find.text('Schema Version'), findsOneWidget);
    expect(find.text('v4'), findsOneWidget);
  });

  testWidgets('debug mode toggle is persisted through settings', (
    tester,
  ) async {
    useTallViewport(tester);
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          SettingsRepository(storage: _InMemorySecureStorage()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DeveloperSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(appSettingsProvider).debugMode, isFalse);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(container.read(appSettingsProvider).debugMode, isTrue);
    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isTrue);
  });

  testWidgets('sync status dialog shows live provider values', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(_buildTestWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sync Status'));
    await tester.pumpAndSettle();

    expect(find.text('Last sync: Never synced'), findsOneWidget);
    expect(find.text('Pending changes: 7'), findsOneWidget);
    expect(find.text('Sync in progress: Yes'), findsOneWidget);
  });

  testWidgets('database information dialog opens', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(_buildTestWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Database Information'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Drift'), findsWidgets);
    expect(find.text('Schema version: v4'), findsOneWidget);
  });
}
