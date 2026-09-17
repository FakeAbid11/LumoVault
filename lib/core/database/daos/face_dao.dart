import 'package:drift/drift.dart';

import '../app_database.dart';

part 'face_dao.g.dart';

@DriftAccessor(tables: [Faces, People, FacePersons, FaceScans])
class FaceDao extends DatabaseAccessor<AppDatabase> with _$FaceDaoMixin {
  FaceDao(super.db);

  /// Insert a detected face.
  Future<int> insertFace(FacesCompanion face) {
    return into(faces).insert(face);
  }

  /// Batch insert faces.
  Future<void> insertFaces(List<FacesCompanion> faceList) async {
    await batch((b) => b.insertAll(faces, faceList));
  }

  /// Get all faces for a media item.
  Future<List<FaceRow>> facesForMediaItem(String mediaItemId) {
    return (select(faces)
          ..where((t) => t.mediaItemId.equals(mediaItemId))
          ..orderBy([(t) => OrderingTerm.desc(t.confidence)]))
        .get();
  }

  /// Get distinct person names for a media item (faces linked to named people).
  Future<List<String>> personNamesForMediaItem(String mediaItemId) async {
    final query =
        select(
            faces,
          ).join([innerJoin(people, people.id.equalsExp(faces.personId))])
          ..where(faces.mediaItemId.equals(mediaItemId))
          ..where(people.name.isNotNull());

    final results = await query.get();
    return results.map((row) => row.readTable(people).name!).toSet().toList();
  }

  /// Get all faces, optionally filtered by person.
  Future<List<FaceRow>> allFaces({int? personId}) {
    final query = select(faces);
    if (personId != null) {
      query.where((t) => t.personId.equals(personId));
    }
    return query.get();
  }

  /// Get all unassigned faces (not yet clustered), oldest first.
  ///
  /// The ordering is load-bearing: [FaceRepository.clusterFaces] drains this
  /// backlog in fixed-size slices, and SQLite guarantees no order without an
  /// explicit ORDER BY — so without this the slice boundary could shift between
  /// passes and starve the tail of the backlog.
  ///
  /// Faces the user removed from a person (`excluded`) are filtered out here
  /// so the clustering slice never re-mints them and [reclusterOrphans] never
  /// re-absorbs them.
  Future<List<FaceRow>> unassignedFaces() {
    return (select(faces)
          ..where((t) => t.personId.isNull() & t.excluded.equals(false))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  /// Assign a face to a person.
  Future<void> assignFaceToPerson(int faceId, int personId) async {
    await (update(faces)..where((t) => t.id.equals(faceId))).write(
      FacesCompanion(personId: Value(personId)),
    );
  }

  /// Batch assign faces to a person.
  Future<void> assignFacesToPerson(List<int> faceIds, int personId) async {
    await (update(faces)..where((t) => t.id.isIn(faceIds))).write(
      FacesCompanion(personId: Value(personId)),
    );
  }

  /// Unassign all faces from a person.
  Future<void> unassignAllFaces(int personId) async {
    await (update(faces)..where((t) => t.personId.equals(personId))).write(
      const FacesCompanion(personId: Value(null)),
    );
  }

  /// Unassign specific faces WITHOUT excluding them (they stay eligible for
  /// re-clustering — this is the 'Fix wrong groupings' path, not a user
  /// removal).
  Future<void> unassignFaces(List<int> faceIds) async {
    if (faceIds.isEmpty) return;
    await (update(faces)..where((t) => t.id.isIn(faceIds))).write(
      const FacesCompanion(personId: Value(null)),
    );
  }

  /// User-removal ("this is not the person"): unassign AND exclude, so the
  /// face never rejoins via absorption or seeds a new cluster. The only
  /// paths that can revive an excluded face are a full rescan
  /// ([clearForRescan] deletes every row) or an explicit user move.
  Future<void> excludeFaces(List<int> faceIds) async {
    if (faceIds.isEmpty) return;
    await (update(faces)..where((t) => t.id.isIn(faceIds))).write(
      const FacesCompanion(personId: Value(null), excluded: Value(true)),
    );
  }

  /// Get all people with face count and unique photo count.
  Future<List<PersonWithCount>> allPeople() async {
    final query = select(
      people,
    ).join([leftOuterJoin(faces, faces.personId.equalsExp(people.id))]);

    final results = await query.get();
    final Map<int, _PersonAccumulator> personMap = {};

    for (final row in results) {
      final person = row.readTableOrNull(people);
      final face = row.readTableOrNull(faces);

      if (person == null) continue;

      personMap.putIfAbsent(
        person.id,
        () => _PersonAccumulator(person: person),
      );

      if (face != null) {
        final acc = personMap[person.id]!;
        acc.faceCount++;
        acc.mediaItemIds.add(face.mediaItemId);
      }
    }

    return personMap.values
        .map(
          (acc) => PersonWithCount(
            person: acc.person,
            faceCount: acc.faceCount,
            photoCount: acc.mediaItemIds.length,
          ),
        )
        .toList()
      ..sort((a, b) => b.photoCount.compareTo(a.photoCount));
  }

  /// Get all people (not just with counts).
  Future<List<PersonRow>> allPeopleRows() {
    return select(people).get();
  }

  /// Get a single person by id.
  Future<PersonRow?> personById(int id) {
    return (select(people)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Create a new person.
  Future<int> createPerson(String? name) {
    return into(people).insert(
      PeopleCompanion(
        name: Value(name),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Update a person's name.
  Future<void> updatePersonName(int personId, String? name) async {
    await (update(people)..where((t) => t.id.equals(personId))).write(
      PeopleCompanion(name: Value(name), updatedAt: Value(DateTime.now())),
    );
  }

  /// Set the thumbnail face for a person (null clears it).
  Future<void> setPersonThumbnail(int personId, int? faceId) async {
    await (update(people)..where((t) => t.id.equals(personId))).write(
      PeopleCompanion(
        thumbnailFaceId: Value(faceId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Update the centroid embedding for a person, stamping the embedder
  /// model it was computed from (centroids may only be compared against
  /// faces carrying the same tag).
  Future<void> updateCentroid(
    int personId,
    List<double> centroid, {
    String model = '',
  }) async {
    await (update(people)..where((t) => t.id.equals(personId))).write(
      PeopleCompanion(
        centroidEmbedding: Value(centroid),
        centroidModel: Value(model),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Delete a person and unassign all their faces.
  Future<void> deletePerson(int personId) async {
    await (update(faces)..where((t) => t.personId.equals(personId))).write(
      const FacesCompanion(personId: Value(null)),
    );
    await (delete(people)..where((t) => t.id.equals(personId))).go();
  }

  /// Merge two people: move all faces from source to target, then delete source.
  Future<void> mergePersons(int sourceId, int targetId) async {
    await (update(faces)..where((t) => t.personId.equals(sourceId))).write(
      FacesCompanion(personId: Value(targetId)),
    );
    await (delete(people)..where((t) => t.id.equals(sourceId))).go();
  }

  /// Get all faces for a person.
  Future<List<FaceRow>> facesForPerson(int personId) {
    return (select(faces)
          ..where((t) => t.personId.equals(personId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Count total faces in the database.
  Future<int> faceCount() async {
    final count = faces.id.count();
    final query = selectOnly(faces)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// Count faces that have been assigned to a person.
  Future<int> assignedFaceCount() async {
    final count = faces.id.count();
    final query = selectOnly(faces)
      ..addColumns([count])
      ..where(faces.personId.isNotNull());
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// Check if face scanning has been completed for all media items.
  Future<bool> isScanningComplete() async {
    final scanned = await scannedMediaItemCount();

    final mediaCount = await customSelect(
      'SELECT COUNT(*) as total FROM media_items WHERE is_trashed = 0 AND is_hidden = 0',
    ).getSingle();
    final total = mediaCount.data['total'] as int? ?? 0;

    return scanned >= total;
  }

  /// Get the list of media item IDs that have already been scanned for faces.
  ///
  /// Reads the scan log rather than the faces table, so photos that contain
  /// no faces are not re-detected on every pass.
  Future<Set<String>> scannedMediaItemIds() async {
    final results = await select(faceScans).get();
    return results.map((r) => r.mediaItemId).toSet();
  }

  /// Record that [mediaItemId] has been through face detection.
  Future<void> markMediaItemScanned(String mediaItemId, int faceCount) async {
    await into(faceScans).insertOnConflictUpdate(
      FaceScansCompanion.insert(
        mediaItemId: mediaItemId,
        scannedAt: DateTime.now(),
        faceCount: Value(faceCount),
      ),
    );
  }

  /// Number of photos that have been scanned for faces.
  Future<int> scannedMediaItemCount() async {
    final count = faceScans.mediaItemId.count();
    final query = selectOnly(faceScans)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// Forget all scan bookkeeping so the next pass re-scans everything.
  Future<void> clearScanLog() async {
    await delete(faceScans).go();
  }

  /// Wipe all face data for a full re-scan while keeping named people.
  ///
  /// [clearScanLog] alone left the `faces` rows in place, so the next pass
  /// re-detected every face ON TOP of the old rows — each "rescan all"
  /// duplicated the entire face set and the grid counts.
  ///
  /// Named people survive as clustering anchors: their centroid is stored on
  /// the row itself, so fresh detections can re-merge into the person the
  /// user named instead of forcing a full relabel. Unnamed people are
  /// meaningless once their faces are gone, so they go.
  Future<void> clearForRescan() async {
    await delete(faces).go();
    await delete(facePersons).go();
    await (delete(
      people,
    )..where((p) => p.name.isNull() | p.name.equals(''))).go();
    await delete(faceScans).go();
  }
}

/// Mutable accumulator used internally by [FaceDao.allPeople].
class _PersonAccumulator {
  _PersonAccumulator({required this.person});

  final PersonRow person;
  int faceCount = 0;
  final mediaItemIds = <String>{};
}

/// A person with their face count and unique photo count.
class PersonWithCount {
  const PersonWithCount({
    required this.person,
    required this.faceCount,
    required this.photoCount,
  });

  final PersonRow person;
  final int faceCount;
  final int photoCount;

  PersonWithCount copyWith({int? faceCount, int? photoCount}) {
    return PersonWithCount(
      person: person,
      faceCount: faceCount ?? this.faceCount,
      photoCount: photoCount ?? this.photoCount,
    );
  }
}
