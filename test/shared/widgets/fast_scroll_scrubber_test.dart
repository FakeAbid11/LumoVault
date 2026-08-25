import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/shared/widgets/fast_scroll_scrubber.dart';

void main() {
  testWidgets('FastScrollScrubber renders child and tracks vertical drag', (
    tester,
  ) async {
    final scrollController = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FastScrollScrubber(
            scrollController: scrollController,
            dateResolver: (progress) => 'August 2024',
            child: ListView.builder(
              controller: scrollController,
              itemCount: 100,
              itemBuilder: (context, index) =>
                  SizedBox(height: 50, child: Text('Item $index')),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(FastScrollScrubber), findsOneWidget);
    expect(find.text('Item 0'), findsOneWidget);

    // Drag vertically on scrubber rail (far right side)
    final rightEdge = tester.getTopRight(find.byType(FastScrollScrubber));
    final gesture = await tester.startGesture(
      rightEdge - const Offset(10, -50),
    );
    await gesture.moveBy(const Offset(0, 100));
    await tester.pumpAndSettle();

    expect(find.text('August 2024'), findsOneWidget);

    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
  });
}
