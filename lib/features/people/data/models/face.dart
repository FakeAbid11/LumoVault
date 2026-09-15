/// Represents a detected face in a photo.
///
/// Each face is associated with a media item and contains location
/// information (bounding box) and a 192-dim embedding vector for recognition.
class Face {
  const Face({
    this.id,
    required this.mediaItemId,
    required this.boundingBoxX,
    required this.boundingBoxY,
    required this.boundingBoxWidth,
    required this.boundingBoxHeight,
    this.landmarks = const {},
    this.embedding = const [],
    required this.confidence,
    this.thumbnailPath,
    required this.createdAt,
  });

  final int? id;
  final String mediaItemId;
  final double boundingBoxX;
  final double boundingBoxY;
  final double boundingBoxWidth;
  final double boundingBoxHeight;

  /// Landmark positions as name -> (x, y).
  final Map<String, (double, double)> landmarks;

  /// 512-dimensional face embedding vector from InsightFace ArcFace
  /// (w600k_mbf.onnx). L2-normalized for cosine similarity comparison.
  final List<double> embedding;

  final double confidence;
  final String? thumbnailPath;
  final DateTime createdAt;

  /// Get the center of the bounding box.
  (double, double) get center => (
    boundingBoxX + boundingBoxWidth / 2,
    boundingBoxY + boundingBoxHeight / 2,
  );

  /// Get the aspect ratio of the face.
  double get aspectRatio =>
      boundingBoxWidth / (boundingBoxHeight > 0 ? boundingBoxHeight : 1);

  /// Get the area of the bounding box.
  double get area => boundingBoxWidth * boundingBoxHeight;

  Face copyWith({
    int? id,
    String? mediaItemId,
    double? boundingBoxX,
    double? boundingBoxY,
    double? boundingBoxWidth,
    double? boundingBoxHeight,
    Map<String, (double, double)>? landmarks,
    List<double>? embedding,
    double? confidence,
    String? thumbnailPath,
    DateTime? createdAt,
  }) {
    return Face(
      id: id ?? this.id,
      mediaItemId: mediaItemId ?? this.mediaItemId,
      boundingBoxX: boundingBoxX ?? this.boundingBoxX,
      boundingBoxY: boundingBoxY ?? this.boundingBoxY,
      boundingBoxWidth: boundingBoxWidth ?? this.boundingBoxWidth,
      boundingBoxHeight: boundingBoxHeight ?? this.boundingBoxHeight,
      landmarks: landmarks ?? this.landmarks,
      embedding: embedding ?? this.embedding,
      confidence: confidence ?? this.confidence,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Face &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          mediaItemId == other.mediaItemId;

  @override
  int get hashCode => id.hashCode ^ mediaItemId.hashCode;
}
