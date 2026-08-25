import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/storage/thumbnail_cache.dart';
import 'package:lumovault/features/restore/engine/restore_engine.dart';
import 'package:lumovault/features/restore/engine/restore_state_store.dart';
import 'package:lumovault/features/restore/data/repositories/restore_repository.dart';
import 'package:lumovault/features/restore/data/models/restore_progress.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';
import 'package:lumovault/features/gallery/data/repositories/telegram_download_service.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/models/caption_metadata.dart';
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

/// 1x1 transparent PNG — valid image bytes for thumbnail cache round-trips.
final Uint8List kTransparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

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
    // ThumbnailCache.instance is a process-wide singleton; isolate tests so
    // one test's cached entries can't silently turn another test's download
    // into a skip.
    ThumbnailCache.instance.clear();

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

    test(
      'startRestore writes downloaded thumbnails into the shared cache',
      () async {
        // Real file on disk so the engine's thumbnail cache write can read it.
        final tempDir = await Directory.systemTemp.createTemp(
          'lumovault_restore_test',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final thumbFile = File('${tempDir.path}/thumb.jpg');
        await thumbFile.writeAsBytes(kTransparentPng);

        final repo = engine.restoreRepository as MockRestoreRepository;
        repo.detectionResult = const ChannelDetectionResult(channelId: 42);
        repo.manifest = Manifest.create(deviceHash: 'test_device');
        final metadata = CaptionMetadata(
          mediaItemId: 'restored_local_1',
          fileHash: 'abc123',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
          backedUpAt: DateTime(2026, 1, 15),
        );
        repo.messages = [
          ChannelMessage(
            messageId: 1,
            fileId: 10,
            fileName: 'photo.jpg',
            caption: metadata.toCaptionString(),
          ),
        ];
        repo.thumbnailFile = DownloadedFile(
          filePath: thumbFile.path,
          fileName: 'photo.jpg',
        );

        final result = await engine.startRestore();
        expect(result, isTrue);
        expect(engine.currentProgress.phase, RestorePhase.completed);
        // The restored item's tile must find its thumbnail in the cache instead
        // of staying on the placeholder.
        expect(
          await ThumbnailCache.instance.contains('restored_local_1'),
          isTrue,
        );
      },
    );

    test(
      'startRestore persists restored hashes into the state store',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'lumovault_restore_state',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final store = RestoreStateStore(filePath: '${tempDir.path}/state.json');
        final engineWithStore = RestoreEngine(
          restoreRepository: MockRestoreRepository(),
          galleryRepository: galleryRepository,
          metadataRepository: metadataRepository,
          manifestService: manifestService,
          partitionService: partitionService,
          searchIndexService: searchIndexService,
          restoreStateStore: store,
        );
        addTearDown(engineWithStore.dispose);

        final repo = engineWithStore.restoreRepository as MockRestoreRepository;
        repo.detectionResult = const ChannelDetectionResult(channelId: 42);
        repo.manifest = Manifest.create(deviceHash: 'test_device');
        repo.messages = [
          ChannelMessage(
            messageId: 1,
            fileId: 10,
            fileName: 'photo.jpg',
            caption: CaptionMetadata(
              mediaItemId: 'r1',
              fileHash: 'abc123',
              createdAt: DateTime(2026, 1, 15),
              modifiedAt: DateTime(2026, 1, 15),
              backedUpAt: DateTime(2026, 1, 15),
            ).toCaptionString(),
          ),
        ];
        repo.thumbnailFile = const DownloadedFile(
          filePath: '/nonexistent/thumb.bin',
          fileName: 'photo.jpg',
        );

        final result = await engineWithStore.startRestore();
        expect(result, isTrue);

        final persisted = await store.load();
        expect(persisted, contains('abc123'));
      },
    );

    test('startRestore skips thumbnails already in the shared cache', () async {
      // Pre-populate the cache under the same key the channel scan uses.
      await ThumbnailCache.instance.put('r2', kTransparentPng);

      final repo = engine.restoreRepository as MockRestoreRepository;
      repo.detectionResult = const ChannelDetectionResult(channelId: 42);
      repo.manifest = Manifest.create(deviceHash: 'test_device');
      repo.messages = [
        ChannelMessage(
          messageId: 2,
          fileId: 20,
          fileName: 'photo2.jpg',
          caption: CaptionMetadata(
            mediaItemId: 'r2',
            fileHash: 'hash2',
            createdAt: DateTime(2026, 1, 15),
            modifiedAt: DateTime(2026, 1, 15),
            backedUpAt: DateTime(2026, 1, 15),
          ).toCaptionString(),
        ),
      ];
      repo.thumbnailFile = const DownloadedFile(
        filePath: '/nonexistent/thumb.bin',
        fileName: 'photo2.jpg',
      );

      final result = await engine.startRestore();
      expect(result, isTrue);
      expect(repo.downloadCalls, 0);
      expect(engine.currentProgress.skippedItems, 1);
    });

    test('startRestore rebuilds trashed state from captions', () async {
      final trashedAt = DateTime.utc(2026, 6, 1, 12, 30);

      final repo = engine.restoreRepository as MockRestoreRepository;
      repo.detectionResult = const ChannelDetectionResult(channelId: 42);
      repo.manifest = Manifest.create(deviceHash: 'test_device');
      repo.messages = [
        ChannelMessage(
          messageId: 3,
          fileId: 30,
          fileName: 'trashed.jpg',
          caption: CaptionMetadata(
            mediaItemId: 'r_trash',
            fileHash: 'hash_trash',
            createdAt: DateTime(2026, 1, 15),
            modifiedAt: DateTime(2026, 1, 15),
            backedUpAt: DateTime(2026, 1, 15),
            isTrashed: true,
            trashedAt: trashedAt,
          ).toCaptionString(),
        ),
      ];
      repo.thumbnailFile = const DownloadedFile(
        filePath: '/nonexistent/thumb.bin',
        fileName: 'trashed.jpg',
      );

      final result = await engine.startRestore();
      expect(result, isTrue);

      final restored = galleryRepository.getItemById('r_trash');
      expect(restored, isNotNull);
      expect(restored!.isTrashed, isTrue);
      expect(restored.trashedAt, trashedAt);
    });

    test('a tombstoned item is not resurrected on restore', () async {
      // Simulate the convergence case: item 'r_del' was permanently deleted
      // here (or the deletion arrived via a Layer-3 reconcile), leaving a local
      // tombstone — but the channel media message, and therefore its caption,
      // still exists. A caption-driven rebuild must NOT bring it back.
      metadataRepository.recordNewItem(
        MediaItem(
          localId: 'r_del',
          fileHash: 'hash_del',
          filePath: '/p/r_del.jpg',
          fileName: 'r_del.jpg',
          mimeType: 'image/jpeg',
          fileSize: 100,
          width: 10,
          height: 10,
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
          scannedAt: DateTime(2026, 1, 15),
        ),
      );
      metadataRepository.recordDeletion(localId: 'r_del', operation: 'delete');
      expect(metadataRepository.getItemMetadata('r_del')!.isDeleted, isTrue);

      final repo = engine.restoreRepository as MockRestoreRepository;
      repo.detectionResult = const ChannelDetectionResult(channelId: 42);
      repo.manifest = Manifest.create(deviceHash: 'test_device');
      repo.messages = [
        ChannelMessage(
          messageId: 7,
          fileId: 70,
          fileName: 'r_del.jpg',
          caption: CaptionMetadata(
            mediaItemId: 'r_del',
            fileHash: 'hash_del',
            createdAt: DateTime(2026, 1, 15),
            modifiedAt: DateTime(2026, 1, 15),
            backedUpAt: DateTime(2026, 1, 15),
          ).toCaptionString(),
        ),
      ];
      repo.thumbnailFile = const DownloadedFile(
        filePath: '/nonexistent/thumb.bin',
        fileName: 'r_del.jpg',
      );

      final result = await engine.startRestore();
      expect(result, isTrue);

      // The still-present caption did not resurrect the deleted item.
      expect(galleryRepository.getItemById('r_del'), isNull);
      // And its tombstone is intact for continued convergence.
      expect(metadataRepository.getItemMetadata('r_del')!.isDeleted, isTrue);
    });
    test(
      'resumeInterruptedRestore combines persisted and gallery hashes',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'lumovault_restore_state',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final store = RestoreStateStore(filePath: '${tempDir.path}/state.json');
        await store.save({'persisted_hash_1'});

        final engineWithStore = RestoreEngine(
          restoreRepository: MockRestoreRepository(),
          galleryRepository: galleryRepository,
          metadataRepository: metadataRepository,
          manifestService: manifestService,
          partitionService: partitionService,
          searchIndexService: searchIndexService,
          restoreStateStore: store,
        );
        addTearDown(engineWithStore.dispose);

        await engineWithStore.resumeInterruptedRestore();
        expect(engineWithStore.isAlreadyRestored('persisted_hash_1'), isTrue);
        expect(engineWithStore.isAlreadyRestored('unknown_hash'), isFalse);
      },
    );
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
  /// Configurable happy-path results — defaults keep the pre-existing
  /// "no backup found" behavior for other tests.
  ChannelDetectionResult detectionResult = const ChannelDetectionResult(
    error: 'No backup found',
  );
  Manifest? manifest;
  List<ChannelMessage> messages = [];
  DownloadedFile? thumbnailFile;

  /// Number of times [downloadFile] has been invoked.
  int downloadCalls = 0;

  @override
  Future<ChannelDetectionResult> detectExistingBackup() async =>
      detectionResult;

  @override
  Future<Manifest?> fetchManifest(int channelId) async => manifest;

  @override
  Future<List<ChannelMessage>> fetchChannelMessages(int channelId) async =>
      messages;

  @override
  Future<DownloadedFile> downloadFile({
    required int messageId,
    required int channelId,
    required String fileName,
    DownloadMode mode = DownloadMode.original,
    void Function(double progress)? onProgress,
  }) async {
    downloadCalls++;
    final file = thumbnailFile;
    if (file == null) {
      throw StateError('thumbnailFile not configured for this test');
    }
    return file;
  }

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
