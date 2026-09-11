import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/core/database/media_item_mapper.dart';
import 'package:lumovault/core/di/database_providers.dart';
import 'package:lumovault/core/di/gallery_providers.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';
import 'package:lumovault/features/gallery/data/services/image_classifier_service.dart';
import 'package:lumovault/features/gallery/presentation/providers/ai_scan_provider.dart';
import 'package:photo_manager/photo_manager.dart';

/// Classifies everything as a cat, instantly — no ONNX, no platform.
class _InstantCatClassifier implements AiLabeler {
  @override
  Future<void> init() async {}

  @override
  bool get isReady => true;

  @override
  Future<List<String>> classify(AssetEntity asset) async => ['ai_cat'];
}

/// Classifies everything as a cat. The first classify() signals
/// [started] and then blocks until [gate] completes, so a test can issue
/// stop() deterministically mid-photo.
class _BlockingCatClassifier implements AiLabeler {
  _BlockingCatClassifier(this.started, this.gate);

  final Completer<void> started;
  final Completer<void> gate;

  @override
  Future<void> init() async {}

  @override
  bool get isReady => true;

  @override
  Future<List<String>> classify(AssetEntity asset) {
    if (!started.isCompleted) started.complete();
    return gate.future.then((_) => ['ai_cat']);
  }
}

class _NoopScanner implements MediaScannerService {
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
  }) async => const [];

  @override
  Future<Uint8List?> getThumbnail(String assetId) async => null;

  @override
  Future<File?> getFullFile(String assetId) async => null;

  @override
  Future<List<DeviceFolder>> getDeviceFolders() async => const [];

  @override
  Future<List<AssetEntity>> getFolderAssets(String pathId) async => const [];
}

MediaItem _media(String localId) => MediaItem(
  localId: localId,
  fileHash: 'h-$localId',
  filePath: '/p/$localId',
  fileName: '$localId.jpg',
  mimeType: 'image/jpeg',
  fileSize: 1,
  width: 1,
  height: 1,
  createdAt: DateTime(2026, 1, 1),
  modifiedAt: DateTime(2026, 1, 1),
  scannedAt: DateTime(2026, 1, 1),
);

AssetEntity _asset(int id) => AssetEntity(
  // photo_manager 3.x ids are strings; typeInt 1 == AssetType.image.
  id: '$id',
  typeInt: 1,
  width: 1,
  height: 1,
);

Future<GalleryRepository> _seedRepository(AppDatabase db) async {
  final repository = GalleryRepository(
    scannerService: _NoopScanner(),
    mediaDao: db.mediaDao,
    faceDao: db.faceDao,
  );
  await repository.hydrate();
  // Seed rows whose localIds match the fake device asset ids, so the scan
  // controller's labelAnyMediaItem(asset.id) updates these rows.
  for (final id in ['101', '102', '103']) {
    await db.mediaDao.upsert(_media(id).toCompanion());
  }
  // Second hydrate pulls the seeded rows into the in-memory read model.
  await repository.hydrate();
  return repository;
}

ProviderContainer _container(
  AppDatabase db,
  GalleryRepository repository, {
  AiLabeler? classifier,
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      galleryRepositoryProvider.overrideWithValue(repository),
      deviceAssetsProvider.overrideWith(
        (ref) => Future.value([_asset(101), _asset(102), _asset(103)]),
      ),
      imageClassifierProvider.overrideWithValue(
        classifier ?? _InstantCatClassifier(),
      ),
    ],
  );
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
  });

  test('labels unlabeled images, skips already-labeled ones', () async {
    final repository = await _seedRepository(db);
    await repository.labelAnyMediaItem('101', ['ai_dog']);
    final container = _container(db, repository);
    addTearDown(container.dispose);

    await container.read(aiScanControllerProvider.notifier).start();

    final state = container.read(aiScanControllerProvider);
    expect(state.running, false);
    expect(state.error, isNull);
    expect(state.completed, 2, reason: '101 was labeled up front');
    expect(repository.labeledLocalIds, containsAll(['102', '103']));
    expect(
      repository.searchMedia('cat').map((i) => i.localId),
      containsAll(['102', '103']),
    );
  });

  test('reports when everything is already labeled', () async {
    final repository = await _seedRepository(db);
    final container = _container(db, repository);
    addTearDown(container.dispose);

    // First run labels all three seeded images…
    await container.read(aiScanControllerProvider.notifier).start();
    expect(container.read(aiScanControllerProvider).error, isNull);

    // …so an immediate second run has nothing left to do.
    await container.read(aiScanControllerProvider.notifier).start();
    expect(
      container.read(aiScanControllerProvider).error,
      'All photos are already labeled.',
    );
  });

  test('stop() prevents further labeling after the current photo', () async {
    final repository = await _seedRepository(db);
    // The classifier signals when the first classify STARTS and blocks until
    // released — so stop() can be issued deterministically mid-photo.
    final firstClassifyStarted = Completer<void>();
    final releaseGate = Completer<void>();
    final classifier = _BlockingCatClassifier(
      firstClassifyStarted,
      releaseGate,
    );
    final container = _container(db, repository, classifier: classifier);
    addTearDown(container.dispose);

    final startFuture = container
        .read(aiScanControllerProvider.notifier)
        .start();
    await firstClassifyStarted.future.timeout(const Duration(seconds: 5));

    container.read(aiScanControllerProvider.notifier).stop();
    releaseGate.complete();
    await startFuture;

    final state = container.read(aiScanControllerProvider);
    expect(state.running, false);
    expect(state.completed, 1, reason: 'stopped before the second photo');
    expect(repository.labeledLocalIds.length, 1);
  });
}
