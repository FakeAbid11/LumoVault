/// Represents a person (cluster of similar faces).
///
/// A person is a group of faces that the clustering algorithm has determined
/// belong to the same individual. Users can optionally assign a name.
class Person {
  const Person({
    this.id,
    this.name,
    this.thumbnailFaceId,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String? name;
  final int? thumbnailFaceId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Display name or fallback to "Person N".
  String get displayName => name ?? 'Person';

  Person copyWith({
    int? id,
    String? name,
    bool clearName = false,
    int? thumbnailFaceId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Person(
      id: id ?? this.id,
      name: clearName ? null : (name ?? this.name),
      thumbnailFaceId: thumbnailFaceId ?? this.thumbnailFaceId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Person && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
