import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';
import 'package:photo_manager/photo_manager.dart';

/// Scanner stub that returns a fixed set of items.
class _StubScanner implements MediaScannerService {
  _StubScanner(this._items, this._folders);

  final List<MediaItem> _items;
  final List<DeviceFolder> _folders;

  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<ScanResult> scanDevice({
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
  }) async {
    return ScanResult(
      mediaItems: _items,
      folders: _folders,
      totalScanned: _items.length,
      newItems: _items.length,
      updatedItems: 0,
      duration: const Duration(milliseconds: 1),
    );
  }

  @override
  Future<List<AssetEntity>> listAllAssets({
    void Function(int loaded)? onProgress,
  }) async => [];

  @override
  Future<Uint8List?> getThumbnail(String assetId) async => null;

  @override
  Future<File?> getFullFile(String assetId) async => null;

  @override
  Future<List<DeviceFolder>> getDeviceFolders() async => _folders;
}

MediaItem _item(String localId, {bool favorite = false}) => MediaItem(
  localId: localId,
  fileHash: 'hash-$localId',
  filePath: '/p/$localId.jpg',
  fileName: '$localId.jpg',
  mimeType: 'image/jpeg',
  fileSize: 100,
  width: 10,
  height: 10,
  createdAt: DateTime(2026, 1, int.parse(localId)),
  modifiedAt: DateTime(2026, 1, 1),
  scannedAt: DateTime(2026, 1, 1),
  isFavorite: favorite,
);

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('GalleryRepository with drift persistence', () {
    test(
      'scanDevice persists items so a fresh repo can hydrate them',
      () async {
        final repo1 = GalleryRepository(
          scannerService: _StubScanner([_item('1'), _item('2')], const []),
          mediaDao: db.mediaDao,
        );
        await repo1.scanDevice();
        expect(repo1.totalCount, 2);

        // A brand-new repository over the same database should recover the set.
        final repo2 = GalleryRepository(
          scannerService: _StubScanner(const [], const []),
          mediaDao: db.mediaDao,
        );
        expect(repo2.totalCount, 0);
        await repo2.hydrate();
        expect(repo2.totalCount, 2);
        expect(repo2.getTimelineItems().map((i) => i.localId).toSet(), {
          '1',
          '2',
        });
      },
    );

    test('toggleFavorite is written through and survives rehydrate', () async {
      final repo1 = GalleryRepository(
        scannerService: _StubScanner([_item('1')], const []),
        mediaDao: db.mediaDao,
      );
      await repo1.scanDevice();
      await repo1.toggleFavorite('1');

      final repo2 = GalleryRepository(
        scannerService: _StubScanner(const [], const []),
        mediaDao: db.mediaDao,
      );
      await repo2.hydrate();
      expect(repo2.getItemById('1')?.isFavorite, isTrue);
    });

    test(
      'moveToTrash then restoreFromTrash clears trashedAt in the database',
      () async {
        final repo1 = GalleryRepository(
          scannerService: _StubScanner([_item('1')], const []),
          mediaDao: db.mediaDao,
        );
        await repo1.scanDevice();
        await repo1.moveToTrash('1');
        await repo1.restoreFromTrash('1');

        final repo2 = GalleryRepository(
          scannerService: _StubScanner(const [], const []),
          mediaDao: db.mediaDao,
        );
        await repo2.hydrate();
        final restored = repo2.getItemById('1');
        expect(restored?.isTrashed, isFalse);
        expect(restored?.trashedAt, isNull);
      },
    );

    test('scanDevice replaces the previous persisted set', () async {
      final repo1 = GalleryRepository(
        scannerService: _StubScanner([_item('1'), _item('2')], const []),
        mediaDao: db.mediaDao,
      );
      await repo1.scanDevice();

      // Second scan returns a different set; the DB should mirror it, not
      // accumulate.
      final repo2 = GalleryRepository(
        scannerService: _StubScanner([_item('3')], const []),
        mediaDao: db.mediaDao,
      );
      await repo2.scanDevice();

      final repo3 = GalleryRepository(
        scannerService: _StubScanner(const [], const []),
        mediaDao: db.mediaDao,
      );
      await repo3.hydrate();
      expect(repo3.getTimelineItems().map((i) => i.localId).toSet(), {'3'});
    });
  });
}
