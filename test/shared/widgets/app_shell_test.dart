import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lumovault/shared/widgets/app_shell.dart';
import 'package:material_symbols_icons/symbols.dart';

void main() {
  group('AppShell', () {
    late StatefulNavigationShell navigationShell;

    Widget buildTestWidget({double width = 400}) {
      final router = GoRouter(
        initialLocation: '/local',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) {
              navigationShell = shell;
              return AppShell(navigationShell: shell);
            },
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/local',
                    builder: (_, __) => const Scaffold(
                      body: Center(child: Text('Local Content')),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/timeline',
                    builder: (_, __) => const Scaffold(
                      body: Center(child: Text('Timeline Content')),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/map',
                    builder: (_, __) => const Scaffold(
                      body: Center(child: Text('Map Content')),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/people',
                    builder: (_, __) => const Scaffold(
                      body: Center(child: Text('People Content')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      return MaterialApp.router(routerConfig: router);
    }

    testWidgets('renders bottom navigation on phone', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget(width: 400));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);
      expect(find.text('Cloud'), findsOneWidget);
      expect(find.text('Map'), findsOneWidget);
      expect(find.text('People'), findsOneWidget);
      // Settings left the bottom bar: it lives behind the top-right gear on
      // each tab's app bar (Google Photos style).
      expect(find.text('Settings'), findsNothing);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
    });

    testWidgets('renders navigation rail on tablet', (tester) async {
      tester.view.physicalSize = const Size(700, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget(width: 700));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('switches tabs when destination tapped', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget(width: 400));
      await tester.pumpAndSettle();

      expect(find.text('Local Content'), findsOneWidget);

      await tester.tap(find.byIcon(Symbols.map));
      await tester.pumpAndSettle();

      expect(navigationShell.currentIndex, equals(2));
      expect(find.text('Map Content'), findsOneWidget);
    });

    testWidgets('does not host a settings tab', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget(width: 400));
      await tester.pumpAndSettle();

      // Tapping the gear is the settings entry point, and the gear belongs
      // to the individual tab screens — not to the shell. The shell only
      // offers the four content destinations.
      expect(find.byIcon(Symbols.settings), findsNothing);
      expect(navigationShell.currentIndex, equals(0));
    });

    testWidgets('displays correct tab content on people tap', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget(width: 400));
      await tester.pumpAndSettle();

      expect(find.text('Local Content'), findsOneWidget);

      await tester.tap(find.byIcon(Symbols.people));
      await tester.pumpAndSettle();

      expect(navigationShell.currentIndex, equals(3));
      expect(find.text('People Content'), findsOneWidget);
    });
  });
}
