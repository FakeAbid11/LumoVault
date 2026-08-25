import '../models/metadata_models.dart';

/// Service for managing the full-text search index per PRD Section 5.1 Collection 6.
///
/// The SearchIndex stores individual searchable terms linked to media items.
/// This enables fast queries across filenames, descriptions, tags, albums, and dates.
class SearchIndexService {
  final List<SearchIndexEntity> _index = [];
  final Map<String, List<SearchIndexEntity>> _byMediaItemId = {};

  int get indexSize => _index.length;

  /// Index a media item's searchable fields.
  void indexItem(PartitionItem item) {
    removeItem(item.localId);

    if (item.fileName != null && item.fileName!.isNotEmpty) {
      _addEntry(
        item.localId,
        item.fileName!.toLowerCase(),
        SearchTermType.filename,
      );
    }

    if (item.description != null && item.description!.isNotEmpty) {
      _addEntry(
        item.localId,
        item.description!.toLowerCase(),
        SearchTermType.description,
      );
    }

    if (item.albumName != null && item.albumName!.isNotEmpty) {
      _addEntry(
        item.localId,
        item.albumName!.toLowerCase(),
        SearchTermType.album,
      );
    }

    for (final tag in item.tags) {
      _addEntry(item.localId, tag.toLowerCase(), SearchTermType.tag);
    }

    final dateStr =
        '${item.createdAt.year}-${item.createdAt.month.toString().padLeft(2, '0')}';
    _addEntry(item.localId, dateStr, SearchTermType.date);
  }

  void _addEntry(String mediaItemId, String term, SearchTermType type) {
    final entity = SearchIndexEntity(
      mediaItemId: mediaItemId,
      term: term,
      type: type,
    );
    _index.add(entity);
    _byMediaItemId.putIfAbsent(mediaItemId, () => []).add(entity);
  }

  /// Re-index an item (e.g., after description or tags change).
  void reindexItem(PartitionItem item) {
    removeItem(item.localId);
    indexItem(item);
  }

  /// Remove all index entries for a media item.
  void removeItem(String mediaItemId) {
    final entries = _byMediaItemId.remove(mediaItemId);
    if (entries != null) {
      for (final entry in entries) {
        _index.remove(entry);
      }
    }
  }

  /// Search for media items matching a query.
  ///
  /// Returns a set of media item IDs that match any term.
  Set<String> search(String query) {
    final lowerQuery = query.toLowerCase();
    final results = <String>{};

    for (final entry in _index) {
      if (entry.term.contains(lowerQuery)) {
        results.add(entry.mediaItemId);
      }
    }

    return results;
  }

  /// Search within a specific term type.
  Set<String> searchByType(String query, SearchTermType type) {
    final lowerQuery = query.toLowerCase();
    final results = <String>{};

    for (final entry in _index) {
      if (entry.type == type && entry.term.contains(lowerQuery)) {
        results.add(entry.mediaItemId);
      }
    }

    return results;
  }

  /// Get all indexed terms for a media item.
  List<SearchIndexEntity> getTermsForItem(String mediaItemId) {
    return _byMediaItemId[mediaItemId] ?? [];
  }

  /// Get all indexed media item IDs.
  Set<String> getAllIndexedIds() {
    return _byMediaItemId.keys.toSet();
  }

  /// Clear the entire search index.
  void clear() {
    _index.clear();
    _byMediaItemId.clear();
  }

  void dispose() {
    _index.clear();
    _byMediaItemId.clear();
  }
}
