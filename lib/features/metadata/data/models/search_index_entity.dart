/// Search term type enumeration per PRD Section 5.2.
enum SearchTermType { filename, description, tag, album, date }

/// SearchIndex entity per PRD Section 5.1 Collection 6.
///
/// Full-text search index for fast queries across media metadata.
/// Each searchable term is stored as a separate index entry linked
/// to a MediaItem via mediaItemId.
class SearchIndexEntity {
  const SearchIndexEntity({
    this.id,
    required this.mediaItemId,
    required this.term,
    required this.type,
  });
  final int? id;
  final String mediaItemId;
  final String term;
  final SearchTermType type;

  SearchIndexEntity copyWith({
    int? id,
    String? mediaItemId,
    String? term,
    SearchTermType? type,
  }) {
    return SearchIndexEntity(
      id: id ?? this.id,
      mediaItemId: mediaItemId ?? this.mediaItemId,
      term: term ?? this.term,
      type: type ?? this.type,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchIndexEntity &&
          runtimeType == other.runtimeType &&
          mediaItemId == other.mediaItemId &&
          term == other.term &&
          type == other.type;

  @override
  int get hashCode => mediaItemId.hashCode ^ term.hashCode ^ type.hashCode;

  @override
  String toString() =>
      'SearchIndexEntity(mediaItemId: $mediaItemId, term: $term, type: $type)';
}
