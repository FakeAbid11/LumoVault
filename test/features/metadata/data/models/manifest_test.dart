import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/metadata/data/models/manifest.dart';

void main() {
  group('Manifest', () {
    test('create generates valid manifest with defaults', () {
      final manifest = Manifest.create(deviceHash: 'test_hash_123');

      expect(manifest.app, 'lumovault');
      expect(manifest.schemaVersion, 1);
      expect(manifest.deviceHash, 'test_hash_123');
      expect(manifest.totalMedia, 0);
      expect(manifest.totalSizeBytes, 0);
      expect(manifest.chunks, isEmpty);
    });

    test('toJsonString produces valid JSON', () {
      final manifest = Manifest.create(deviceHash: 'test_hash');
      final json = manifest.toJsonString();

      expect(json, isNotEmpty);
      expect(json, contains('"app":"lumovault"'));
      expect(json, contains('"schema_version":1'));
      expect(json, contains('"device_hash":"test_hash"'));
    });

    test('fromJsonString parses valid JSON', () {
      final original = Manifest.create(deviceHash: 'test_hash');
      final json = original.toJsonString();

      final parsed = Manifest.fromJsonString(json);

      expect(parsed, isNotNull);
      expect(parsed!.app, 'lumovault');
      expect(parsed.schemaVersion, 1);
      expect(parsed.deviceHash, 'test_hash');
    });

    test('fromJsonString returns null for invalid JSON', () {
      final parsed = Manifest.fromJsonString('not valid json');
      expect(parsed, isNull);
    });

    test('fromJsonString returns null for empty string', () {
      final parsed = Manifest.fromJsonString('');
      expect(parsed, isNull);
    });

    test('copyWith creates updated copy', () {
      final original = Manifest.create(deviceHash: 'hash1');
      final updated = original.copyWith(
        totalMedia: 100,
        totalSizeBytes: 1024 * 1024,
      );

      expect(updated.totalMedia, 100);
      expect(updated.totalSizeBytes, 1024 * 1024);
      expect(updated.deviceHash, 'hash1');
      expect(original.totalMedia, 0);
    });

    test('isCompatibleWith returns true for same or newer version', () {
      final manifest = Manifest.create(deviceHash: 'hash');
      expect(manifest.isCompatibleWith(1), isTrue);
      expect(manifest.isCompatibleWith(2), isTrue);
      expect(manifest.isCompatibleWith(0), isFalse);
    });

    test('equality based on schema, device, media count, size', () {
      final a = Manifest.create(
        deviceHash: 'hash',
      ).copyWith(totalMedia: 10, totalSizeBytes: 100);
      final b = Manifest.create(
        deviceHash: 'hash',
      ).copyWith(totalMedia: 10, totalSizeBytes: 100);
      final c = Manifest.create(
        deviceHash: 'hash',
      ).copyWith(totalMedia: 20, totalSizeBytes: 100);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('computeDeviceHash produces deterministic hash', () {
      final hash1 = Manifest.computeDeviceHash('device123');
      final hash2 = Manifest.computeDeviceHash('device123');
      final hash3 = Manifest.computeDeviceHash('device456');

      expect(hash1, equals(hash2));
      expect(hash1, isNot(equals(hash3)));
    });

    test('manifest with chunks preserves chunk data', () {
      final chunks = [
        const ManifestChunk(id: '2026/01', count: 500, hash: 'abc'),
        const ManifestChunk(id: '2026/02', count: 300, hash: 'def'),
      ];
      final manifest = Manifest(
        created: DateTime.now().toUtc(),
        deviceHash: 'hash',
        lastSync: DateTime.now().toUtc(),
        chunks: chunks,
      );

      final json = manifest.toJsonString();
      final parsed = Manifest.fromJsonString(json);

      expect(parsed, isNotNull);
      expect(parsed!.chunks.length, 2);
      expect(parsed.chunks[0].id, '2026/01');
      expect(parsed.chunks[1].count, 300);
    });
  });

  group('ManifestChunk', () {
    test('toJson produces correct JSON', () {
      const chunk = ManifestChunk(id: '2026/01', count: 100, hash: 'abc123');
      final json = chunk.toJson();

      expect(json['id'], '2026/01');
      expect(json['count'], 100);
      expect(json['hash'], 'abc123');
    });

    test('fromJson parses correct JSON', () {
      const chunk = ManifestChunk(id: '2026/01', count: 100, hash: 'abc123');
      final json = chunk.toJson();
      final parsed = ManifestChunk.fromJson(json);

      expect(parsed.id, '2026/01');
      expect(parsed.count, 100);
      expect(parsed.hash, 'abc123');
    });

    test('copyWith creates updated copy', () {
      const original = ManifestChunk(id: '2026/01', count: 100, hash: 'abc');
      final updated = original.copyWith(count: 200);

      expect(updated.count, 200);
      expect(updated.id, '2026/01');
      expect(original.count, 100);
    });

    test('equality based on id, count, hash', () {
      const a = ManifestChunk(id: '2026/01', count: 100, hash: 'abc');
      const b = ManifestChunk(id: '2026/01', count: 100, hash: 'abc');
      const c = ManifestChunk(id: '2026/01', count: 200, hash: 'abc');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
