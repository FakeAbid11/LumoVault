import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumovault/core/di/gallery_providers.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/presentation/screens/map_screen.dart';

void main() {
  Widget wrap(List<MediaItem> photos) {
    return ProviderScope(
      overrides: [
        mapPhotosProvider.overrideWith((ref) => Stream.value(photos)),
      ],
      child: const MaterialApp(home: MapScreen()),
    );
  }

  testWidgets('shows map with loading indicator when no photo carries a location', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const []));
    await tester.pump();

    expect(find.text('Loading photos…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
