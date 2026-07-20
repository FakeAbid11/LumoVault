import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/error_handling/error_boundary.dart';

void main() {
  group('ErrorBoundary', () {
    testWidgets('renders child when no error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ErrorBoundary(child: Text('Hello'))),
      );

      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('shows error UI when showError is called', (tester) async {
      final key = GlobalKey<State<ErrorBoundary>>();

      await tester.pumpWidget(
        MaterialApp(
          home: ErrorBoundary(key: key, child: const Text('Hello')),
        ),
      );

      expect(find.text('Hello'), findsOneWidget);

      // Manually trigger error state.
      (key.currentState! as dynamic).showError(Exception('test error'));
      await tester.pump();

      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('calls onError when showError is called', (tester) async {
      Object? capturedError;
      final key = GlobalKey<State<ErrorBoundary>>();

      await tester.pumpWidget(
        MaterialApp(
          home: ErrorBoundary(
            key: key,
            onError: (error, stack) {
              capturedError = error;
            },
            child: const Text('Hello'),
          ),
        ),
      );

      final testError = Exception('captured error');
      (key.currentState! as dynamic).showError(testError);
      await tester.pump();

      expect(capturedError, equals(testError));
    });

    testWidgets('clearError restores child', (tester) async {
      final key = GlobalKey<State<ErrorBoundary>>();

      await tester.pumpWidget(
        MaterialApp(
          home: ErrorBoundary(key: key, child: const Text('Hello')),
        ),
      );

      // Show error.
      (key.currentState! as dynamic).showError(Exception('error'));
      await tester.pump();
      expect(find.text('Something went wrong'), findsOneWidget);

      // Clear error.
      (key.currentState! as dynamic).clearError();
      await tester.pump();
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('uses custom fallback builder when provided', (tester) async {
      final key = GlobalKey<State<ErrorBoundary>>();

      await tester.pumpWidget(
        MaterialApp(
          home: ErrorBoundary(
            key: key,
            fallbackBuilder: (context, error) {
              return const Scaffold(body: Text('Custom Error UI'));
            },
            child: const Text('Hello'),
          ),
        ),
      );

      (key.currentState! as dynamic).showError(Exception('custom'));
      await tester.pump();

      expect(find.text('Custom Error UI'), findsOneWidget);
    });

    testWidgets('default error UI has Try Again button', (tester) async {
      final key = GlobalKey<State<ErrorBoundary>>();

      await tester.pumpWidget(
        MaterialApp(
          home: ErrorBoundary(key: key, child: const Text('Hello')),
        ),
      );

      (key.currentState! as dynamic).showError(Exception('error'));
      await tester.pump();

      expect(find.text('Try Again'), findsOneWidget);
    });
  });
}
