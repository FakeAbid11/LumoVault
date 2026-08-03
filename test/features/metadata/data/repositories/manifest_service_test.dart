import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/metadata/data/models/metadata_models.dart';
import 'package:lumovault/features/metadata/data/repositories/manifest_service.dart';
import 'package:lumovault/features/metadata/data/repositories/partition_service.dart';

void main() {
  group('ManifestService', () {
    late ManifestService service;

    setUp(() {
      service = ManifestService();
    });

    tearDown(() {
      service.dispose();
    });

    test('getCurrentManifest returns null initially', () {
      expect(service.getCurrentManifest(), isNull);
    });

    test('setManifest stores manifest', () {
      final manifest = Manifest.create(deviceHash: 'test_hash');
      service.setManifest(manifest);

      expect(service.getCurrentManifest(), equals(manifest));
    });

    test('getPartitionHash returns null for unknown partition', () {
      expect(service.getPartitionHash('2026/01'), isNull);
    });

    test('getPartitionHash returns hash after setManifest', () {
      final chunks = [
        const ManifestChunk(id: '2026/01', count: 100, hash: 'abc'),
      ];
      final manifest = Manifest(
        created: DateTime.now().toUtc(),
        deviceHash: 'hash',
        lastSync: DateTime.now().toUtc(),
        chunks: chunks,
      );
      service.setManifest(manifest);

      expect(service.getPartitionHash('2026/01'), 'abc');
    });

    test('generateManifest creates manifest from metadata', () async {
      final items = [
        PartitionItem(
          localId: '1',
          fileHash: 'hash1',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
          fileSize: 1024,
        ),
        PartitionItem(
          localId: '2',
          fileHash: 'hash2',
          createdAt: DateTime(2026, 1, 20),
          modifiedAt: DateTime(2026, 1, 20),
          fileSize: 2048,
        ),
      ];

      final manifest = await service.generateManifest(
        localMetadata: items,
        deviceHash: 'test_device',
      );

      expect(manifest.app, 'lumovault');
      expect(manifest.schemaVersion, 1);
      expect(manifest.deviceHash, 'test_device');
      expect(manifest.totalMedia, 2);
      expect(manifest.totalSizeBytes, 3072);
      expect(manifest.chunks.length, 1);
      expect(manifest.chunks[0].id, '2026/01');
      expect(manifest.chunks[0].count, 2);
    });

    test('generateManifest groups items by month', () async {
      final items = [
        PartitionItem(
          localId: '1',
          fileHash: 'hash1',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
        ),
        PartitionItem(
          localId: '2',
          fileHash: 'hash2',
          createdAt: DateTime(2026, 2, 10),
          modifiedAt: DateTime(2026, 2, 10),
        ),
        PartitionItem(
          localId: '3',
          fileHash: 'hash3',
          createdAt: DateTime(2026, 2, 20),
          modifiedAt: DateTime(2026, 2, 20),
        ),
      ];

      final manifest = await service.generateManifest(
        localMetadata: items,
        deviceHash: 'test_device',
      );

      expect(manifest.chunks.length, 2);
      expect(manifest.chunks[0].id, '2026/01');
      expect(manifest.chunks[0].count, 1);
      expect(manifest.chunks[1].id, '2026/02');
      expect(manifest.chunks[1].count, 2);
    });

    test('hasPartitionChanged detects changes', () async {
      final items = [
        PartitionItem(
          localId: '1',
          fileHash: 'hash1',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
        ),
      ];

      final manifest = await service.generateManifest(
        localMetadata: items,
        deviceHash: 'test_device',
      );
      // setManifest is the legitimate baseline-advancing path (it is what a
      // restore or a freshly loaded remote manifest goes through).
      service.setManifest(manifest);

      // Recompute the hash from an independent service so the comparison is
      // against a freshly derived digest, not the value already cached here.
      final other = ManifestService();
      addTearDown(other.dispose);
      final recomputed = await other.generateManifest(
        localMetadata: items,
        deviceHash: 'test_device',
      );

      expect(service.getPartitionHash('2026/01'), isNotNull);
      expect(
        service.hasPartitionChanged('2026/01', recomputed.chunks[0].hash),
        isFalse,
      );
      expect(service.hasPartitionChanged('2026/01', 'different'), isTrue);
      expect(service.hasPartitionChanged('2026/02', 'anything'), isTrue);
    });

    test('partition hashes are deterministic across instances', () async {
      List<PartitionItem> buildItems() => [
        PartitionItem(
          localId: '1',
          fileHash: 'hash1',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
          fileSize: 1024,
        ),
        PartitionItem(
          localId: '2',
          fileHash: 'hash2',
          createdAt: DateTime(2026, 1, 20),
          modifiedAt: DateTime(2026, 1, 20),
          fileSize: 2048,
        ),
      ];

      final first = ManifestService();
      addTearDown(first.dispose);
      final second = ManifestService();
      addTearDown(second.dispose);

      final a = await first.generateManifest(
        localMetadata: buildItems(),
        deviceHash: 'test_device',
      );
      final b = await second.generateManifest(
        localMetadata: buildItems(),
        deviceHash: 'test_device',
      );

      expect(a.chunks.single.hash, equals(b.chunks.single.hash));
      // A digest, not an identity hashCode.
      expect(a.chunks.single.hash, hasLength(64));
      expect(a.chunks.single.hash, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('partition hash ignores item ordering', () async {
      final items = [
        PartitionItem(
          localId: '1',
          fileHash: 'hash1',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
        ),
        PartitionItem(
          localId: '2',
          fileHash: 'hash2',
          createdAt: DateTime(2026, 1, 20),
          modifiedAt: DateTime(2026, 1, 20),
        ),
      ];

      final forward = ManifestService();
      addTearDown(forward.dispose);
      final reversed = ManifestService();
      addTearDown(reversed.dispose);

      final a = await forward.generateManifest(
        localMetadata: items,
        deviceHash: 'test_device',
      );
      final b = await reversed.generateManifest(
        localMetadata: items.reversed.toList(),
        deviceHash: 'test_device',
      );

      expect(a.chunks.single.hash, equals(b.chunks.single.hash));
    });

    test('partition hash changes when a tracked field changes', () async {
      final base = PartitionItem(
        localId: '1',
        fileHash: 'hash1',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
      );

      Future<String> hashOf(PartitionItem item) async {
        final s = ManifestService();
        addTearDown(s.dispose);
        final manifest = await s.generateManifest(
          localMetadata: [item],
          deviceHash: 'test_device',
        );
        return manifest.chunks.single.hash;
      }

      final baseline = await hashOf(base);

      expect(await hashOf(base.copyWith(fileHash: 'hash2')), isNot(baseline));
      expect(await hashOf(base.copyWith(isFavorite: true)), isNot(baseline));
      expect(await hashOf(base.copyWith(isHidden: true)), isNot(baseline));
      expect(await hashOf(base.copyWith(isArchived: true)), isNot(baseline));
      expect(await hashOf(base.copyWith(isTrashed: true)), isNot(baseline));
      expect(
        await hashOf(base.copyWith(modifiedAt: DateTime(2026, 1, 16))),
        isNot(baseline),
      );
    });

    test(
      'manifest chunk hash matches the partition\'s own computeHash',
      () async {
        // The manifest and MetadataPartition used to hash items with two
        // separate implementations: this one sorted the per-item records and
        // delimited fields with control characters, the partition's did
        // neither. Every hash comparison between them therefore reported a
        // difference, so getDirtyPartitionIds called every partition dirty even
        // when nothing had changed. They must stay byte-identical.
        //
        // Deliberately built out of chronological order — if either side ever
        // stops sorting, this catches it.
        final items = [
          PartitionItem(
            localId: '2',
            fileHash: 'hash2',
            createdAt: DateTime(2026, 1, 20),
            modifiedAt: DateTime(2026, 1, 20),
          ),
          PartitionItem(
            localId: '1',
            fileHash: 'hash1',
            createdAt: DateTime(2026, 1, 15),
            modifiedAt: DateTime(2026, 1, 15),
          ),
        ];

        final partitionService = PartitionService();
        addTearDown(partitionService.dispose);
        for (final item in items) {
          partitionService.upsertItem(item);
        }

        final manifest = await service.generateManifest(
          localMetadata: items,
          deviceHash: 'test_device',
        );

        expect(
          manifest.chunks.single.hash,
          equals(partitionService.getPartition('2026/01')!.computeHash()),
        );
      },
    );

    test('recordSyncedPartitions makes the synced partitions clean', () async {
      final partitionService = PartitionService();
      addTearDown(partitionService.dispose);

      partitionService.upsertItem(
        PartitionItem(
          localId: '1',
          fileHash: 'hash1',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
        ),
      );

      // Nothing synced yet: the partition has no recorded hash, so it's dirty.
      expect(
        partitionService.getDirtyPartitionIds(
          manifestHashes: service.partitionHashes,
        ),
        ['2026/01'],
      );

      service.setManifest(Manifest.create(deviceHash: 'test'));
      service.recordSyncedPartitions(
        partitions: partitionService.getAllPartitions(),
        syncTime: DateTime(2026, 2),
      );

      // After recording, an unchanged partition must not be re-uploaded.
      // Without this the "incremental" sync re-sent the user's entire
      // metadata history on every single run.
      expect(
        partitionService.getDirtyPartitionIds(
          manifestHashes: service.partitionHashes,
        ),
        isEmpty,
      );

      // A real edit makes it dirty again.
      partitionService.upsertItem(
        PartitionItem(
          localId: '1',
          fileHash: 'hash1',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
          isFavorite: true,
        ),
      );
      expect(
        partitionService.getDirtyPartitionIds(
          manifestHashes: service.partitionHashes,
        ),
        ['2026/01'],
      );
    });

    test('generateManifest does not advance the sync baseline', () async {
      // Regenerating the manifest must describe current state without
      // pretending everything was uploaded: the baseline only advances via
      // recordSyncedPartitions (or setManifest). An earlier version wrote
      // the freshly computed hashes into partitionHashes here, so a change
      // flushed by the debounced queue made every partition look clean and
      // syncToTelegram re-uploaded nothing.
      final partitionService = PartitionService();
      addTearDown(partitionService.dispose);
      partitionService.upsertItem(
        PartitionItem(
          localId: '1',
          fileHash: 'hash1',
          createdAt: DateTime(2026, 1, 15),
          modifiedAt: DateTime(2026, 1, 15),
        ),
      );

      await service.generateManifest(
        localMetadata: partitionService
            .getAllPartitions()
            .expand((p) => p.items)
            .toList(),
        deviceHash: 'test_device',
      );

      // Nothing has been uploaded: the partition must still be dirty.
      expect(
        partitionService.getDirtyPartitionIds(
          manifestHashes: service.partitionHashes,
        ),
        ['2026/01'],
      );

      // Only a recorded upload marks it clean.
      service.setManifest(Manifest.create(deviceHash: 'test_device'));
      service.recordSyncedPartitions(
        partitions: partitionService.getAllPartitions(),
        syncTime: DateTime(2026, 2),
      );
      expect(
        partitionService.getDirtyPartitionIds(
          manifestHashes: service.partitionHashes,
        ),
        isEmpty,
      );
    });

    test('updateAfterSync merges chunks instead of replacing them', () {
      // An incremental sync only uploads the dirty partitions; replacing the
      // whole chunk set would drop every unchanged partition from the
      // manifest sent to Telegram and shrink totalMedia to just the
      // recently-changed items.
      final manifest = Manifest(
        created: DateTime(2026, 1, 1).toUtc(),
        deviceHash: 'test',
        lastSync: DateTime(2026, 1, 1).toUtc(),
        chunks: const [
          ManifestChunk(id: '2026/01', count: 1, hash: 'a'),
          ManifestChunk(id: '2026/02', count: 1, hash: 'b'),
        ],
      );
      service.setManifest(manifest);

      service.updateAfterSync(
        updatedChunks: const [
          ManifestChunk(id: '2026/01', count: 2, hash: 'a2'),
        ],
        syncTime: DateTime(2026, 2).toUtc(),
      );

      final current = service.getCurrentManifest()!;
      expect(current.chunks, hasLength(2));
      expect(current.chunks.firstWhere((c) => c.id == '2026/01').hash, 'a2');
      expect(current.chunks.firstWhere((c) => c.id == '2026/01').count, 2);
      // Untouched partition keeps its chunk.
      expect(current.chunks.firstWhere((c) => c.id == '2026/02').hash, 'b');
      expect(current.totalMedia, 3);
      // Baseline advances only for the uploaded partition.
      expect(service.getPartitionHash('2026/01'), 'a2');
      expect(service.getPartitionHash('2026/02'), 'b');
    });

    test('toJsonString returns current manifest JSON', () {
      final manifest = Manifest.create(deviceHash: 'test');
      service.setManifest(manifest);

      final json = service.toJsonString();
      expect(json, isNotNull);
      expect(json, contains('lumovault'));
    });

    test('parseManifest returns manifest from JSON', () {
      final manifest = Manifest.create(deviceHash: 'test');
      final json = manifest.toJsonString();

      final parsed = service.parseManifest(json);
      expect(parsed, isNotNull);
      expect(parsed!.deviceHash, 'test');
    });
  });
}
