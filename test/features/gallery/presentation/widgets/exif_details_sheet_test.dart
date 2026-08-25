import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/presentation/widgets/exif_details_sheet.dart';

void main() {
  final now = DateTime(2024, 10, 24, 15, 45);

  final testItemWithLocation = MediaItem(
    localId: 'test_local_1',
    fileHash: 'hash_1',
    filePath: '/storage/emulated/0/DCIM/Camera/IMG_20241024_154500.jpg',
    fileName: 'IMG_20241024_154500.jpg',
    mimeType: 'image/jpeg',
    fileSize: 3456789,
    width: 4032,
    height: 3024,
    status: MediaStatus.uploaded,
    telegramMessageId: '12345',
    latitude: 37.7749,
    longitude: -122.4194,
    createdAt: now,
    modifiedAt: now,
    scannedAt: now,
  );

  final testItemWithoutLocation = MediaItem(
    localId: 'test_local_2',
    fileHash: 'hash_2',
    filePath: '/storage/emulated/0/DCIM/Camera/IMG_20241024_154501.jpg',
    fileName: 'IMG_20241024_154501.jpg',
    mimeType: 'image/jpeg',
    fileSize: 2000000,
    width: 1920,
    height: 1080,
    status: MediaStatus.pending,
    createdAt: now,
    modifiedAt: now,
    scannedAt: now,
  );

  testWidgets(
      'ExifDetailsSheet renders technical details, backup status and mini map',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ExifDetailsSheet(item: testItemWithLocation),
          ),
        ),
      ),
    );

    // Date and time
    expect(find.textContaining('Oct 24, 2024'), findsOneWidget);
    expect(find.textContaining('3:45 PM'), findsOneWidget);

    // File name
    expect(find.text('IMG_20241024_154500.jpg'), findsOneWidget);

    // Technical specs (Megapixels & dimensions)
    expect(find.textContaining('12.2MP'), findsOneWidget);
    expect(find.textContaining('4032 × 3024'), findsOneWidget);

    // Backup status
    expect(find.text('Backed up to Telegram'), findsOneWidget);
    expect(find.text('Message #12345'), findsOneWidget);

    // Location header & coordinates
    expect(find.text('Location'), findsOneWidget);
    expect(find.textContaining('37.7749° N'), findsOneWidget);
    expect(find.textContaining('122.4194° W'), findsOneWidget);
  });

  testWidgets('ExifDetailsSheet renders Add location when no coordinates',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ExifDetailsSheet(item: testItemWithoutLocation),
          ),
        ),
      ),
    );

    expect(find.text('Add location'), findsOneWidget);
    expect(find.text('Pin where this photo was taken'), findsOneWidget);
    expect(find.text('Stored on this device'), findsOneWidget);
  });
}
