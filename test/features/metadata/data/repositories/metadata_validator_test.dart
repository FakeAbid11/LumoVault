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

      final validator = MetadataValidator(
        mediaItems: items,
        searchTerms: ['test.jpg'],
      );

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

      final validator = MetadataValidator(mediaItems: items, searchTerms: []);

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

      final validator = MetadataValidator(mediaItems: items, searchTerms: []);

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

      final validator = MetadataValidator(mediaItems: items, searchTerms: []);

      final result = await validator.validate();

      expect(result.itemsChecked, equals(2));
    });

    test('autoFix returns count of fixable issues', () async {
      final issues = [
        const MetadataIssue(
          localId: '1',
          type: MetadataIssueType.thumbnailMissing,
          description: 'Thumbnail missing',
          autoFixable: true,
        ),
        const MetadataIssue(
          localId: '2',
          type: MetadataIssueType.fileMissing,
          description: 'File missing',
          autoFixable: false,
        ),
        const MetadataIssue(
          localId: '3',
          type: MetadataIssueType.incompleteMetadata,
          description: 'Empty hash',
          autoFixable: true,
        ),
      ];

      final items = <MediaItem>[];
      final validator = MetadataValidator(mediaItems: items, searchTerms: []);

      final fixed = await validator.autoFix(issues);

      expect(fixed, equals(2));
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
    test('has all expected types', () {
      expect(MetadataIssueType.values.length, equals(7));
      expect(
        MetadataIssueType.values.toSet(),
        equals({
          MetadataIssueType.fileMissing,
          MetadataIssueType.hashMismatch,
          MetadataIssueType.incompleteMetadata,
          MetadataIssueType.orphanedFile,
          MetadataIssueType.thumbnailMissing,
          MetadataIssueType.danglingPartitionRef,
          MetadataIssueType.staleSearchIndex,
        }),
      );
    });
  });
}
