import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/incremental_scanner.dart';
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

/// Incremental scanner stub that returns a canned result instead of talking
/// to photo_manager, so the repository's merge/persist path is testable.
class _FakeIncrementalScanner extends IncrementalScanner {
  _FakeIncrementalScanner(this.result);

  final IncrementalScanResult result;

  @override
  Future<IncrementalScanResult> scanForChanges({
    required Map<String, MediaItem> lastKnownItems,
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
    void Function(List<MediaItem> newItems, List<MediaItem> updatedItems)?
    onBatch,
  }) async {
    onBatch?.call(result.newItems, result.updatedItems);
    return result;
  }
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

    test(
      'full rescan preserves user metadata from the previous record',
      () async {
        final repo = GalleryRepository(
          scannerService: _StubScanner([_item('1')], const []),
          mediaDao: db.mediaDao,
        );
        await repo.scanDevice();
        await repo.toggleHidden('1');
        await repo.toggleFavorite('1');

        // A second full scan re-discovers item '1' with default metadata; the
        // repository must keep the hidden/favorite flags rather than wiping
        // them with the fresh scan.
        await repo.scanDevice();
        final item = repo.getItemById('1');
        expect(item?.isHidden, isTrue);
        expect(item?.isFavorite, isTrue);

        final repo2 = GalleryRepository(
          scannerService: _StubScanner(const [], const []),
          mediaDao: db.mediaDao,
        );
        await repo2.hydrate();
        expect(repo2.getItemById('1')?.isHidden, isTrue);
      },
    );

    test('incremental update preserves metadata and resets upload state '
        'when the content hash changes', () async {
      final initial = _item('1').copyWith(
        status: MediaStatus.uploaded,
        uploadedAt: DateTime(2026, 1, 1),
        backedUpAt: DateTime(2026, 1, 1),
        telegramMessageId: 'msg-1',
        telegramFileId: 'file-1',
      );
      final repo = GalleryRepository(
        scannerService: _StubScanner([initial], const []),
        mediaDao: db.mediaDao,
        incrementalScanner: _FakeIncrementalScanner(
          IncrementalScanResult(
            newItems: const [],
            updatedItems: [
              // Device re-saved the file: new hash, scanner-default flags.
              _item('1').copyWith(
                fileHash: 'hash-1-edited',
                modifiedAt: DateTime(2026, 1, 2),
                isExcluded: true,
              ),
            ],
            deletedIds: const [],
            totalChecked: 1,
            duration: Duration.zero,
          ),
        ),
      );
      await repo.scanDevice();
      await repo.toggleHidden('1');
      await repo.toggleFavorite('1');

      await repo.scanDeviceIncremental();

      final item = repo.getItemById('1');
      // User state survives the rescan.
      expect(item?.isHidden, isTrue);
      expect(item?.isFavorite, isTrue);
      expect(item?.isExcluded, isFalse);
      // Device state comes from the fresh scan.
      expect(item?.fileHash, 'hash-1-edited');
      // New content means the old upload badge must not survive.
      expect(item?.status, MediaStatus.pending);
      expect(item?.uploadedAt, isNull);
      expect(item?.telegramMessageId, isNull);

      // The DB row was updated in place (no duplicate rows, no exception).
      final repo2 = GalleryRepository(
        scannerService: _StubScanner(const [], const []),
        mediaDao: db.mediaDao,
      );
      await repo2.hydrate();
      expect(repo2.totalCount, 1);
      expect(repo2.getItemById('1')?.isHidden, isTrue);
      expect(repo2.getItemById('1')?.status, MediaStatus.pending);
    });

    test(
      'incremental update keeps upload state when the hash is unchanged',
      () async {
        final initial = _item('1').copyWith(
          status: MediaStatus.uploaded,
          uploadedAt: DateTime(2026, 1, 1),
          backedUpAt: DateTime(2026, 1, 1),
          telegramMessageId: 'msg-1',
          telegramFileId: 'file-1',
        );
        final repo = GalleryRepository(
          scannerService: _StubScanner([initial], const []),
          mediaDao: db.mediaDao,
          incrementalScanner: _FakeIncrementalScanner(
            IncrementalScanResult(
              newItems: const [],
              updatedItems: [
                // Timestamp touched, same content: hash unchanged.
                _item('1').copyWith(modifiedAt: DateTime(2026, 1, 2)),
              ],
              deletedIds: const [],
              totalChecked: 1,
              duration: Duration.zero,
            ),
          ),
        );
        await repo.scanDevice();

        await repo.scanDeviceIncremental();

        final item = repo.getItemById('1');
        expect(item?.status, MediaStatus.uploaded);
        expect(item?.uploadedAt, DateTime(2026, 1, 1));
        expect(item?.telegramMessageId, 'msg-1');
        expect(item?.telegramFileId, 'file-1');
      },
    );

    test(
      'purgeExpiredTrashedItems removes only trash past retention',
      () async {
        final expired = _item('1').copyWith(
          isTrashed: true,
          trashedAt: DateTime.now().subtract(const Duration(days: 40)),
        );
        final recent = _item(
          '2',
        ).copyWith(isTrashed: true, trashedAt: DateTime.now());
        final repo = GalleryRepository(
          scannerService: _StubScanner([expired, recent, _item('3')], const []),
          mediaDao: db.mediaDao,
        );
        await repo.scanDevice();

        expect(await repo.purgeExpiredTrashedItems(), 1);
        expect(repo.getItemById('1'), isNull);
        expect(repo.getItemById('2')?.isTrashed, isTrue);
        expect(repo.getItemById('3'), isNotNull);

        final repo2 = GalleryRepository(
          scannerService: _StubScanner(const [], const []),
          mediaDao: db.mediaDao,
        );
        await repo2.hydrate();
        expect(repo2.getItemById('1'), isNull);
        expect(repo2.getItemById('2')?.isTrashed, isTrue);
      },
    );

    test('hydrate purges trash past the retention window', () async {
      final repo = GalleryRepository(
        scannerService: _StubScanner([
          _item('1').copyWith(
            isTrashed: true,
            trashedAt: DateTime.now().subtract(const Duration(days: 40)),
          ),
        ], const []),
        mediaDao: db.mediaDao,
      );
      await repo.scanDevice();

      final repo2 = GalleryRepository(
        scannerService: _StubScanner(const [], const []),
        mediaDao: db.mediaDao,
      );
      await repo2.hydrate();
      expect(repo2.totalCount, 0);
      expect(repo2.getItemById('1'), isNull);
    });
  });
}
