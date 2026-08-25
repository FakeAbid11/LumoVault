import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';
import 'package:photo_manager/photo_manager.dart';

class _StubScanner implements MediaScannerService {
  List<MediaItem> items = [];

  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<ScanResult> scanDevice({
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
  }) async => ScanResult(
    mediaItems: items,
    folders: const [],
    totalScanned: items.length,
    newItems: items.length,
    updatedItems: 0,
    duration: Duration.zero,
  );

  @override
  Future<List<AssetEntity>> listAllAssets({
    void Function(int loaded)? onProgress,
  }) async => [];

  @override
  Future<Uint8List?> getThumbnail(String assetId) async => null;

  @override
  Future<File?> getFullFile(String assetId) async => null;

  @override
  Future<List<DeviceFolder>> getDeviceFolders() async => const [];
}

MediaItem _item(
  String id, {
  String? messageId,
  bool isTrashed = false,
  DateTime? trashedAt,
}) => MediaItem(
  localId: id,
  fileHash: 'hash_$id',
  filePath: '/p/$id.jpg',
  fileName: '$id.jpg',
  mimeType: 'image/jpeg',
  fileSize: 100,
  width: 10,
  height: 10,
  createdAt: DateTime(2026, 1, 15),
  modifiedAt: DateTime(2026, 1, 15),
  scannedAt: DateTime(2026, 1, 15),
  telegramMessageId: messageId,
  isTrashed: isTrashed,
  trashedAt: trashedAt,
);

void main() {
  group('GalleryRepository remote-delete propagation', () {
    late _StubScanner scanner;
    late GalleryRepository repository;
    late List<List<int>> remoteDeletes;

    setUp(() async {
      scanner = _StubScanner();
      repository = GalleryRepository(scannerService: scanner);
      remoteDeletes = [];
      repository.setRemoteDeleteCallback((ids) async {
        remoteDeletes.add(ids);
      });
      scanner.items = [
        _item('a', messageId: '10'),
        _item('b', messageId: '20'),
        _item('c'), // never uploaded — no message id
      ];
      await repository.scanDevice();
    });

    test('permanent delete revokes the channel messages', () async {
      await repository.deletePermanentlyBatch(['a', 'b']);

      expect(remoteDeletes, hasLength(1));
      expect(remoteDeletes.first, containsAll(<int>[10, 20]));
      expect(repository.totalCount, 1); // only 'c' remains
    });

    test('an item never uploaded contributes no message id', () async {
      await repository.deletePermanentlyBatch(['c']);

      // No message id to revoke -> the callback is never invoked.
      expect(remoteDeletes, isEmpty);
    });

    test('moveToTrash never touches the channel', () async {
      await repository.moveToTrash('a');

      expect(remoteDeletes, isEmpty);
      // The item is still present, just flagged trashed.
      final trashed = repository.getTrashedItems();
      expect(trashed.map((i) => i.localId), contains('a'));
    });
  });

  group('GalleryRepository auto-purge retains the cloud backup', () {
    late _StubScanner scanner;
    late GalleryRepository repository;
    late List<List<int>> remoteDeletes;

    setUp(() async {
      scanner = _StubScanner();
      repository = GalleryRepository(scannerService: scanner);
      remoteDeletes = [];
      repository.setRemoteDeleteCallback((ids) async {
        remoteDeletes.add(ids);
      });
      scanner.items = [
        // Trashed 90 days ago -> well past the retention cutoff.
        _item(
          'old',
          messageId: '10',
          isTrashed: true,
          trashedAt: DateTime.now().subtract(const Duration(days: 90)),
        ),
        // Freshly trashed -> must survive the purge.
        _item(
          'fresh',
          messageId: '20',
          isTrashed: true,
          trashedAt: DateTime.now(),
        ),
      ];
      await repository.scanDevice();
    });

    test(
      'expired items are removed locally but NOT revoked remotely',
      () async {
        final purged = await repository.purgeExpiredTrashedItems(
          retentionDays: 30,
        );

        expect(purged, 1);
        // The expired item is gone locally...
        expect(repository.getItemById('old'), isNull);
        // ...but its cloud copy was never revoked.
        expect(remoteDeletes, isEmpty);
        // The freshly-trashed item is untouched.
        expect(repository.getItemById('fresh'), isNotNull);
      },
    );

    test(
      'opting in to revokeRemote still revokes expired cloud copies',
      () async {
        final purged = await repository.purgeExpiredTrashedItems(
          retentionDays: 30,
          revokeRemote: true,
        );

        expect(purged, 1);
        expect(remoteDeletes, hasLength(1));
        expect(remoteDeletes.first, contains(10));
      },
    );
  });
}
