import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';
import 'package:lumovault/features/metadata/data/repositories/conflict_resolver.dart';
import 'package:lumovault/features/metadata/data/repositories/manifest_service.dart';
import 'package:lumovault/features/metadata/data/repositories/metadata_integration.dart';
import 'package:lumovault/features/metadata/data/repositories/metadata_repository.dart';
import 'package:lumovault/features/metadata/data/repositories/partition_service.dart';
import 'package:lumovault/features/metadata/data/repositories/search_index_service.dart';
import 'package:lumovault/features/metadata/data/repositories/sync_service.dart';
import 'package:photo_manager/photo_manager.dart';

class _StubScanner implements MediaScannerService {
  _StubScanner(this.items);

  final List<MediaItem> items;

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
      mediaItems: items,
      folders: const [],
      totalScanned: items.length,
      newItems: items.length,
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
  Future<List<DeviceFolder>> getDeviceFolders() async => const [];
}

MediaItem _item(String localId) => MediaItem(
  localId: localId,
  fileHash: 'hash-$localId',
  filePath: '/p/$localId.jpg',
  fileName: '$localId.jpg',
  mimeType: 'image/jpeg',
  fileSize: 100,
  width: 10,
  height: 10,
  createdAt: DateTime(2026, 1, 15),
  modifiedAt: DateTime(2026, 1, 15),
  scannedAt: DateTime(2026, 1, 15),
);

void main() {
  group('MetadataIntegration', () {
    late MetadataRepository metadataRepository;
    late MetadataIntegration integration;
    late GalleryRepository gallery;

    setUp(() {
      metadataRepository = MetadataRepository(
        manifestService: ManifestService(),
        partitionService: PartitionService(),
        searchIndexService: SearchIndexService(),
        syncService: SyncService(),
        conflictResolver: ConflictResolver(),
      );
      integration = MetadataIntegration(metadataRepository: metadataRepository);
      gallery = GalleryRepository(
        scannerService: _StubScanner([_item('1'), _item('2')]),
      );
      integration.connectGalleryRepository(gallery);
    });

    tearDown(() {
      metadataRepository.dispose();
    });

    test('scan discovery feeds the metadata layer', () async {
      await gallery.scanDevice();

      expect(metadataRepository.totalItems, 2);
      expect(metadataRepository.getItemMetadata('1'), isNotNull);
    });

    test(
      'markUploaded records the Telegram IDs into the metadata layer',
      () async {
        await gallery.scanDevice();

        await gallery.markUploaded(
          localId: '1',
          telegramMessageId: 'msg_456',
          telegramFileId: 'file_789',
        );

        final metadata = metadataRepository.getItemMetadata('1');
        expect(metadata, isNotNull);
        expect(metadata!.telegramMessageId, 'msg_456');
        expect(metadata.telegramFileId, 'file_789');
        expect(metadata.backedUpAt, isNotNull);

        // The partition (which is what sync uploads) carries the IDs too.
        final partitionItem = metadataRepository.getAllMetadata().firstWhere(
          (m) => m.localId == '1',
        );
        expect(partitionItem.telegramMessageId, 'msg_456');
        expect(partitionItem.telegramFileId, 'file_789');
      },
    );

    test(
      'markUploaded without Telegram IDs leaves metadata untouched',
      () async {
        await gallery.scanDevice();

        await gallery.markUploaded(localId: '1');

        final metadata = metadataRepository.getItemMetadata('1');
        expect(metadata!.telegramMessageId, isNull);
        expect(metadata.telegramFileId, isNull);
      },
    );

    test('favorite toggles flow through to the metadata layer', () async {
      await gallery.scanDevice();

      await gallery.toggleFavorite('1');

      final metadata = metadataRepository.getItemMetadata('1');
      expect(metadata!.isFavorite, isTrue);
    });
  });
}
