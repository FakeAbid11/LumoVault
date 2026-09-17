import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/core/database/media_item_mapper.dart';
import 'package:lumovault/core/di/gallery_providers.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';
import 'package:lumovault/features/gallery/presentation/widgets/exif_details_sheet.dart';
import 'package:photo_manager/photo_manager.dart';

/// The sheet only needs a scanner to satisfy the repository's constructor —
/// no scan is run for these tests.
class _NoopScanner implements MediaScannerService {
  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<ScanResult> scanDevice({
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
  }) async {
    return const ScanResult(
      mediaItems: [],
      folders: [],
      totalScanned: 0,
      newItems: 0,
      updatedItems: 0,
      duration: Duration.zero,
    );
  }

  @override
  Future<List<AssetEntity>> listAllAssets({
    void Function(int loaded)? onProgress,
  }) async => const [];

  @override
  Future<Uint8List?> getThumbnail(String assetId) async => null;

  @override
  Future<File?> getFullFile(String assetId) async => null;

  @override
  Future<List<DeviceFolder>> getDeviceFolders() async => const [];

  @override
  Future<List<AssetEntity>> getFolderAssets(String pathId) async => const [];
}

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
            home: Scaffold(body: ExifDetailsSheet(item: testItemWithLocation)),
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
    },
  );

  testWidgets('ExifDetailsSheet hides location when no coordinates', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: ExifDetailsSheet(item: testItemWithoutLocation)),
        ),
      ),
    );

    expect(find.text('Add location'), findsNothing);
    expect(find.text('Pin where this photo was taken'), findsNothing);
    expect(find.text('Stored on this device'), findsOneWidget);
  });

  testWidgets('editing the date updates the sheet immediately', (tester) async {
    // The sheet reads the capture date from an immutable MediaItem snapshot,
    // so an edit that only calls setCreatedAt + an empty setState used to leave
    // the stale date on screen until the sheet was reopened.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = GalleryRepository(
      scannerService: _NoopScanner(),
      mediaDao: db.mediaDao,
      faceDao: db.faceDao,
    );
    await repository.hydrate();
    await db.mediaDao.upsert(testItemWithoutLocation.toCompanion());
    await repository.hydrate(); // pull the seeded row into the read model

    await tester.pumpWidget(
      ProviderScope(
        overrides: [galleryRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: ExifDetailsSheet(item: testItemWithoutLocation),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Pre-edit: the item's capture date.
    expect(find.textContaining('Oct 24, 2024'), findsOneWidget);

    // Date picker: keep the month, pick a different day.
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Time picker: keep 3:45 PM.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // The sheet now reflects the edited date, not the stale snapshot.
    expect(find.textContaining('Oct 15, 2024'), findsOneWidget);
    expect(find.textContaining('3:45 PM'), findsOneWidget);

    // And the edit actually reached the repository.
    expect(
      repository.getItemById('test_local_2')?.createdAt,
      DateTime(2024, 10, 15, 15, 45),
    );
  });
}
