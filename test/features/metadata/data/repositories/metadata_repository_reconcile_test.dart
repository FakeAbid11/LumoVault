import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/metadata/data/models/metadata_models.dart';
import 'package:lumovault/features/metadata/data/repositories/conflict_resolver.dart';
import 'package:lumovault/features/metadata/data/repositories/manifest_service.dart';
import 'package:lumovault/features/metadata/data/repositories/metadata_repository.dart';
import 'package:lumovault/features/metadata/data/repositories/partition_service.dart';
import 'package:lumovault/features/metadata/data/repositories/search_index_service.dart';
import 'package:lumovault/features/metadata/data/repositories/sync_service.dart';

/// Exercises the pull half of two-way sync — [MetadataRepository]
/// .reconcileFromTelegram — with injected fake download callbacks, no TDLib.
void main() {
  group('MetadataRepository.reconcileFromTelegram', () {
    late MetadataRepository repository;
    late ManifestService manifestService;
    late PartitionService partitionService;
    late SearchIndexService searchIndexService;
    late SyncService syncService;

    setUp(() {
      manifestService = ManifestService();
      partitionService = PartitionService();
      searchIndexService = SearchIndexService();
      syncService = SyncService();
      repository = MetadataRepository(
        manifestService: manifestService,
        partitionService: partitionService,
        searchIndexService: searchIndexService,
        syncService: syncService,
        conflictResolver: ConflictResolver(),
      );
    });

    tearDown(() {
      repository.dispose();
      manifestService.dispose();
      partitionService.dispose();
      searchIndexService.dispose();
      syncService.dispose();
    });

    MediaItem mediaItem(String id, {DateTime? modified}) => MediaItem(
      localId: id,
      fileHash: 'hash_$id',
      filePath: '/path/$id.jpg',
      fileName: '$id.jpg',
      mimeType: 'image/jpeg',
      fileSize: 1024,
      width: 100,
      height: 100,
      createdAt: DateTime(2026, 1, 15),
      modifiedAt: modified ?? DateTime(2026, 1, 15),
      scannedAt: DateTime(2026, 1, 15),
    );

    test('downloads only partitions whose remote hash differs', () async {
      // Seed one local item -> one local partition (2026/01).
      await repository.recordNewItem(mediaItem('a'));
      final localManifest = await repository.generateManifest(
        deviceHash: 'device',
      );
      final unchangedChunk = localManifest.chunks.firstWhere(
        (c) => c.id == '2026/01',
      );

      // Remote manifest: the 2026/01 chunk is byte-identical (must be skipped),
      // plus a 2099/01 chunk that does not exist locally (must be pulled).
      final remoteManifest = Manifest(
        created: DateTime.now().toUtc(),
        deviceHash: 'device',
        lastSync: DateTime.now().toUtc(),
        chunks: [
          unchangedChunk,
          const ManifestChunk(id: '2099/01', count: 1, hash: 'different'),
        ],
      );

      final requested = <String>[];
      await repository.reconcileFromTelegram(
        downloadManifest: () async => remoteManifest,
        downloadPartition: (id) async {
          requested.add(id);
          // Return an empty partition for the changed id; content doesn't
          // matter for this assertion.
          return MetadataPartition(
            id: id,
            periodStart: DateTime(2099),
            periodEnd: DateTime(2099, 2),
            lastModified: DateTime.now().toUtc(),
          );
        },
      );

      expect(requested, ['2099/01']);
    });

    test('applies a remote tombstone as a local deletion', () async {
      await repository.recordNewItem(mediaItem('a'));

      // Remote says item 'a' was deleted, with a newer modifiedAt so LWW picks
      // the tombstone.
      final tombstone = PartitionItem(
        localId: 'a',
        fileHash: 'hash_a',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 2, 1),
        isDeleted: true,
        deletedAt: DateTime(2026, 2, 1),
      );
      final remotePartition = MetadataPartition(
        id: '2026/01',
        periodStart: DateTime(2026),
        periodEnd: DateTime(2026, 2),
        items: [tombstone],
        lastModified: DateTime(2026, 2, 1),
      );
      final remoteManifest = Manifest(
        created: DateTime.now().toUtc(),
        deviceHash: 'device',
        lastSync: DateTime.now().toUtc(),
        chunks: [
          ManifestChunk(
            id: '2026/01',
            count: 1,
            hash: remotePartition.computeHash(),
          ),
        ],
      );

      final reflectedDeletions = <String>[];
      repository.onReconcileApplied = (upserts, deletions) async {
        reflectedDeletions.addAll(deletions);
      };

      final applied = await repository.reconcileFromTelegram(
        downloadManifest: () async => remoteManifest,
        downloadPartition: (id) async => remotePartition,
      );

      expect(applied, 1);
      expect(reflectedDeletions, ['a']);
      final md = repository.getItemMetadata('a');
      expect(md, isNotNull);
      expect(md!.isDeleted, isTrue);
    });

    test('a null remote manifest is a no-op', () async {
      await repository.recordNewItem(mediaItem('a'));
      final applied = await repository.reconcileFromTelegram(
        downloadManifest: () async => null,
        downloadPartition: (id) async => null,
      );
      expect(applied, 0);
      expect(repository.getItemMetadata('a'), isNotNull);
    });

    test('an old pre-tombstone manifest reconciles with no deletions', () async {
      // A channel written by the push-only version: schemaVersion 1, and its
      // partition items carry no isDeleted/deletedAt (they parse back as the
      // false/null defaults). Reconciling such a manifest must never produce a
      // deletion — there are simply no tombstones to apply.
      await repository.recordNewItem(mediaItem('a'));

      // Remote-only item 'b', not deleted, in a partition that does not exist
      // locally so it is guaranteed to download and be adopted.
      final legacyItem = PartitionItem(
        localId: 'b',
        fileHash: 'hash_b',
        createdAt: DateTime(2099, 3, 3),
        modifiedAt: DateTime(2099, 3, 3),
        // isDeleted defaults false, deletedAt null — as an old channel would.
      );
      final legacyPartition = MetadataPartition(
        id: '2099/03',
        periodStart: DateTime(2099, 3),
        periodEnd: DateTime(2099, 4),
        items: [legacyItem],
        lastModified: DateTime(2099, 3, 3),
      );
      final legacyManifest = Manifest(
        schemaVersion: 1,
        created: DateTime.now().toUtc(),
        deviceHash: 'legacy_device',
        lastSync: DateTime.now().toUtc(),
        chunks: [
          ManifestChunk(
            id: '2099/03',
            count: 1,
            hash: legacyPartition.computeHash(),
          ),
        ],
      );

      final reflectedUpserts = <String>[];
      final reflectedDeletions = <String>[];
      repository.onReconcileApplied = (upserts, deletions) async {
        reflectedUpserts.addAll(upserts.map((i) => i.localId));
        reflectedDeletions.addAll(deletions);
      };

      final applied = await repository.reconcileFromTelegram(
        downloadManifest: () async => legacyManifest,
        downloadPartition: (id) async => legacyPartition,
      );

      expect(applied, 1);
      expect(reflectedUpserts, ['b']);
      expect(reflectedDeletions, isEmpty);
      // Both items live; nothing was tombstoned.
      expect(repository.getItemMetadata('a')!.isDeleted, isFalse);
      expect(repository.getItemMetadata('b')!.isDeleted, isFalse);
    });
  });
}
