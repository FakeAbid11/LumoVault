import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/metadata/data/models/metadata_models.dart';
import 'package:lumovault/features/metadata/data/repositories/manifest_service.dart';

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

      await service.generateManifest(
        localMetadata: items,
        deviceHash: 'test_device',
      );

      final currentHash = service.getPartitionHash('2026/01');
      expect(currentHash, isNotNull);
      expect(service.hasPartitionChanged('2026/01', currentHash!), isFalse);
      expect(service.hasPartitionChanged('2026/01', 'different'), isTrue);
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
