import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/caption_metadata.dart';

void main() {
  group('CaptionMetadata', () {
    test('toCaptionString creates valid JSON', () {
      final metadata = CaptionMetadata(
        mediaItemId: 'media_1',
        fileHash: 'hash1',
        createdAt: DateTime(2026, 7, 14),
        modifiedAt: DateTime(2026, 7, 14),
        backedUpAt: DateTime(2026, 7, 14),
        mimeType: 'image/jpeg',
        fileSize: 1000,
        width: 1920,
        height: 1080,
        isFavorite: true,
        albumName: 'Vacation',
        tags: ['travel', 'beach'],
      );

      final caption = metadata.toCaptionString();

      expect(caption, isNotEmpty);
      expect(caption, contains('v'));
      expect(caption, contains('h'));
      expect(caption, contains('fav'));
    });

    test('fromCaptionString parses valid JSON', () {
      final original = CaptionMetadata(
        mediaItemId: 'media_1',
        fileHash: 'hash1',
        createdAt: DateTime(2026, 7, 14),
        modifiedAt: DateTime(2026, 7, 14),
        backedUpAt: DateTime(2026, 7, 14),
        mimeType: 'image/jpeg',
        fileSize: 1000,
        width: 1920,
        height: 1080,
        isFavorite: true,
        albumName: 'Vacation',
        tags: ['travel', 'beach'],
      );

      final caption = original.toCaptionString();
      final parsed = CaptionMetadata.fromCaptionString(caption);

      expect(parsed.mediaItemId, original.mediaItemId);
      expect(parsed.fileHash, original.fileHash);
      expect(parsed.fileSize, original.fileSize);
      expect(parsed.width, original.width);
      expect(parsed.height, original.height);
      expect(parsed.isFavorite, original.isFavorite);
      expect(parsed.albumName, original.albumName);
      expect(parsed.tags, original.tags);
    });

    test('fromCaptionString handles invalid JSON gracefully', () {
      final parsed = CaptionMetadata.fromCaptionString('invalid json');

      expect(parsed.mediaItemId, '');
      expect(parsed.fileHash, '');
      expect(parsed.createdAt, isNotNull);
    });

    test('equality based on mediaItemId and fileHash', () {
      final metadata1 = CaptionMetadata(
        mediaItemId: 'media_1',
        fileHash: 'hash1',
        createdAt: DateTime(2026, 7, 14),
        modifiedAt: DateTime(2026, 7, 14),
        backedUpAt: DateTime(2026, 7, 14),
      );

      final metadata2 = CaptionMetadata(
        mediaItemId: 'media_1',
        fileHash: 'hash1',
        createdAt: DateTime(2026, 7, 15),
        modifiedAt: DateTime(2026, 7, 15),
        backedUpAt: DateTime(2026, 7, 15),
      );

      final metadata3 = CaptionMetadata(
        mediaItemId: 'media_2',
        fileHash: 'hash2',
        createdAt: DateTime(2026, 7, 14),
        modifiedAt: DateTime(2026, 7, 14),
        backedUpAt: DateTime(2026, 7, 14),
      );

      expect(metadata1, equals(metadata2));
      expect(metadata1, isNot(equals(metadata3)));
    });

    test('roundtrip preserves all fields', () {
      final original = CaptionMetadata(
        mediaItemId: 'media_1',
        fileHash: 'hash1',
        createdAt: DateTime(2026, 7, 14, 12, 30, 45),
        modifiedAt: DateTime(2026, 7, 14, 12, 30, 45),
        backedUpAt: DateTime(2026, 7, 14, 12, 30, 45),
        mimeType: 'video/mp4',
        fileSize: 5000000,
        width: 1920,
        height: 1080,
        durationMs: 30000,
        isFavorite: true,
        isHidden: false,
        isArchived: true,
        albumName: 'Family',
        deviceFolder: 'DCIM',
        description: 'Beach sunset',
        tags: ['sunset', 'beach'],
      );

      final caption = original.toCaptionString();
      final parsed = CaptionMetadata.fromCaptionString(caption);

      expect(parsed.mediaItemId, original.mediaItemId);
      expect(parsed.fileHash, original.fileHash);
      expect(parsed.mimeType, original.mimeType);
      expect(parsed.fileSize, original.fileSize);
      expect(parsed.width, original.width);
      expect(parsed.height, original.height);
      expect(parsed.durationMs, original.durationMs);
      expect(parsed.isFavorite, original.isFavorite);
      expect(parsed.isHidden, original.isHidden);
      expect(parsed.isArchived, original.isArchived);
      expect(parsed.albumName, original.albumName);
      expect(parsed.deviceFolder, original.deviceFolder);
      expect(parsed.description, original.description);
      expect(parsed.tags, original.tags);
    });
  });
}
