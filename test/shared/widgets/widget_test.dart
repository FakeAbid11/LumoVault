import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/shared/widgets/lumo_empty_state.dart';
import 'package:lumovault/shared/widgets/lumo_error_widget.dart';
import 'package:lumovault/shared/widgets/lumo_loading.dart';

void main() {
  group('LumoLoading', () {
    testWidgets('renders without message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LumoLoading())),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('renders with message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LumoLoading(message: 'Loading...')),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading...'), findsOneWidget);
    });
  });

  group('LumoEmptyState', () {
    testWidgets('renders title and icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LumoEmptyState(icon: Icons.photo_library, title: 'No photos'),
          ),
        ),
      );

      expect(find.byIcon(Icons.photo_library), findsOneWidget);
      expect(find.text('No photos'), findsOneWidget);
    });

    testWidgets('renders message when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LumoEmptyState(
              icon: Icons.photo_library,
              title: 'No photos',
              message: 'Start backing up your photos',
            ),
          ),
        ),
      );

      expect(find.text('Start backing up your photos'), findsOneWidget);
    });

    testWidgets('renders action button when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LumoEmptyState(
              icon: Icons.photo_library,
              title: 'No photos',
              actionLabel: 'Get Started',
              onAction: () {},
            ),
          ),
        ),
      );

      expect(find.text('Get Started'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });

  group('LumoErrorWidget', () {
    testWidgets('renders error message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LumoErrorWidget(message: 'Network error occurred'),
          ),
        ),
      );

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Network error occurred'), findsOneWidget);
    });

    testWidgets('renders retry button when onRetry provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LumoErrorWidget(
              message: 'Network error occurred',
              onRetry: () {},
            ),
          ),
        ),
      );

      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('does not render retry button without onRetry', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LumoErrorWidget(message: 'Network error occurred'),
          ),
        ),
      );

      expect(find.text('Retry'), findsNothing);
    });
  });
}
