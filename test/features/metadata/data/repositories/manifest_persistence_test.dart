import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/metadata/data/models/metadata_models.dart';
import 'package:lumovault/features/metadata/data/repositories/manifest_persistence.dart';
import 'package:lumovault/features/metadata/data/repositories/manifest_service.dart';

class _FakeManifestStore implements ManifestStore {
  Manifest? saved;
  int saveCount = 0;
  bool cleared = false;

  @override
  Future<Manifest?> load() async => saved;

  @override
  Future<void> save(Manifest manifest) async {
    saved = manifest;
    saveCount++;
  }

  @override
  Future<void> clear() async {
    saved = null;
    cleared = true;
  }
}

void main() {
  group('ManifestService persistence', () {
    test('generateManifest persists after the debounce', () async {
      final store = _FakeManifestStore();
      final service = ManifestService(
        store: store,
        persistDebounce: const Duration(milliseconds: 50),
      );
      addTearDown(service.dispose);

      await service.generateManifest(
        localMetadata: const [],
        deviceHash: 'test_device',
      );

      expect(store.saveCount, 0);

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(store.saveCount, 1);
      expect(store.saved!.deviceHash, 'test_device');
    });

    test('setManifest persists immediately on saveNow', () async {
      final store = _FakeManifestStore();
      final service = ManifestService(store: store);
      addTearDown(service.dispose);

      service.setManifest(Manifest.create(deviceHash: 'test_device'));
      await service.saveNow();

      expect(store.saveCount, 1);
      expect(store.saved!.deviceHash, 'test_device');
    });

    test('a reloaded service restores the baseline', () async {
      final store = _FakeManifestStore();
      final first = ManifestService(store: store);
      addTearDown(first.dispose);
      await first.generateManifest(
        localMetadata: [
          PartitionItem(
            localId: '1',
            fileHash: 'hash1',
            createdAt: DateTime(2026, 1, 15),
            modifiedAt: DateTime(2026, 1, 15),
          ),
        ],
        deviceHash: 'test_device',
      );
      await first.saveNow();

      // Simulate an app restart: the persisted manifest restores both the
      // content and the sync baseline.
      final restarted = ManifestService(store: store);
      addTearDown(restarted.dispose);
      final loaded = await store.load();
      restarted.setManifest(loaded!);

      expect(restarted.getCurrentManifest(), isNotNull);
      expect(restarted.getPartitionHash('2026/01'), isNotNull);
    });

    test('no store means no persistence and no timers', () async {
      final service = ManifestService();
      addTearDown(service.dispose);

      await service.generateManifest(
        localMetadata: const [],
        deviceHash: 'test_device',
      );
      await service.saveNow();
      expect(service.getCurrentManifest(), isNotNull);
    });
  });
}
