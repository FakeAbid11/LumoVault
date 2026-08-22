import 'package:drift/drift.dart';

/// A detected face region within a media item.
///
/// Each row represents one face found in one photo/video frame. The face is
/// linked to a [MediaItems] row via [mediaItemId] (the `localId` column) and
/// optionally to a [FaceGroups] row via [groupId].
@DataClassName('FaceRow')
@TableIndex(name: 'idx_faces_media_item_id', columns: {#mediaItemId})
@TableIndex(name: 'idx_faces_group_id', columns: {#groupId})
class Faces extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The [MediaItem.localId] this face belongs to.
  TextColumn get mediaItemId => text()();

  /// Optional link to a [FaceGroups] row. Null means "unassigned / unknown".
  IntColumn get groupId => integer().nullable()();

  /// Bounding box within the source image (normalised 0.0–1.0).
  RealColumn get bboxLeft => real()();
  RealColumn get bboxTop => real()();
  RealColumn get bboxRight => real()();
  RealColumn get bboxBottom => real()();

  /// Embedding vector produced by ML Kit (192 float32 values).
  /// Stored as a JSON-encoded list of doubles.
  TextColumn get embedding => text()();

  /// Confidence score from the detector (0.0–1.0).
  RealColumn get confidence => real()();

  /// When this face was detected.
  DateTimeColumn get detectedAt => dateTime()();

  /// Whether this face has been reviewed / confirmed by the user.
  BoolColumn get isReviewed => boolean().withDefault(const Constant(false))();
}

/// A logical "person" — a cluster of faces that the app believes belong to
/// the same individual.
@DataClassName('FaceGroupRow')
@TableIndex(name: 'idx_face_groups_item_count', columns: {#itemCount})
class FaceGroups extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// User-assigned display name, e.g. "Mom". Null means unnamed.
  TextColumn get name => text().nullable()();

  /// File path to the representative thumbnail for this group.
  /// Displayed in the People grid.
  TextColumn get thumbnailPath => text().nullable()();

  /// Number of faces currently in this group (denormalised counter).
  IntColumn get itemCount => integer().withDefault(const Constant(0))();

  /// When this group was first created.
  DateTimeColumn get createdAt => dateTime()();

  /// Last time a face was added or removed.
  DateTimeColumn get updatedAt => dateTime()();
}
