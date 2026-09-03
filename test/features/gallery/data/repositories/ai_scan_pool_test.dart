import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:lumovault/core/di/gallery_providers.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';

/// The AI scan pool used to be drawn from the repository's scanned records
/// only — which made AI search silently cover just backed-up photos, because
/// the scan (the thing that creates records) is the backup prerequisite. It
/// now draws from every device image and the scan creates records on demand.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _FakeGalleryRepository newRepo() => _FakeGalleryRepository();

  MediaItem item(
    String id, {
    List<String> aiLabels = const [],
    bool isHidden = false,
    bool isTrashed = false,
  }) => MediaItem(
    localId: id,
    fileHash: 'hash_$id',
    filePath: 'device://$id',
    fileName: 'photo_$id.jpg',
    mimeType: 'image/jpeg',
    fileSize: 1,
    width: 10,
    height: 10,
    createdAt: DateTime(2026, 1, 1),
    modifiedAt: DateTime(2026, 1, 1),
    scannedAt: DateTime(2026, 1, 1),
    status: MediaStatus.uploaded,
    aiLabels: aiLabels,
    isHidden: isHidden,
    isTrashed: isTrashed,
  );

  AssetEntity asset(String id, {bool video = false}) => AssetEntity(
    id: id,
    typeInt: video ? 2 : 1, // 1 = image, 2 = video in photo_manager.
    width: 10,
    height: 10,
  );

  ProviderContainer container(
    _FakeGalleryRepository repo,
    List<AssetEntity> assets,
  ) => ProviderContainer(
    overrides: [
      galleryRepositoryProvider.overrideWithValue(repo),
      deviceAssetsProvider.overrideWith((ref) => assets),
    ],
  );

  group('aiScanPoolProvider', () {
    test('includes never-scanned device images', () async {
      final c = container(newRepo(), [asset('a'), asset('b')]);
      addTearDown(c.dispose);

      final pool = await c.read(aiScanPoolProvider.future);

      expect(pool.map((a) => a.id), ['a', 'b']);
    });

    test('excludes labeled records but keeps unlabeled ones', () async {
      final repo = newRepo();
      await repo.mergeTelegramItems([
        item('labeled', aiLabels: ['ai_beach']),
        item('unlabeled'),
      ]);
      final c = container(repo, [
        asset('labeled'),
        asset('unlabeled'),
        asset('new'),
      ]);
      addTearDown(c.dispose);

      final pool = await c.read(aiScanPoolProvider.future);

      expect(pool.map((a) => a.id), ['unlabeled', 'new']);
    });

    test('excludes hidden and trashed records', () async {
      final repo = newRepo();
      await repo.mergeTelegramItems([
        item('hidden', isHidden: true),
        item('trashed', isTrashed: true),
      ]);
      final c = container(repo, [asset('hidden'), asset('trashed')]);
      addTearDown(c.dispose);

      final pool = await c.read(aiScanPoolProvider.future);

      expect(pool, isEmpty);
    });

    test('excludes videos (the classifier is image-only)', () async {
      final c = container(newRepo(), [asset('v', video: true)]);
      addTearDown(c.dispose);

      final pool = await c.read(aiScanPoolProvider.future);

      expect(pool, isEmpty);
    });
  });

  group('upsertFromAsset', () {
    test('returns the existing record without rebuilding', () async {
      final repo = newRepo();
      await repo.mergeTelegramItems([item('existing')]);

      final result = await repo.upsertFromAsset(asset('existing'));

      expect(result, isNotNull);
      expect(result!.localId, 'existing');
      expect(result.aiLabels, isEmpty);
    });

    test(
      'returns null for an asset the platform cannot resolve, and adds nothing',
      () async {
        final repo = newRepo();

        // Under the test binding the photo_manager platform channel has no
        // handler, so buildSingleItem cannot resolve the file — the contract
        // is to skip quietly rather than create a half-baked record.
        final result = await repo.upsertFromAsset(asset('unresolvable'));

        expect(result, isNull);
        expect(
          repo.mediaItems.where((i) => i.localId == 'unresolvable'),
          isEmpty,
        );
      },
    );
  });
}

class _FakeGalleryRepository extends GalleryRepository {
  _FakeGalleryRepository() : super(scannerService: _FakeScannerService());
}

class _FakeScannerService implements MediaScannerService {
  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<ScanResult> scanDevice({
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
  }) async => const ScanResult(
    mediaItems: [],
    folders: [],
    totalScanned: 0,
    newItems: 0,
    updatedItems: 0,
    duration: Duration.zero,
  );

  @override
  Future<List<AssetEntity>> listAllAssets({
    void Function(int loaded)? onProgress,
  }) async => const [];

  @override
  Future<Uint8List?> getThumbnail(String assetId) async => null;

  @override
  Future<File?> getFullFile(String assetId) async => null;

  @override
  Future<List<DeviceFolder>> getDeviceFolders() async => const [];
}
