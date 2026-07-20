import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lumovault/shared/widgets/app_shell.dart';

void main() {
  group('AppShell', () {
    late StatefulNavigationShell navigationShell;

    Widget buildTestWidget({double width = 400}) {
      final router = GoRouter(
        initialLocation: '/timeline',
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
                    path: '/albums',
                    builder: (_, __) => const Scaffold(
                      body: Center(child: Text('Albums Content')),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/favorites',
                    builder: (_, __) => const Scaffold(
                      body: Center(child: Text('Favorites Content')),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/settings',
                    builder: (_, __) => const Scaffold(
                      body: Center(child: Text('Settings Content')),
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
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Favorites'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
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

      expect(find.text('Timeline Content'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.photo_library_outlined));
      await tester.pumpAndSettle();

      expect(navigationShell.currentIndex, equals(1));
      expect(find.text('Albums Content'), findsOneWidget);
    });

    testWidgets('displays correct tab content on settings tap', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget(width: 400));
      await tester.pumpAndSettle();

      expect(find.text('Timeline Content'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(navigationShell.currentIndex, equals(3));
      expect(find.text('Settings Content'), findsOneWidget);
    });
  });
}
