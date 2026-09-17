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

  testWidgets(
    'shows map with loading indicator when no photo carries a location',
    (tester) async {
      await tester.pumpWidget(wrap(const []));
      await tester.pump();

      expect(find.text('Loading photos…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  testWidgets(
    'shows the empty state rather than crashing when no item is located',
    (tester) async {
      // Non-empty list, but nothing carries coordinates. The old code checked
      // only `photos.isEmpty`, so it reached `LatLng(p.latitude!, ...)`
      // (and points.first below) and threw during build; the filter now
      // routes this list to the empty branch instead.
      await tester.pumpWidget(wrap([_item('a'), _item('b')]));
      await tester.pump();

      expect(find.text('Loading photos…'), findsOneWidget);
    },
  );
}

MediaItem _item(String id, {double? lat, double? lng}) {
  return MediaItem(
    localId: id,
    fileHash: 'h$id',
    filePath: '/tmp/$id.jpg',
    fileName: '$id.jpg',
    mimeType: 'image/jpeg',
    fileSize: 1,
    width: 10,
    height: 10,
    status: MediaStatus.uploaded,
    createdAt: DateTime(2024, 1, 1),
    modifiedAt: DateTime(2024, 1, 1),
    scannedAt: DateTime(2024, 1, 1),
    latitude: lat,
    longitude: lng,
  );
}
