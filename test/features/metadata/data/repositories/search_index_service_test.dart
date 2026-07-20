import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/metadata/data/models/metadata_models.dart';
import 'package:lumovault/features/metadata/data/repositories/search_index_service.dart';

void main() {
  group('SearchIndexService', () {
    late SearchIndexService service;

    setUp(() {
      service = SearchIndexService();
    });

    tearDown(() {
      service.dispose();
    });

    test('indexSize returns 0 initially', () {
      expect(service.indexSize, 0);
    });

    test('indexItem adds searchable terms', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        fileName: 'photo.jpg',
        albumName: 'Camera',
        description: 'A beautiful sunset',
        tags: ['vacation', 'beach'],
      );

      service.indexItem(item);

      expect(service.indexSize, greaterThan(0));
    });

    test('search finds matching items', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        fileName: 'sunset_photo.jpg',
      );

      service.indexItem(item);

      final results = service.search('sunset');
      expect(results, contains('123'));
    });

    test('search returns empty for no matches', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        fileName: 'photo.jpg',
      );

      service.indexItem(item);

      final results = service.search('nonexistent');
      expect(results, isEmpty);
    });

    test('searchByType finds items in specific type', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        fileName: 'photo.jpg',
        albumName: 'Vacation',
      );

      service.indexItem(item);

      final filenameResults = service.searchByType(
        'photo',
        SearchTermType.filename,
      );
      expect(filenameResults, contains('123'));

      final albumResults = service.searchByType(
        'Vacation',
        SearchTermType.album,
      );
      expect(albumResults, contains('123'));
    });

    test('removeItem removes all index entries', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        fileName: 'photo.jpg',
      );

      service.indexItem(item);
      expect(service.indexSize, greaterThan(0));

      service.removeItem('123');
      expect(service.indexSize, 0);
    });

    test('reindexItem updates index entries', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        fileName: 'old_name.jpg',
      );

      service.indexItem(item);

      final updatedItem = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        fileName: 'new_name.jpg',
      );

      service.reindexItem(updatedItem);

      final oldResults = service.search('old_name');
      expect(oldResults, isEmpty);

      final newResults = service.search('new_name');
      expect(newResults, contains('123'));
    });

    test('getTermsForItem returns indexed terms', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        fileName: 'photo.jpg',
        albumName: 'Camera',
      );

      service.indexItem(item);

      final terms = service.getTermsForItem('123');
      expect(terms.length, greaterThan(0));
    });

    test('getAllIndexedIds returns all indexed IDs', () {
      final item1 = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        fileName: 'photo1.jpg',
      );
      final item2 = PartitionItem(
        localId: '456',
        fileHash: 'def',
        createdAt: DateTime(2026, 1, 20),
        modifiedAt: DateTime(2026, 1, 20),
        fileName: 'photo2.jpg',
      );

      service.indexItem(item1);
      service.indexItem(item2);

      final ids = service.getAllIndexedIds();
      expect(ids.length, 2);
      expect(ids, contains('123'));
      expect(ids, contains('456'));
    });

    test('clear removes all index entries', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        fileName: 'photo.jpg',
      );

      service.indexItem(item);
      expect(service.indexSize, greaterThan(0));

      service.clear();
      expect(service.indexSize, 0);
    });

    test('search is case-insensitive', () {
      final item = PartitionItem(
        localId: '123',
        fileHash: 'abc',
        createdAt: DateTime(2026, 1, 15),
        modifiedAt: DateTime(2026, 1, 15),
        fileName: 'Sunset.jpg',
      );

      service.indexItem(item);

      final results = service.search('sunset');
      expect(results, contains('123'));
    });
  });
}
