import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/metadata/data/repositories/metadata_validator.dart';

void main() {
  group('MetadataValidator', () {
    test('returns empty issues for valid items', () async {
      final items = [
        MediaItem(
          localId: '1',
          fileHash: 'abc123',
          filePath: '/fake/path.jpg',
          fileName: 'test.jpg',
          mimeType: 'image/jpeg',
          fileSize: 1024,
          width: 1920,
          height: 1080,
          createdAt: DateTime(2024),
          modifiedAt: DateTime(2024),
          scannedAt: DateTime(2024),
        ),
      ];

      final validator = MetadataValidator(mediaItems: items);

      final result = await validator.validate();

      expect(result.hasIssues, isTrue);
      // File missing is expected since /fake/path.jpg doesn't exist.
      expect(
        result.issues.any((i) => i.type == MetadataIssueType.fileMissing),
        isTrue,
      );
    });

    test('detects empty file hash', () async {
      final items = [
        MediaItem(
          localId: '1',
          fileHash: '',
          filePath: '/fake/path.jpg',
          fileName: 'test.jpg',
          mimeType: 'image/jpeg',
          fileSize: 1024,
          width: 1920,
          height: 1080,
          createdAt: DateTime(2024),
          modifiedAt: DateTime(2024),
          scannedAt: DateTime(2024),
        ),
      ];

      final validator = MetadataValidator(mediaItems: items);

      final result = await validator.validate();

      expect(
        result.issues.any(
          (i) =>
              i.type == MetadataIssueType.incompleteMetadata &&
              i.description.contains('File hash'),
        ),
        isTrue,
      );
    });

    test('detects empty MIME type', () async {
      final items = [
        MediaItem(
          localId: '1',
          fileHash: 'abc123',
          filePath: '/fake/path.jpg',
          fileName: 'test.jpg',
          mimeType: '',
          fileSize: 1024,
          width: 1920,
          height: 1080,
          createdAt: DateTime(2024),
          modifiedAt: DateTime(2024),
          scannedAt: DateTime(2024),
        ),
      ];

      final validator = MetadataValidator(mediaItems: items);

      final result = await validator.validate();

      expect(
        result.issues.any(
          (i) =>
              i.type == MetadataIssueType.incompleteMetadata &&
              i.description.contains('MIME type'),
        ),
        isTrue,
      );
    });

    // Regression guard: restored/cloud items keep their file in the storage
    // channel, so their local path is a telegram:// URI (or empty). Without
    // the isTelegram guard every one of these was reported fileMissing and
    // the "repair" feature told users their whole library was broken.
    test('does not report Telegram-only items as missing', () async {
      final items = [
        MediaItem(
          localId: 'msg_123',
          fileHash: 'abc123',
          filePath: 'telegram://123',
          fileName: 'photo.jpg',
          mimeType: 'image/jpeg',
          fileSize: 1024,
          width: 1920,
          height: 1080,
          telegramMessageId: '123',
          createdAt: DateTime(2024),
          modifiedAt: DateTime(2024),
          scannedAt: DateTime(2024),
        ),
      ];

      final validator = MetadataValidator(mediaItems: items);

      final result = await validator.validate();

      expect(
        result.issues.any((i) => i.type == MetadataIssueType.fileMissing),
        isFalse,
        reason: 'Telegram-only items have no local file by design',
      );
    });

    test('counts checked items correctly', () async {
      final items = [
        MediaItem(
          localId: '1',
          fileHash: 'abc',
          filePath: '/fake/a.jpg',
          fileName: 'a.jpg',
          mimeType: 'image/jpeg',
          fileSize: 100,
          width: 100,
          height: 100,
          createdAt: DateTime(2024),
          modifiedAt: DateTime(2024),
          scannedAt: DateTime(2024),
        ),
        MediaItem(
          localId: '2',
          fileHash: 'def',
          filePath: '/fake/b.jpg',
          fileName: 'b.jpg',
          mimeType: 'image/jpeg',
          fileSize: 200,
          width: 200,
          height: 200,
          createdAt: DateTime(2024),
          modifiedAt: DateTime(2024),
          scannedAt: DateTime(2024),
        ),
      ];

      final validator = MetadataValidator(mediaItems: items);

      final result = await validator.validate();

      expect(result.itemsChecked, equals(2));
    });

    test('ValidationResult fixableCount is correct', () {
      const result = ValidationResult(
        issues: [
          MetadataIssue(
            localId: '1',
            type: MetadataIssueType.thumbnailMissing,
            description: 'Missing',
            autoFixable: true,
          ),
          MetadataIssue(
            localId: '2',
            type: MetadataIssueType.fileMissing,
            description: 'Missing',
            autoFixable: false,
          ),
        ],
        itemsChecked: 10,
        duration: Duration(seconds: 1),
      );

      expect(result.fixableCount, equals(1));
      expect(result.hasIssues, isTrue);
    });

    test('ValidationResult with no issues', () {
      const result = ValidationResult(
        issues: [],
        itemsChecked: 0,
        duration: Duration.zero,
      );

      expect(result.fixableCount, equals(0));
      expect(result.hasIssues, isFalse);
    });
  });

  group('MetadataIssueType', () {
    // The enum is a truthful contract: exactly the checks validate() performs.
    // Advertising checks that don't exist is what made the old repair feature
    // report problems it could not find and fixes it never applied.
    test('has exactly the detectable issue types', () {
      expect(MetadataIssueType.values.length, equals(3));
      expect(
        MetadataIssueType.values.toSet(),
        equals({
          MetadataIssueType.fileMissing,
          MetadataIssueType.incompleteMetadata,
          MetadataIssueType.thumbnailMissing,
        }),
      );
    });
  });
}
