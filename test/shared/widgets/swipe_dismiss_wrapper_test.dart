import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/shared/widgets/swipe_dismiss_wrapper.dart';

void main() {
  testWidgets(
    'SwipeDismissWrapper triggers onDismissed when dragged down past threshold',
    (tester) async {
      bool dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeDismissWrapper(
              onDismissed: () => dismissed = true,
              child: const Center(child: Text('Viewer Content')),
            ),
          ),
        ),
      );

      expect(find.text('Viewer Content'), findsOneWidget);

      // Drag down
      final center = tester.getCenter(find.text('Viewer Content'));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(0, 200));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    },
  );
}
