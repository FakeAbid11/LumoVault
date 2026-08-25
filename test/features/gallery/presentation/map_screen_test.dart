import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumovault/core/di/gallery_providers.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/presentation/screens/map_screen.dart';

void main() {
  Widget wrap(List<MediaItem> photos) {
    return ProviderScope(
      overrides: [mapPhotosProvider.overrideWith((ref) async => photos)],
      child: const MaterialApp(home: MapScreen()),
    );
  }

  testWidgets('shows empty state when no photo carries a location', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const []));
    await tester.pumpAndSettle();

    expect(find.text('No photos with location yet'), findsOneWidget);
    expect(find.byIcon(Icons.location_off_outlined), findsOneWidget);
  });
}
