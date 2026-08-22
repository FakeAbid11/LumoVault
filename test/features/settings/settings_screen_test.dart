import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import 'package:lumovault/features/settings/data/repositories/settings_repository.dart';
import 'package:lumovault/features/settings/presentation/providers/settings_providers.dart';
import 'package:lumovault/features/settings/presentation/screens/settings_screen.dart';

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

Widget _buildTestWidget({GoRouter? router}) {
  return ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(
        SettingsRepository(storage: _InMemorySecureStorage()),
      ),
    ],
    child: MaterialApp.router(
      routerConfig:
          router ??
          GoRouter(
            initialLocation: '/settings',
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, __) => const SettingsScreen(),
              ),
              GoRoute(
                path: '/settings/:section',
                builder: (_, state) => Scaffold(
                  body: Text('Section: ${state.pathParameters['section']}'),
                ),
              ),
            ],
          ),
    ),
  );
}

void main() {
  group('SettingsScreen', () {
    testWidgets('renders section headers and top tiles', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      // Visible section headers (top of list)
      expect(find.text('Account'), findsNWidgets(2));
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Backup'), findsOneWidget);
    });

    testWidgets('renders Settings title in app bar', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('auto backup toggle renders with default on', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      final switchWidget = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile).first,
      );
      expect(switchWidget.value, isTrue);
    });

    testWidgets('wifi only toggle renders with default on', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      final switchWidget = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile).at(1),
      );
      expect(switchWidget.value, isTrue);
    });

    testWidgets('displays English as default language', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('account ListTile navigates to /settings/account', (
      tester,
    ) async {
      final captured = <String>[];
      final router = GoRouter(
        initialLocation: '/settings',
        routes: [
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/settings/:section',
            builder: (context, state) {
              captured.add(state.matchedLocation);
              return Scaffold(
                body: Text('Section: ${state.pathParameters['section']}'),
              );
            },
          ),
        ],
      );

      await tester.pumpWidget(_buildTestWidget(router: router));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();

      expect(captured, contains('/settings/account'));
    });

    testWidgets('settings list is scrollable', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      // Verify the ListView is present
      expect(find.byType(ListView), findsOneWidget);

      // Verify all major sections are present by checking key tiles
      expect(find.text('Auto Backup'), findsOneWidget);
      expect(find.text('Wi-Fi Only'), findsOneWidget);
    });
  });
}
