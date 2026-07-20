import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/metadata/data/models/metadata_models.dart';
import 'package:lumovault/features/metadata/data/repositories/conflict_resolver.dart';
import 'package:lumovault/features/metadata/data/repositories/manifest_service.dart';
import 'package:lumovault/features/metadata/data/repositories/metadata_repository.dart';
import 'package:lumovault/features/metadata/data/repositories/partition_service.dart';
import 'package:lumovault/features/metadata/data/repositories/search_index_service.dart';
import 'package:lumovault/features/metadata/data/repositories/sync_service.dart';

void main() {
  group('MetadataRepository', () {
    late MetadataRepository repository;
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

      repository = MetadataRepository(
        manifestService: manifestService,
        partitionService: partitionService,
        searchIndexService: searchIndexService,
        syncService: syncService,
        conflictResolver: conflictResolver,
      );
    });

    tearDown(() {
      repository.dispose();
      manifestService.dispose();
      partitionService.dispose();
      searchIndexService.dispose();
      syncService.dispose();
    });

    test('totalItems returns 0 initially', () {
      expect(repository.totalItems, 0);
    });

    test('getItemMetadata returns null for unknown item', () {
      expect(repository.getItemMetadata('123'), isNull);
    });

    test('recordNewItem adds item to metadata', () {
      final item = MediaItem(
        localId: '123',
        fileHash: 'abc123',
        filePath: '/path/file.jpg',
        fileName: 'file.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024,
        width: 1920,
        height: 1080,
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        scannedAt: DateTime(2026, 1, 15),
      );

      repository.recordNewItem(item);

      expect(repository.totalItems, 1);
      final metadata = repository.getItemMetadata('123');
      expect(metadata, isNotNull);
      expect(metadata!.localId, '123');
    });

    test('recordStateChange updates item metadata', () {
      final item = MediaItem(
        localId: '123',
        fileHash: 'abc123',
        filePath: '/path/file.jpg',
        fileName: 'file.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024,
        width: 1920,
        height: 1080,
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        scannedAt: DateTime(2026, 1, 15),
      );

      repository.recordNewItem(item);

      final updatedItem = PartitionItem(
        localId: '123',
        fileHash: 'abc123',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        isFavorite: true,
      );

      repository.recordStateChange(
        localId: '123',
        operation: 'favorite_toggle',
        updatedItem: updatedItem,
      );

      final metadata = repository.getItemMetadata('123');
      expect(metadata!.isFavorite, isTrue);
    });

    test('recordUploadComplete updates Telegram metadata', () {
      final item = MediaItem(
        localId: '123',
        fileHash: 'abc123',
        filePath: '/path/file.jpg',
        fileName: 'file.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024,
        width: 1920,
        height: 1080,
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        scannedAt: DateTime(2026, 1, 15),
      );

      repository.recordNewItem(item);

      repository.recordUploadComplete(
        localId: '123',
        telegramMessageId: 'msg_456',
        telegramFileId: 'file_789',
      );

      final metadata = repository.getItemMetadata('123');
      expect(metadata!.telegramMessageId, 'msg_456');
      expect(metadata.telegramFileId, 'file_789');
      expect(metadata.backedUpAt, isNotNull);
    });

    test('recordDeletion removes item from metadata', () {
      final item = MediaItem(
        localId: '123',
        fileHash: 'abc123',
        filePath: '/path/file.jpg',
        fileName: 'file.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024,
        width: 1920,
        height: 1080,
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        scannedAt: DateTime(2026, 1, 15),
      );

      repository.recordNewItem(item);
      expect(repository.totalItems, 1);

      repository.recordDeletion(localId: '123', operation: 'delete');

      expect(repository.totalItems, 0);
    });

    test('getCurrentManifest returns null initially', () {
      expect(repository.getCurrentManifest(), isNull);
    });

    test('generateManifest creates manifest from current state', () async {
      final item = MediaItem(
        localId: '123',
        fileHash: 'abc123',
        filePath: '/path/file.jpg',
        fileName: 'file.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024,
        width: 1920,
        height: 1080,
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        scannedAt: DateTime(2026, 1, 15),
      );

      repository.recordNewItem(item);

      final manifest = await repository.generateManifest(
        deviceHash: 'test_device',
      );

      expect(manifest.totalMedia, 1);
      expect(manifest.deviceHash, 'test_device');
    });

    test('resolveConflict resolves local vs remote', () {
      final local = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 20),
      );
      final remote = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 15),
      );

      final resolved = repository.resolveConflict(local: local, remote: remote);

      expect(resolved, isNotNull);
      expect(resolved!.localId, '123');
    });

    test('getDirtyPartitions returns partition IDs', () {
      final item = MediaItem(
        localId: '123',
        fileHash: 'abc123',
        filePath: '/path/file.jpg',
        fileName: 'file.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024,
        width: 1920,
        height: 1080,
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        scannedAt: DateTime(2026, 1, 15),
      );

      repository.recordNewItem(item);

      final dirty = repository.getDirtyPartitions();
      expect(dirty.length, 1);
      expect(dirty.contains('2026/01'), isTrue);
    });

    test('getSyncStatus returns current sync status', () {
      final status = repository.getSyncStatus();
      expect(status.syncInProgress, isFalse);
      expect(status.pendingChangesCount, 0);
    });

    test('changeStream emits events on state changes', () async {
      final events = <MetadataChangeEvent>[];
      repository.changeStream.listen((event) {
        events.add(event);
      });

      final item = MediaItem(
        localId: '123',
        fileHash: 'abc123',
        filePath: '/path/file.jpg',
        fileName: 'file.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024,
        width: 1920,
        height: 1080,
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        scannedAt: DateTime(2026, 1, 15),
      );

      await repository.recordNewItem(item);

      expect(events.length, 1);
      expect(events[0].mediaItemId, '123');
      expect(events[0].operation, 'create');
    });
  });
}
