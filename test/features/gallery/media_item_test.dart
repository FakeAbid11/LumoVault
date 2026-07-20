import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';

void main() {
  group('MediaItem', () {
    test('mediaType returns image for image mime types', () {
      final item = MediaItem(
        localId: '1',
        fileHash: 'hash1',
        filePath: '/path/test.jpg',
        fileName: 'test.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1000,
        width: 1920,
        height: 1080,
        createdAt: DateTime(2026, 7, 14),
        modifiedAt: DateTime(2026, 7, 14),
        scannedAt: DateTime(2026, 7, 14),
      );

      expect(item.mediaType, MediaType.image);
      expect(item.isVideo, false);
    });

    test('mediaType returns video for video mime types', () {
      final item = MediaItem(
        localId: '1',
        fileHash: 'hash1',
        filePath: '/path/test.mp4',
        fileName: 'test.mp4',
        mimeType: 'video/mp4',
        fileSize: 5000000,
        width: 1920,
        height: 1080,
        durationMs: 30000,
        createdAt: DateTime(2026, 7, 14),
        modifiedAt: DateTime(2026, 7, 14),
        scannedAt: DateTime(2026, 7, 14),
      );

      expect(item.mediaType, MediaType.video);
      expect(item.isVideo, true);
      expect(item.durationMs, 30000);
    });

    test('copyWith creates new instance with updated fields', () {
      final item = MediaItem(
        localId: '1',
        fileHash: 'hash1',
        filePath: '/path/test.jpg',
        fileName: 'test.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1000,
        width: 1920,
        height: 1080,
        createdAt: DateTime(2026, 7, 14),
        modifiedAt: DateTime(2026, 7, 14),
        scannedAt: DateTime(2026, 7, 14),
      );

      final updated = item.copyWith(isFavorite: true);

      expect(updated.isFavorite, true);
      expect(item.isFavorite, false);
      expect(updated.localId, '1');
    });

    test('equality based on localId and fileHash', () {
      final item1 = MediaItem(
        localId: '1',
        fileHash: 'hash1',
        filePath: '/path/test.jpg',
        fileName: 'test.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1000,
        width: 1920,
        height: 1080,
        createdAt: DateTime(2026, 7, 14),
        modifiedAt: DateTime(2026, 7, 14),
        scannedAt: DateTime(2026, 7, 14),
      );

      final item2 = MediaItem(
        localId: '1',
        fileHash: 'hash1',
        filePath: '/path/test2.jpg',
        fileName: 'test2.jpg',
        mimeType: 'image/jpeg',
        fileSize: 2000,
        width: 1920,
        height: 1080,
        createdAt: DateTime(2026, 7, 14),
        modifiedAt: DateTime(2026, 7, 14),
        scannedAt: DateTime(2026, 7, 14),
      );

      expect(item1, equals(item2));
    });

    test('default values are correct', () {
      final item = MediaItem(
        localId: '1',
        fileHash: 'hash1',
        filePath: '/path/test.jpg',
        fileName: 'test.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1000,
        width: 1920,
        height: 1080,
        createdAt: DateTime(2026, 7, 14),
        modifiedAt: DateTime(2026, 7, 14),
        scannedAt: DateTime(2026, 7, 14),
      );

      expect(item.status, MediaStatus.pending);
      expect(item.isFavorite, false);
      expect(item.isHidden, false);
      expect(item.isArchived, false);
      expect(item.isTrashed, false);
      expect(item.isExcluded, false);
      expect(item.tags, isEmpty);
    });
  });
}
