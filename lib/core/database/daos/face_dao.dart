import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/face_tables.dart';

part 'face_dao.g.dart';

/// Data-access object for the [Faces] and [FaceGroups] tables.
@DriftAccessor(tables: [Faces, FaceGroups])
class FaceDao extends DatabaseAccessor<AppDatabase> with _$FaceDaoMixin {
  FaceDao(super.db);

  // ── Faces ──────────────────────────────────────────────────────────────

  /// All faces detected in a specific media item.
  Future<List<FaceRow>> facesForMediaItem(String mediaItemId) {
    return (select(faces)
          ..where((t) => t.mediaItemId.equals(mediaItemId))
          ..orderBy([(t) => OrderingTerm.desc(t.confidence)]))
        .get();
  }

  /// All faces in a specific group.
  Future<List<FaceRow>> facesInGroup(int groupId) {
    return (select(faces)
          ..where((t) => t.groupId.equals(groupId))
          ..orderBy([(t) => OrderingTerm.desc(t.detectedAt)]))
        .get();
  }

  /// Faces that have not been assigned to any group yet.
  Future<List<FaceRow>> ungroupedFaces() {
    return (select(faces)
          ..where((t) => t.groupId.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.detectedAt)]))
        .get();
  }

  /// Batch upsert faces. Existing faces with the same [FaceRow.mediaItemId]
  /// and bounding box are replaced.
  Future<void> upsertFaces(List<FacesCompanion> companions) async {
    await batch((b) {
      b.insertAll(faces, companions, mode: InsertMode.insertOrReplace);
    });
  }

  /// Move a face to a different group (or null to ungroup).
  Future<void> assignFaceToGroup(int faceId, int? groupId) {
    return (update(faces)..where((t) => t.id.equals(faceId))).write(
      FacesCompanion(groupId: Value(groupId)),
    );
  }

  /// Batch assign faces to a group.
  Future<void> assignFacesToGroup(List<int> faceIds, int groupId) async {
    await (update(faces)..where((t) => t.id.isIn(faceIds))).write(
      FacesCompanion(groupId: Value(groupId)),
    );
  }

  /// Delete all faces for a media item (e.g. when the item is deleted).
  Future<void> deleteFacesForMediaItem(String mediaItemId) {
    return (delete(faces)..where((t) => t.mediaItemId.equals(mediaItemId)))
        .go();
  }

  /// Count of faces per group, keyed by group id.
  Future<Map<int, int>> faceCountByGroup() async {
    final query = selectOnly(faces, distinct: true)
      ..addColumns([faces.groupId, faces.id.count()])
      ..where(faces.groupId.isNotNull())
      ..groupBy([faces.groupId]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(faces.groupId)!: row.read(faces.id.count())!,
    };
  }

  // ── Face Groups ────────────────────────────────────────────────────────

  /// All face groups, ordered by item count descending.
  Future<List<FaceGroupRow>> allGroups() {
    return (select(faceGroups)
          ..orderBy([(t) => OrderingTerm.desc(t.itemCount)]))
        .get();
  }

  /// A single group by id.
  Future<FaceGroupRow?> groupById(int id) {
    return (select(faceGroups)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Create a new face group. Returns the new row id.
  Future<int> createGroup({
    String? name,
    String? thumbnailPath,
  }) {
    return into(faceGroups).insert(
      FaceGroupsCompanion.insert(
        name: Value(name),
        thumbnailPath: Value(thumbnailPath),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Update a group's name.
  Future<void> renameGroup(int groupId, String? newName) {
    return (update(faceGroups)..where((t) => t.id.equals(groupId))).write(
      FaceGroupsCompanion(
        name: Value(newName),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Update a group's thumbnail.
  Future<void> updateGroupThumbnail(int groupId, String? thumbnailPath) {
    return (update(faceGroups)..where((t) => t.id.equals(groupId))).write(
      FaceGroupsCompanion(
        thumbnailPath: Value(thumbnailPath),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Refresh the denormalised [FaceGroupRow.itemCount] from actual face rows.
  Future<void> refreshGroupCounts() async {
    final counts = await faceCountByGroup();
    await transaction(() async {
      // Zero out all groups first.
      await customStatement(
        'UPDATE face_groups SET item_count = 0',
      );
      // Set the real counts.
      for (final entry in counts.entries) {
        await (update(faceGroups)..where((t) => t.id.equals(entry.key))).write(
          FaceGroupsCompanion(itemCount: Value(entry.value)),
        );
      }
    });
  }

  /// Delete a group. Faces inside are ungrouped (set to null), not deleted.
  Future<void> deleteGroup(int groupId) async {
    await transaction(() async {
      await (update(faces)..where((t) => t.groupId.equals(groupId))).write(
        const FacesCompanion(groupId: Value(null)),
      );
      await (delete(faceGroups)..where((t) => t.id.equals(groupId))).go();
    });
  }

  /// Merge two groups: all faces from [sourceGroupId] move to
  /// [targetGroupId], then the source is deleted.
  Future<void> mergeGroups(int sourceGroupId, int targetGroupId) async {
    await transaction(() async {
      await (update(faces)
            ..where((t) => t.groupId.equals(sourceGroupId)))
          .write(FacesCompanion(groupId: Value(targetGroupId)));
      await (delete(faceGroups)
            ..where((t) => t.id.equals(sourceGroupId)))
          .go();
      await refreshGroupCounts();
    });
  }

  /// Total number of detected faces in the database.
  Future<int> totalFaceCount() async {
    final count = faces.id.count();
    final query = selectOnly(faces)..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// Total number of face groups.
  Future<int> totalGroupCount() async {
    final count = faceGroups.id.count();
    final query = selectOnly(faceGroups)..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }
}
