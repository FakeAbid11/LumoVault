import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';

/// Minimal scanner: [GalleryRepository.scanDevice] is the supported way to
/// seed the in-memory read model, and it only calls `scanDevice` on the
/// service. Everything else falls through to [Fake.noSuchMethod].
class _FakeScanner extends Fake implements MediaScannerService {
  _FakeScanner(this.items);

  final List<MediaItem> items;

  @override
  Future<ScanResult> scanDevice({
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
  }) async {
    return ScanResult(
      mediaItems: items,
      folders: const <DeviceFolder>[],
      totalScanned: items.length,
      newItems: items.length,
      updatedItems: 0,
      duration: Duration.zero,
    );
  }
}

MediaItem _item({
  required String localId,
  required String fileHash,
  bool isHidden = false,
  bool isTrashed = false,
}) {
  return MediaItem(
    localId: localId,
    fileHash: fileHash,
    filePath: '/photos/$localId.jpg',
    fileName: '$localId.jpg',
    mimeType: 'image/jpeg',
    fileSize: 1000,
    width: 100,
    height: 100,
    createdAt: DateTime(2026, 7, 14),
    modifiedAt: DateTime(2026, 7, 14),
    scannedAt: DateTime(2026, 7, 14),
    isHidden: isHidden,
    isTrashed: isTrashed,
  );
}

Future<GalleryRepository> _repositoryWith(List<MediaItem> items) async {
  final repository = GalleryRepository(scannerService: _FakeScanner(items));
  await repository.scanDevice();
  return repository;
}

void main() {
  group('getDuplicateGroups', () {
    test(
      'keeps every equal-size group (regression: SplayTreeMap collapse)',
      () async {
        // Sizes 3 / 2 / 2. With the old size-comparator SplayTreeMap the two
        // 2-member groups were "equal keys" and only one survived.
        final repository = await _repositoryWith([
          _item(localId: 'a1', fileHash: 'hashA'),
          _item(localId: 'a2', fileHash: 'hashA'),
          _item(localId: 'a3', fileHash: 'hashA'),
          _item(localId: 'b1', fileHash: 'hashB'),
          _item(localId: 'b2', fileHash: 'hashB'),
          _item(localId: 'c1', fileHash: 'hashC'),
          _item(localId: 'c2', fileHash: 'hashC'),
        ]);

        final groups = repository.getDuplicateGroups();
        expect(groups, hasLength(3));
        expect(groups.map((g) => g.length).toList(), [3, 2, 2]);
        final hashes = groups.map((g) => g.first.fileHash).toSet();
        expect(hashes, {'hashA', 'hashB', 'hashC'});
      },
    );

    test('orders groups by size then hash for stable output', () async {
      final repository = await _repositoryWith([
        _item(localId: 'b1', fileHash: 'hashB'),
        _item(localId: 'b2', fileHash: 'hashB'),
        _item(localId: 'a1', fileHash: 'hashA'),
        _item(localId: 'a2', fileHash: 'hashA'),
        _item(localId: 'z1', fileHash: 'hashZ'),
        _item(localId: 'z2', fileHash: 'hashZ'),
        _item(localId: 'z3', fileHash: 'hashZ'),
      ]);

      final groups = repository.getDuplicateGroups();
      expect(groups.map((g) => g.first.fileHash).toList(), [
        'hashZ',
        'hashA',
        'hashB',
      ]);
    });

    test('excludes hidden, trashed, and empty-hash items', () async {
      final repository = await _repositoryWith([
        // Pair split by a hidden member → not a visible duplicate group.
        _item(localId: 'h1', fileHash: 'hashH'),
        _item(localId: 'h2', fileHash: 'hashH', isHidden: true),
        // Pair split by a trashed member → same.
        _item(localId: 't1', fileHash: 'hashT'),
        _item(localId: 't2', fileHash: 'hashT', isTrashed: true),
        // AI-labeled rows carry an empty hash — never duplicate candidates.
        _item(localId: 'e1', fileHash: ''),
        _item(localId: 'e2', fileHash: ''),
      ]);

      expect(repository.getDuplicateGroups(), isEmpty);
    });
  });
}
