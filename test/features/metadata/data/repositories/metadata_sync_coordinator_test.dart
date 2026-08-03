import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/models/upload_task.dart';
import 'package:lumovault/features/gallery/data/repositories/telegram_upload_service.dart';
import 'package:lumovault/features/metadata/data/models/metadata_models.dart';
import 'package:lumovault/features/metadata/data/repositories/conflict_resolver.dart';
import 'package:lumovault/features/metadata/data/repositories/manifest_service.dart';
import 'package:lumovault/features/metadata/data/repositories/metadata_repository.dart';
import 'package:lumovault/features/metadata/data/repositories/metadata_sync_coordinator.dart';
import 'package:lumovault/features/metadata/data/repositories/partition_service.dart';
import 'package:lumovault/features/metadata/data/repositories/search_index_service.dart';
import 'package:lumovault/features/metadata/data/repositories/sync_service.dart';
import 'package:lumovault/features/metadata/data/repositories/telegram_metadata_uploader.dart';

class _RecordedUpload {
  _RecordedUpload(this.task);
  final UploadTask task;
}

class _FakeUploadService implements UploadService {
  final List<_RecordedUpload> uploaded = [];

  @override
  Stream<UploadProgress> get progressStream =>
      const Stream<UploadProgress>.empty();

  @override
  Future<UploadResult> uploadFile({
    required UploadTask task,
    required int channelId,
    bool includeCaption = true,
  }) async {
    uploaded.add(_RecordedUpload(task));
    return UploadResult(taskId: task.id, messageId: 42, fileId: 7);
  }

  @override
  Future<void> cancelUpload(String taskId) async {}

  @override
  void dispose() {}
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
  createdAt: DateTime(2026, 1, 15),
  modifiedAt: DateTime(2026, 1, 15),
  scannedAt: DateTime(2026, 1, 15),
  isFavorite: favorite,
);

void main() {
  group('MetadataSyncCoordinator', () {
    late MetadataRepository repository;
    late ManifestService manifestService;
    late PartitionService partitionService;
    late SearchIndexService searchIndexService;
    late SyncService syncService;
    late ConflictResolver conflictResolver;
    late _FakeUploadService uploadService;
    late TelegramMetadataUploader uploader;
    late MetadataSyncCoordinator coordinator;
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('lumovault_coord_test');
      manifestService = ManifestService();
      partitionService = PartitionService();
      searchIndexService = SearchIndexService();
      syncService = SyncService(
        debounceDuration: const Duration(milliseconds: 100),
      );
      conflictResolver = ConflictResolver();

      repository = MetadataRepository(
        manifestService: manifestService,
        partitionService: partitionService,
        searchIndexService: searchIndexService,
        syncService: syncService,
        conflictResolver: conflictResolver,
      );

      uploadService = _FakeUploadService();
      uploader = TelegramMetadataUploader(
        uploadService: uploadService,
        channelIdProvider: () async => 1,
        tempDirProvider: () async => tempDir,
        deviceHashProvider: () async => 'device-hash-1',
      );
      coordinator = MetadataSyncCoordinator(
        metadataRepository: repository,
        uploader: uploader,
      );
    });

    tearDown(() {
      coordinator.dispose();
      repository.dispose();
      manifestService.dispose();
      partitionService.dispose();
      searchIndexService.dispose();
      syncService.dispose();
      uploadService.dispose();
      tempDir.deleteSync(recursive: true);
    });

    List<String> uploadedFiles() =>
        uploadService.uploaded.map((u) => u.task.fileName).toList();

    test('syncNow generates a manifest when none exists', () async {
      expect(repository.getCurrentManifest(), isNull);

      await repository.recordNewItem(_item('1'));
      await coordinator.syncNow();

      final manifest = repository.getCurrentManifest();
      expect(manifest, isNotNull);
      expect(manifest!.deviceHash, 'device-hash-1');
    });

    test('syncNow uploads dirty partitions and the manifest', () async {
      await repository.recordNewItem(_item('1'));

      final synced = await coordinator.syncNow();

      expect(synced, 1);
      expect(uploadedFiles(), contains('metadata/2026-01.json'));
      expect(uploadedFiles(), contains('metadata/manifest.json'));
      expect(repository.getDirtyPartitions(), isEmpty);
    });

    test('a clean run re-uploads only the manifest', () async {
      await repository.recordNewItem(_item('1'));
      await coordinator.syncNow();
      uploadService.uploaded.clear();

      final synced = await coordinator.syncNow();

      expect(synced, 0);
      expect(uploadedFiles(), ['metadata/manifest.json']);
    });

    test('an edit after sync makes the partition dirty again', () async {
      await repository.recordNewItem(_item('1'));
      await coordinator.syncNow();
      uploadService.uploaded.clear();

      await repository.recordStateChange(
        localId: '1',
        operation: 'favorite_toggle',
        updatedItem: PartitionItem(
          localId: '1',
          fileHash: 'hash-1',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
          isFavorite: true,
        ),
      );

      final synced = await coordinator.syncNow();

      expect(synced, 1);
      expect(uploadedFiles(), contains('metadata/2026-01.json'));
      expect(uploadedFiles(), contains('metadata/manifest.json'));
      expect(repository.getDirtyPartitions(), isEmpty);
    });

    test('gallery mutations auto-sync after the debounced flush', () async {
      await repository.recordNewItem(_item('1'));

      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        uploadedFiles(),
        containsAll(['metadata/2026-01.json', 'metadata/manifest.json']),
      );
    });

    test('concurrent syncNow calls do not double-upload', () async {
      await repository.recordNewItem(_item('1'));

      final results = await Future.wait([
        coordinator.syncNow(),
        coordinator.syncNow(),
      ]);

      expect(results, [1, 0]);
      expect(
        uploadedFiles().where((f) => f == 'metadata/2026-01.json'),
        hasLength(1),
      );
    });
  });
}
