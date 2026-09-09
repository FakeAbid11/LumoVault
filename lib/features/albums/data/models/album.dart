class Album {
  const Album({
    this.id,
    required this.name,
    this.coverId,
    this.position = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String? coverId;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;

  Album copyWith({
    int? id,
    String? name,
    String? coverId,
    bool clearCoverId = false,
    int? position,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Album(
      id: id ?? this.id,
      name: name ?? this.name,
      coverId: clearCoverId ? null : (coverId ?? this.coverId),
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Album &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name;

  @override
  int get hashCode => id.hashCode ^ name.hashCode;
}

class AlbumItem {
  const AlbumItem({
    required this.albumId,
    required this.mediaId,
    required this.addedAt,
  });

  final int albumId;
  final String mediaId;
  final DateTime addedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlbumItem &&
          runtimeType == other.runtimeType &&
          albumId == other.albumId &&
          mediaId == other.mediaId;

  @override
  int get hashCode => albumId.hashCode ^ mediaId.hashCode;
}
