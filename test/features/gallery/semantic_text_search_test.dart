import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/core/database/media_item_mapper.dart';
import 'package:lumovault/core/di/gallery_providers.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';
import 'package:lumovault/features/gallery/data/services/clip_embedding_service.dart';

/// Maps known queries to fixed 512-dim unit vectors so ranking is
/// hand-verifiable: 'cat' is pure e0, 'something else' is pure e1.
class _FakeTextEmbedder implements AiTextEmbedder {
  @override
  Future<void> initText() async {}

  @override
  bool get isTextReady => true;

  @override
  String? get textInitError => null;

  @override
  Future<List<double>?> embedText(String query) async {
    switch (query) {
      case 'cat':
        return [1.0, ...List<double>.filled(511, 0)]; // e0
      case 'something else':
        return [0.0, 1.0, ...List<double>.filled(510, 0)]; // e1
      default:
        return null;
    }
  }
}

class _NoopScanner implements MediaScannerService {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

List<double> _mixed(List<double> a, List<double> b, double weight) {
  final mixed = <double>[
    for (var i = 0; i < a.length; i++) a[i] * weight + b[i] * (1 - weight),
  ];
  final norm = math.sqrt(mixed.fold<double>(0, (s, v) => s + v * v));
  return mixed.map((v) => v / norm).toList();
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

void main() {
  late AppDatabase db;
  late GalleryRepository repository;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = GalleryRepository(
      scannerService: _NoopScanner(),
      mediaDao: db.mediaDao,
      faceDao: db.faceDao,
    );
    container = ProviderContainer(
      overrides: [
        galleryRepositoryProvider.overrideWithValue(repository),
        textEmbedderProvider.overrideWithValue(_FakeTextEmbedder()),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
  });

  test(
    'semantic search ranks by cosine similarity and skips hidden items',
    () async {
      await repository.hydrate();
      for (final id in ['exact', 'partial', 'unrelated', 'hidden']) {
        await db.mediaDao.upsert(_media(id).toCompanion());
      }
      await repository.hydrate();

      final e0 = await _FakeTextEmbedder().embedText('cat');
      final e1 = await _FakeTextEmbedder().embedText('something else');
      final mixed = _mixed(e0!, e1!, 0.6); // cosine 0.6 against e0

      // 'exact' = e0 (similarity 1.0), 'partial' = 0.6, 'unrelated' has no
      // embedding at all, 'hidden' is excluded from search entirely.
      await repository.updateClipEmbedding('exact', e0);
      await repository.updateClipEmbedding('partial', mixed);

      final results = await container
          .read(semanticTextSearchProvider('cat').future)
          .timeout(const Duration(seconds: 5));

      expect(results.map((i) => i.localId), ['exact', 'partial']);
      expect(results.map((i) => i.localId), isNot(contains('unrelated')));
      expect(results.map((i) => i.localId), isNot(contains('hidden')));

      // The 'something else' query ranks in the opposite order.
      final opposite = await container.read(
        semanticTextSearchProvider('something else').future,
      );
      expect(opposite.first.localId, 'partial');
    },
  );
}
