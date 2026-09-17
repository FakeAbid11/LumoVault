import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/metadata/data/models/manifest.dart';
import 'package:lumovault/features/metadata/data/models/metadata_models.dart';
import 'package:lumovault/features/metadata/data/repositories/conflict_resolver.dart';
import 'package:lumovault/features/metadata/data/repositories/manifest_persistence.dart';
import 'package:lumovault/features/metadata/data/repositories/manifest_service.dart';
import 'package:lumovault/features/metadata/data/repositories/metadata_repository.dart';
import 'package:lumovault/features/metadata/data/repositories/partition_persistence.dart';
import 'package:lumovault/features/metadata/data/repositories/partition_service.dart';
import 'package:lumovault/features/metadata/data/repositories/search_index_service.dart';
import 'package:lumovault/features/metadata/data/repositories/sync_service.dart';

/// In-memory [ManifestStore] so the persist→restart round trip can be tested
/// without a filesystem.
class _MemoryManifestStore implements ManifestStore {
  Manifest? _manifest;

  @override
  Future<Manifest?> load() async => _manifest;

  @override
  Future<void> save(Manifest manifest) async => _manifest = manifest;

  @override
  Future<void> clear() async => _manifest = null;
}

/// In-memory [PartitionStore].
class _MemoryPartitionStore implements PartitionStore {
  List<MetadataPartition> _partitions = const [];

  @override
  Future<List<MetadataPartition>> load() async => _partitions;

  @override
  Future<void> save(List<MetadataPartition> partitions) async =>
      _partitions = List.of(partitions);

  @override
  Future<void> clear() async => _partitions = const [];
}

MediaItem _item(String localId, {DateTime? createdAt}) {
  final at = createdAt ?? DateTime(2026, 3, 15);
  return MediaItem(
    localId: localId,
    fileHash: 'hash-$localId',
    filePath: '/path/$localId.jpg',
    fileName: '$localId.jpg',
    mimeType: 'image/jpeg',
    fileSize: 1024,
    width: 1920,
    height: 1080,
    createdAt: at,
    modifiedAt: at,
    scannedAt: at,
  );
}

/// The stores survive the repository: they are what a fresh process would see
/// on disk. Both services are rebuilt on the SAME stores, exactly as the
/// provider graph constructs them against the on-disk file stores.
void main() {
  group('metadata persistence round trip', () {
    late _MemoryManifestStore manifestStore;
    late _MemoryPartitionStore partitionStore;

    setUp(() {
      manifestStore = _MemoryManifestStore();
      partitionStore = _MemoryPartitionStore();
    });

    MetadataRepository buildRepository() {
      final manifestService = ManifestService(store: manifestStore);
      final partitionService = PartitionService(store: partitionStore);
      final repository = MetadataRepository(
        manifestService: manifestService,
        partitionService: partitionService,
        searchIndexService: SearchIndexService(),
        syncService: SyncService(),
        conflictResolver: ConflictResolver(),
      );
      return repository;
    }

    test('a restart rehydrates layer 1 from the persisted partitions', () async {
      // First "process": record an item and force the stores to disk.
      final first = buildRepository();
      await first.initialize();
      first.recordNewItem(_item('100'));
      await first.partitionService.saveNow();
      await first.generateManifest(deviceHash: 'device-1');
      await first.manifestService.saveNow();
      first.dispose();

      // Fresh repository on the same stores — a cold start.
      final second = buildRepository();
      await second.initialize();

      expect(second.totalItems, 1, reason: 'layer 1 must hydrate from disk');
      expect(second.getItemMetadata('100'), isNotNull);
      expect(second.partitionService.partitionCount, greaterThan(0));
      second.dispose();
    });

    test('a restart restores the sync baseline, so nothing is dirty', () async {
      final first = buildRepository();
      await first.initialize();
      first.recordNewItem(_item('101'));
      await first.recordUploadComplete(
        localId: '101',
        telegramMessageId: '999',
        telegramFileId: 'file-999',
      );
      // Record the synced baseline the way a successful upload does: generate
      // the manifest, then advance the baseline to the partition hashes.
      await first.generateManifest(deviceHash: 'device-1');
      first.manifestService.recordSyncedPartitions(
        partitions: first.partitionService.getAllPartitions(),
        syncTime: DateTime.utc(2026, 3, 15),
      );
      await first.partitionService.saveNow();
      await first.manifestService.saveNow();
      first.dispose();

      final second = buildRepository();
      await second.initialize();

      // The baseline is restored, so an unchanged partition set is NOT dirty.
      expect(
        second.getDirtyPartitions(),
        isEmpty,
        reason:
            'Without loading the persisted baseline, every launch reports all '
            'partitions dirty and re-uploads the full metadata history.',
      );
      second.dispose();
    });

    test('a genuine change after a restart is still detected as dirty', () async {
      // Establish a fully-synced baseline (nothing dirty).
      final first = buildRepository();
      await first.initialize();
      first.recordNewItem(_item('102'));
      await first.generateManifest(deviceHash: 'device-1');
      first.manifestService.recordSyncedPartitions(
        partitions: first.partitionService.getAllPartitions(),
        syncTime: DateTime.utc(2026, 3, 15),
      );
      await first.partitionService.saveNow();
      await first.manifestService.saveNow();
      first.dispose();

      // Cold start with a restored baseline.
      final second = buildRepository();
      await second.initialize();
      expect(second.getDirtyPartitions(), isEmpty, reason: 'baseline restored');

      // A real edit must still move the partition off the baseline — the whole
      // point of loading the baseline is precision, not suppression.
      final existing = second.getItemMetadata('102')!;
      second.recordStateChange(
        localId: '102',
        operation: 'favorite_toggle',
        updatedItem: existing.copyWith(isFavorite: true),
      );
      expect(
        second.getDirtyPartitions(),
        isNotEmpty,
        reason: 'a post-restart edit must be detected as dirty',
      );
      second.dispose();
    });
  });
}
