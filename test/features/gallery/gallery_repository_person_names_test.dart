import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/core/database/media_item_mapper.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';
import 'package:photo_manager/photo_manager.dart';

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

MediaItem _media(String localId) => MediaItem(
  localId: localId,
  fileHash: 'h-$localId',
  filePath: '/p/$localId',
  fileName: '$localId.jpg',
  mimeType: 'image/jpeg',
  fileSize: 1,
  width: 1,
  height: 1,
  createdAt: DateTime(2026, 1, 1),
  modifiedAt: DateTime(2026, 1, 1),
  scannedAt: DateTime(2026, 1, 1),
);

void main() {
  late AppDatabase db;
  late GalleryRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = GalleryRepository(
      scannerService: _NoopScanner(),
      mediaDao: db.mediaDao,
      faceDao: db.faceDao,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'renaming a person updates person-name search without a restart',
    () async {
      // Mimic production: a scan puts the item in memory + DB (hydrate),
      // THEN a face is detected and assigned to a person.
      await repository.hydrate();
      await db.mediaDao.upsert(_media('m1').toCompanion());
      await repository.hydrate();

      final personId = await db.faceDao.createPerson('Alice');
      await db.faceDao.insertFace(
        FacesCompanion.insert(
          mediaItemId: 'm1',
          boundingBoxX: 0.1,
          boundingBoxY: 0.1,
          boundingBoxWidth: 0.2,
          boundingBoxHeight: 0.2,
          confidence: 0.9,
          personId: Value(personId),
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      // The person-names cache was loaded during hydrate(), before the face
      // existed — the People tab's assignment change calls
      // invalidatePersonNamesCache(). Await the reload deterministically: it
      // completes by firing onDataChanged, which the fix fires after the
      // async reload lands.
      var namesReloaded = Completer<void>();
      repository.onDataChanged = () {
        if (!namesReloaded.isCompleted) namesReloaded.complete();
      };
      repository.invalidatePersonNamesCache();
      await namesReloaded.future.timeout(const Duration(seconds: 5));

      // Regression guard: invalidate used to leave the cache EMPTY (nothing
      // reloaded it), so person-name search returned nothing until restart.
      expect(repository.searchMedia('alice').map((i) => i.localId), ['m1']);

      // Rename the person; the cache must follow without an app restart.
      await db.faceDao.updatePersonName(personId, 'Bob');
      namesReloaded = Completer<void>();
      repository.invalidatePersonNamesCache();
      await namesReloaded.future.timeout(const Duration(seconds: 5));

      expect(repository.searchMedia('bob').map((i) => i.localId), ['m1']);
      expect(repository.searchMedia('alice'), isEmpty);
      repository.onDataChanged = null;
    },
  );
}
