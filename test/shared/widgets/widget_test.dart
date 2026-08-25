import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
