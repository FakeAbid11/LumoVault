import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/restore/engine/restore_engine.dart';
import 'package:lumovault/features/restore/data/repositories/restore_repository.dart';
import 'package:lumovault/features/restore/data/models/restore_progress.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';
import 'package:lumovault/features/gallery/data/repositories/telegram_download_service.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/metadata/data/repositories/manifest_service.dart';
import 'package:lumovault/features/metadata/data/repositories/metadata_repository.dart';
import 'package:lumovault/features/metadata/data/repositories/partition_service.dart';
import 'package:lumovault/features/metadata/data/repositories/search_index_service.dart';
import 'package:lumovault/features/metadata/data/repositories/sync_service.dart';
import 'package:lumovault/features/metadata/data/repositories/conflict_resolver.dart';
import 'package:lumovault/features/metadata/data/models/manifest.dart';
import 'package:lumovault/features/metadata/data/models/metadata_partition.dart';
import 'package:photo_manager/photo_manager.dart';

class MockMediaScannerService implements MediaScannerService {
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
  }) async => [];

  @override
  Future<Uint8List?> getThumbnail(String assetId) async => null;

  @override
  Future<File?> getFullFile(String assetId) async => null;

  @override
  Future<List<DeviceFolder>> getDeviceFolders() async => [];
}

void main() {
  late RestoreEngine engine;
  late GalleryRepository galleryRepository;
  late MetadataRepository metadataRepository;
  late ManifestService manifestService;
  late PartitionService partitionService;
  late SearchIndexService searchIndexService;
  late SyncService syncService;
  late ConflictResolver conflictResolver;

  setUp(() {
    manifestService = ManifestService();
    partitionService = PartitionService();
    searchIndexService = SearchIndexService();
    syncService = SyncService();
    conflictResolver = ConflictResolver();

    metadataRepository = MetadataRepository(
      manifestService: manifestService,
      partitionService: partitionService,
      searchIndexService: searchIndexService,
      syncService: syncService,
      conflictResolver: conflictResolver,
    );

    galleryRepository = GalleryRepository(
      scannerService: MockMediaScannerService(),
    );

    engine = RestoreEngine(
      restoreRepository: MockRestoreRepository(),
      galleryRepository: galleryRepository,
      metadataRepository: metadataRepository,
      manifestService: manifestService,
      partitionService: partitionService,
      searchIndexService: searchIndexService,
    );
  });

  tearDown(() {
    engine.dispose();
    metadataRepository.dispose();
    manifestService.dispose();
    partitionService.dispose();
    searchIndexService.dispose();
    syncService.dispose();
  });

  group('RestoreEngine', () {
    test('initial progress is detecting phase', () {
      expect(engine.currentProgress.phase, RestorePhase.detecting);
      expect(engine.currentProgress.overallProgress, 0.0);
    });

    test('pauseRestore sets paused state', () {
      engine.pauseRestore();
      expect(engine.currentProgress.isPaused, isTrue);
    });

    test('resumeRestore unpauses', () {
      engine.pauseRestore();
      engine.resumeRestore();
      expect(engine.currentProgress.isPaused, isFalse);
    });

    test('cancelRestore sets failed phase with cancelled error', () {
      engine.cancelRestore();
      expect(engine.currentProgress.isFailed, isTrue);
      expect(
        engine.currentProgress.error?.category,
        RestoreErrorCategory.cancelled,
      );
    });

    test('isAlreadyRestored returns false initially', () {
      expect(engine.isAlreadyRestored('abc123'), isFalse);
    });

    test('resumeInterruptedRestore loads existing hashes', () async {
      await engine.resumeInterruptedRestore();
      expect(engine.isAlreadyRestored('nonexistent'), isFalse);
    });

    test('progress stream emits updates', () async {
      final updates = <RestoreProgress>[];
      final subscription = engine.progressStream.listen((progress) {
        updates.add(progress);
      });

      engine.cancelRestore();
      await Future.delayed(const Duration(milliseconds: 50));

      await subscription.cancel();
      expect(updates, isNotEmpty);
      expect(updates.last.phase, RestorePhase.failed);
    });

    test('startRestore returns false when no backup found', () async {
      final result = await engine.startRestore();
      expect(result, isFalse);
      expect(engine.currentProgress.phase, RestorePhase.failed);
    });
  });

  group('ManifestService restore operations', () {
    test('setManifest stores manifest correctly', () {
      final manifest = Manifest.create(deviceHash: 'test_device');
      manifestService.setManifest(manifest);

      final stored = manifestService.getCurrentManifest();
      expect(stored, isNotNull);
      expect(stored!.deviceHash, 'test_device');
    });

    test('getPartitionHash returns null for unknown partition', () {
      expect(manifestService.getPartitionHash('2026/01'), isNull);
    });

    test('getPartitionHash returns hash after setManifest', () {
      final manifest = Manifest.create(deviceHash: 'test_device').copyWith(
        chunks: [const ManifestChunk(id: '2026/01', count: 100, hash: 'abc')],
      );

      manifestService.setManifest(manifest);
      expect(manifestService.getPartitionHash('2026/01'), 'abc');
    });
  });

  group('PartitionService restore operations', () {
    test('clear removes all partitions', () {
      partitionService.upsertItem(
        PartitionItem(
          localId: '1',
          fileHash: 'abc',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
        ),
      );

      expect(partitionService.partitionCount, 1);
      partitionService.clear();
      expect(partitionService.partitionCount, 0);
    });

    test('getAllPartitions returns sorted list', () {
      partitionService.upsertItem(
        PartitionItem(
          localId: '2',
          fileHash: 'def',
          createdAt: DateTime(2026, 2, 15),
          modifiedAt: DateTime(2026, 2, 15),
        ),
      );
      partitionService.upsertItem(
        PartitionItem(
          localId: '1',
          fileHash: 'abc',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
        ),
      );

      final partitions = partitionService.getAllPartitions();
      expect(partitions.length, 2);
      expect(partitions[0].id, '2026/01');
      expect(partitions[1].id, '2026/02');
    });

    test('upsertItem updates existing item', () {
      partitionService.upsertItem(
        PartitionItem(
          localId: '1',
          fileHash: 'abc',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
          isFavorite: false,
        ),
      );

      partitionService.upsertItem(
        PartitionItem(
          localId: '1',
          fileHash: 'abc',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
          isFavorite: true,
        ),
      );

      final partition = partitionService.getPartition('2026/01');
      expect(partition, isNotNull);
      expect(partition!.items.length, 1);
      expect(partition.items.first.isFavorite, isTrue);
    });
  });

  group('SearchIndexService restore operations', () {
    test('clear removes all index entries', () {
      searchIndexService.indexItem(
        PartitionItem(
          localId: '1',
          fileHash: 'abc',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
          fileName: 'photo.jpg',
        ),
      );

      expect(searchIndexService.indexSize, greaterThan(0));
      searchIndexService.clear();
      expect(searchIndexService.indexSize, 0);
    });

    test('search finds indexed items after restore', () {
      searchIndexService.indexItem(
        PartitionItem(
          localId: '1',
          fileHash: 'abc',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
          fileName: 'vacation_photo.jpg',
        ),
      );

      final results = searchIndexService.search('vacation');
      expect(results, contains('1'));
    });

    test('reindexItem updates index entries', () {
      searchIndexService.indexItem(
        PartitionItem(
          localId: '1',
          fileHash: 'abc',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
          fileName: 'photo.jpg',
        ),
      );

      searchIndexService.reindexItem(
        PartitionItem(
          localId: '1',
          fileHash: 'abc',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
          fileName: 'renamed_photo.jpg',
        ),
      );

      final results = searchIndexService.search('renamed');
      expect(results, contains('1'));
    });
  });
}

/// Mock restore repository for testing.
class MockRestoreRepository implements RestoreRepository {
  @override
  Future<ChannelDetectionResult> detectExistingBackup() async {
    return const ChannelDetectionResult(error: 'No backup found');
  }

  @override
  Future<Manifest?> fetchManifest(int channelId) async => null;

  @override
  Future<List<ChannelMessage>> fetchChannelMessages(int channelId) async => [];

  @override
  Future<DownloadedFile?> downloadFile({
    required int messageId,
    required int channelId,
    required String fileName,
    DownloadMode mode = DownloadMode.original,
    void Function(double progress)? onProgress,
  }) async => null;

  @override
  Future<String> saveRestoredFile({
    required String sourcePath,
    required String fileName,
    required String subDir,
  }) async => sourcePath;

  @override
  MediaItem? buildMediaItemFromMessage({
    required ChannelMessage message,
    required String localFilePath,
    required String fileName,
  }) => null;

  @override
  Future<void> cancelDownload(String taskId) async {}

  @override
  void dispose() {}
}
