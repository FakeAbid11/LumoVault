import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/shared/widgets/shimmer_placeholder.dart';

void main() {
  testWidgets('ShimmerPlaceholder renders with given dimensions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShimmerPlaceholder(
            width: 100,
            height: 100,
            child: Text('Loading...'),
          ),
        ),
      ),
    );

    expect(find.byType(ShimmerPlaceholder), findsOneWidget);
    expect(find.text('Loading...'), findsOneWidget);

    // Let animation cycle
    await tester.pump(const Duration(milliseconds: 500));
  });
}
