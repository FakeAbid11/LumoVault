import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/database/daos/face_dao.dart';
import '../../../../core/database/app_database.dart';
import '../models/face.dart';
import '../models/person.dart';
import '../services/face_detection_service.dart';
import '../services/face_clustering_service.dart';

class FaceRepository {
  FaceRepository({
    required this.faceDao,
    required this.faceDetectionService,
    required this.faceClusteringService,
  });

  final FaceDao faceDao;
  final FaceDetectionService faceDetectionService;
  final FaceClusteringService faceClusteringService;

  static const double minConfidence = 0.7;

  /// Minimum face size, as a fraction of each image dimension.
  ///
  /// Detection runs on a 640×640 downscale, so 3% of the image is roughly a
  /// 19 px face in detector space — below that the embedding is not reliable.
  /// (The previous gate asked for 2% of the image *area*, which on a 12 MP
  /// photo demanded a ~490 px face and rejected essentially every real one.)
  static const double minFaceSideFraction = 0.03;
  static const double maxAspectRatio = 2.0;

  /// Longest side, in pixels, of the image handed to the detector.
  ///
  /// Detection runs at 640×640 and the size gate rejects anything under 3% of a
  /// side, so full sensor resolution buys nothing. Decoding it costs a great
  /// deal: `package:image` is pure Dart and allocates width × height × 3, so a
  /// 108 MP original — routine on mid-range phones in 64/108 MP mode — becomes a
  /// 324 MB buffer and seconds of single-threaded work, where this is under
  /// 6 MB and milliseconds via the platform decoder.
  static const int detectionMaxSide = 1600;

  /// Faces clustered per pass. Clustering is O(n²) in memory and worse in
  /// time, so the unassigned backlog is drained oldest-first in slices;
  /// leftovers are picked up by the next pass or by [reclusterOrphans].
  static const int maxFacesPerClusterPass = 600;

  /// Names of the five SCRFD landmarks, in the order the detector emits them.
  static const List<String> landmarkNames = [
    'leftEye',
    'rightEye',
    'nose',
    'leftMouth',
    'rightMouth',
  ];

  /// Landmarks normalised to 0..1, matching how the bounding box is stored.
  ///
  /// Empty when the detector export has no keypoint head, which also signals
  /// that this face's embedding came from an unaligned crop.
  @visibleForTesting
  Map<String, (double, double)> normalizedLandmarks(
    DetectedFace face,
    int imageWidth,
    int imageHeight,
  ) {
    if (face.landmarks.length != landmarkNames.length) return const {};
    if (imageWidth <= 0 || imageHeight <= 0) return const {};
    return {
      for (var i = 0; i < landmarkNames.length; i++)
        landmarkNames[i]: (
          face.landmarks[i].dx / imageWidth,
          face.landmarks[i].dy / imageHeight,
        ),
    };
  }

  @visibleForTesting
  bool isHighQualityFace(DetectedFace face, int imageWidth, int imageHeight) {
    if (face.confidence < minConfidence) {
      return false;
    }
    if (imageWidth <= 0 || imageHeight <= 0) {
      return false;
    }
    if (face.boundingBox.width / imageWidth < minFaceSideFraction ||
        face.boundingBox.height / imageHeight < minFaceSideFraction) {
      return false;
    }
    final aspectRatio = face.boundingBox.width / face.boundingBox.height;
    if (aspectRatio < (1.0 / maxAspectRatio) || aspectRatio > maxAspectRatio) {
      return false;
    }
    return true;
  }

  Future<int> scanMediaItem(AssetEntity asset) async {
    try {
      await faceDetectionService.ensureInitialized();
      final imageBytes = await _detectionBytes(asset);
      if (imageBytes == null) {
        // Nothing decodable to offer the detector — record the attempt so it is
        // not retried on every later pass.
        await faceDao.markMediaItemScanned(asset.id, 0);
        return 0;
      }

      // Single call: detect faces + generate all thumbnails in one worker
      // isolate pass. No per-face cropFace() re-reads or compute() spawns.
      final detection = await faceDetectionService.detectFacesWithThumbnails(
        imageBytes,
      );
      final detectedFaces = detection.faces;
      final thumbnailPaths = detection.thumbnailPaths;

      if (detectedFaces.isEmpty) {
        // Record the attempt so a face-less photo (or a video, or an
        // undecodable file) is not re-detected on every later pass.
        await faceDao.markMediaItemScanned(asset.id, 0);
        return 0;
      }
      final now = DateTime.now();
      final companions = <FacesCompanion>[];
      // Normalise against the decoded image, which is what the boxes were
      // measured in; asset.width/height disagree on EXIF-rotated photos.
      final imageWidth = detection.imageWidth > 0
          ? detection.imageWidth
          : asset.width;
      final imageHeight = detection.imageHeight > 0
          ? detection.imageHeight
          : asset.height;
      if (imageWidth == 0 || imageHeight == 0) {
        // Undecodable dimensions — mark scanned so it is not retried forever.
        await faceDao.markMediaItemScanned(asset.id, 0);
        return 0;
      }
      var accepted = 0;
      var rejected = 0;
      for (var i = 0; i < detectedFaces.length; i++) {
        final face = detectedFaces[i];
        if (!isHighQualityFace(face, imageWidth, imageHeight)) {
          rejected++;
          continue;
        }
        accepted++;
        companions.add(
          FacesCompanion.insert(
            mediaItemId: asset.id,
            boundingBoxX: face.boundingBox.left / imageWidth,
            boundingBoxY: face.boundingBox.top / imageHeight,
            boundingBoxWidth: face.boundingBox.width / imageWidth,
            boundingBoxHeight: face.boundingBox.height / imageHeight,
            landmarks: Value(
              normalizedLandmarks(face, imageWidth, imageHeight),
            ),
            embedding: Value(face.embedding),
            confidence: face.confidence,
            thumbnailPath: Value(
              i < thumbnailPaths.length ? thumbnailPaths[i] : null,
            ),
            createdAt: now,
          ),
        );
      }
      if (companions.isNotEmpty) await faceDao.insertFaces(companions);
      await faceDao.markMediaItemScanned(asset.id, companions.length);
      debugPrint(
        '[FaceRepository] scan ${asset.id}: '
        '${detectedFaces.length} detected, '
        '$accepted accepted, $rejected rejected '
        '(img ${imageWidth}x$imageHeight)',
      );
      return companions.length;
    } catch (e) {
      debugPrint('[FaceRepository] Failed to scan: $e');
      return 0;
    }
  }

  /// Bytes to run detection against, downscaled to [detectionMaxSide].
  ///
  /// `thumbnailDataWithSize` decodes on the platform side, which is both far
  /// faster than `package:image` and bounded in memory regardless of the
  /// sensor's resolution. It also returns the frame already rotated, so boxes
  /// land in the same orientation the viewer shows — the original's EXIF
  /// rotation is not applied by `img.decodeImage`.
  ///
  /// Falls back to the original file for assets the platform will not
  /// thumbnail. That decode is unbounded, but the detection service now times
  /// out and respawns its worker, so a photo too large to decode costs one
  /// timeout instead of stalling the scan.
  Future<Uint8List?> _detectionBytes(AssetEntity asset) async {
    try {
      final thumbnail = await asset.thumbnailDataWithSize(
        const ThumbnailSize(detectionMaxSide, detectionMaxSide),
      );
      if (thumbnail != null && thumbnail.isNotEmpty) return thumbnail;
    } catch (e) {
      debugPrint('[FaceRepository] Thumbnail failed for ${asset.id}: $e');
    }

    final file = await asset.file;
    if (file == null) return null;
    return file.readAsBytes();
  }

  /// Photos scanned between progressive clustering passes.
  ///
  /// After every [scanBatchSize] photos the caller's [onBatchComplete] runs,
  /// which clusters what has been found so far and refreshes the People grid,
  /// then scanning continues with the next slice.
  static const int scanBatchSize = 50;

  Future<Map<String, int>> scanMediaItems(
    List<AssetEntity> assets, {
    void Function(int current, int total)? onProgress,
    Future<void> Function()? onBatchComplete,
  }) async {
    final results = <String, int>{};
    final scannedIds = await faceDao.scannedMediaItemIds();
    final toScan = assets.where((a) => !scannedIds.contains(a.id)).toList();
    for (var i = 0; i < toScan.length; i++) {
      final faceCount = await scanMediaItem(toScan[i]);
      results[toScan[i].id] = faceCount;
      onProgress?.call(i + 1, toScan.length);
      await Future.delayed(Duration.zero);
      // Every scanBatchSize photos, let the caller cluster + refresh the UI.
      // Awaited so clustering never overlaps itself or the next batch.
      if (onBatchComplete != null && (i + 1) % scanBatchSize == 0) {
        await onBatchComplete();
      }
    }
    return results;
  }

  Future<int> clusterFaces() async {
    // Repair first. Databases written before the absorb-then-create ordering
    // below can already hold several tiles for one face, and nothing else in
    // the app ever merges them back.
    await consolidateDuplicatePeople();

    // Absorb before creating. This used to run *after* new people were minted
    // (see the tail of this method), which meant every pass created a fresh
    // person for any cluster of three or more unassigned faces — even when the
    // grid already had a tile for that face. Only the sub-three leftovers were
    // ever matched against an existing centroid, so one burst of photos inside
    // a single 50-photo pass was enough to duplicate somebody.
    await reclusterOrphans();

    final unassigned = await faceDao.unassignedFaces();
    if (unassigned.isEmpty) return 0;
    final allWithEmb = unassigned.where((f) => f.embedding.isNotEmpty).toList();
    if (allWithEmb.isEmpty) return 0;
    // Oldest-first slice so the backlog drains deterministically.
    final withEmb = allWithEmb.length > maxFacesPerClusterPass
        ? allWithEmb.sublist(0, maxFacesPerClusterPass)
        : allWithEmb;
    final embeddings = withEmb.map((f) => f.embedding).toList();
    debugPrint(
      '[FaceRepository] clusterFaces: ${withEmb.length} of '
      '${allWithEmb.length} unassigned faces this pass '
      '(embedding dim: ${embeddings.first.length})',
    );
    // Clustering is pure CPU work — run it off the UI isolate.
    final clusters = await compute(clusterAndRefine, embeddings);
    debugPrint('[FaceRepository] ${clusters.length} clusters after refinement');
    var newPersons = 0;
    for (final cluster in clusters) {
      // Enforce minimum cluster size — small clusters remain unassigned
      // and may be picked up later by reclusterOrphans().
      if (cluster.length < FaceClusteringService.minClusterSizeForNewPerson) {
        continue;
      }

      final personId = await faceDao.createPerson(null);
      final cEmb = cluster.map((i) => withEmb[i].embedding).toList();
      await faceDao.updateCentroid(
        personId,
        faceClusteringService.computeCentroid(cEmb),
      );

      final faceIds = cluster
          .map((i) => withEmb[i].id)
          .whereType<int>()
          .toList();
      await faceDao.assignFacesToPerson(faceIds, personId);

      // Select the largest face as the person's thumbnail
      final li = cluster.reduce((a, b) {
        final aa = withEmb[a].boundingBoxWidth * withEmb[a].boundingBoxHeight;
        final ab = withEmb[b].boundingBoxWidth * withEmb[b].boundingBoxHeight;
        return aa > ab ? a : b;
      });
      await faceDao.setPersonThumbnail(personId, withEmb[li].id);
      newPersons++;
    }
    debugPrint(
      '[FaceRepository] created $newPersons persons '
      '(${clusters.length - newPersons} clusters below min size)',
    );
    // The people just created are new absorption anchors, so the faces that
    // failed to match anything at the top of this method get one more chance
    // against them. Skipped when nothing was created: the leading pass already
    // tried every anchor that exists, and re-walking the whole orphan backlog
    // against them costs O(orphans × people) for no possible gain.
    if (newPersons > 0) {
      await reclusterOrphans();
    }
    return newPersons;
  }

  /// Whether [name] is a real user-supplied name rather than an auto-created
  /// person's placeholder.
  static bool _hasName(String? name) => name != null && name.trim().isNotEmpty;

  /// Cosine similarity an orphan face must reach to join the person named
  /// [personName].
  ///
  /// A user-named person is an explicit identity claim, so joining one takes
  /// the stricter [FaceClusteringService.namedThreshold]. An auto-created,
  /// still-unnamed person gets [FaceClusteringService.defaultThreshold] — the
  /// same bar the clustering pass used to group its faces in the first place.
  ///
  /// Holding unnamed people to the strict bar is what produced duplicate tiles:
  /// a face 0.50 similar to an existing unnamed person was too dissimilar to
  /// join it, yet three such faces cleared the 0.45 bar *between themselves*
  /// and became a second person for the same face. The threshold constant is
  /// documented as the orphan-to-*named*-person bar; it was being applied to
  /// everyone.
  @visibleForTesting
  static double absorbThreshold(String? personName) => _hasName(personName)
      ? FaceClusteringService.namedThreshold
      : FaceClusteringService.defaultThreshold;

  Future<void> reclusterOrphans() async {
    final orphans = await faceDao.unassignedFaces();
    if (orphans.isEmpty) return;
    final orphanEmb = orphans.where((f) => f.embedding.isNotEmpty).toList();
    if (orphanEmb.isEmpty) return;
    final peopleRows = await faceDao.allPeopleRows();
    final anchors = peopleRows
        .where((p) => p.centroidEmbedding.isNotEmpty)
        .toList();
    if (anchors.isEmpty) return;
    for (final orphan in orphanEmb) {
      var bestId = -1;
      var bestSim = 0.0;
      for (final person in anchors) {
        final sim = faceClusteringService.cosineSimilarity(
          orphan.embedding,
          person.centroidEmbedding,
        );
        // Each candidate is held to its own bar before competing, so a 0.52
        // match against an unnamed person wins over a 0.54 match against a
        // named one that fails its stricter 0.55 threshold.
        if (sim < absorbThreshold(person.name)) continue;
        if (sim > bestSim) {
          bestSim = sim;
          bestId = person.id;
        }
      }
      if (bestId >= 0) {
        await faceDao.assignFaceToPerson(orphan.id, bestId);
      }
    }
  }

  /// Merges people that are duplicates of one another.
  ///
  /// Repairs libraries scanned before [clusterFaces] learned to absorb before
  /// creating, where one burst of photos of someone already in the grid minted
  /// a second tile for them. Runs at the top of every clustering pass, so an
  /// existing install heals on its next scan without a schema migration.
  ///
  /// A named person is only ever a merge *target*, never a source: two people
  /// the user named separately is an explicit statement that they are different
  /// people, and no similarity score overrides that.
  ///
  /// Returns the number of people merged away.
  Future<int> consolidateDuplicatePeople() async {
    final people = await faceDao.allPeople();
    final candidates = people
        .where((p) => p.person.centroidEmbedding.isNotEmpty)
        .toList();
    if (candidates.length < 2) return 0;

    // Named people first, then the largest clusters. The tile a user is most
    // likely to recognise absorbs the strays, rather than a three-face
    // fragment swallowing their main one and inheriting its thumbnail.
    candidates.sort((a, b) {
      final aNamed = _hasName(a.person.name);
      final bNamed = _hasName(b.person.name);
      if (aNamed != bNamed) return aNamed ? -1 : 1;
      return b.faceCount.compareTo(a.faceCount);
    });

    final centroids = <int, List<double>>{
      for (final c in candidates) c.person.id: c.person.centroidEmbedding,
    };
    final merged = <int>{};
    var mergedAway = 0;

    for (var i = 0; i < candidates.length; i++) {
      final target = candidates[i].person;
      if (merged.contains(target.id)) continue;
      final threshold = absorbThreshold(target.name);

      for (var j = i + 1; j < candidates.length; j++) {
        final source = candidates[j].person;
        if (merged.contains(source.id) || _hasName(source.name)) continue;

        final sim = faceClusteringService.cosineSimilarity(
          centroids[target.id]!,
          centroids[source.id]!,
        );
        if (sim < threshold) continue;

        await faceDao.mergePersons(source.id, target.id);
        merged.add(source.id);
        mergedAway++;

        // Recompute before the next comparison: the target now covers both
        // clusters, and matching later candidates against its stale centroid
        // would leave a chain of near-duplicates unmerged.
        await recomputeCentroid(target.id);
        final refreshed = await faceDao.personById(target.id);
        if (refreshed != null && refreshed.centroidEmbedding.isNotEmpty) {
          centroids[target.id] = refreshed.centroidEmbedding;
        }
      }
    }

    if (mergedAway > 0) {
      debugPrint(
        '[FaceRepository] consolidated $mergedAway duplicate person(s)',
      );
    }
    return mergedAway;
  }

  Future<void> recomputeCentroid(int personId) async {
    final faces = await faceDao.facesForPerson(personId);
    final embs = faces
        .where((f) => f.embedding.isNotEmpty)
        .map((f) => f.embedding)
        .toList();
    if (embs.isEmpty) return;
    await faceDao.updateCentroid(
      personId,
      faceClusteringService.computeCentroid(embs),
    );
  }

  Future<List<PersonWithCount>> getPeople() => faceDao.allPeople();

  Future<Person?> getPerson(int id) async {
    final row = await faceDao.personById(id);
    if (row == null) return null;
    return Person(
      id: row.id,
      name: row.name,
      thumbnailFaceId: row.thumbnailFaceId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  Future<void> updatePersonName(int personId, String? name) async {
    await faceDao.updatePersonName(personId, name);
    await recomputeCentroid(personId);
    await reclusterOrphans();
  }

  Future<List<Face>> getFacesForPerson(int personId) async {
    final rows = await faceDao.facesForPerson(personId);
    return rows.map(_rowToFace).toList();
  }

  Future<List<String>> getMediaItemIdsForPerson(int personId) async {
    final faces = await faceDao.facesForPerson(personId);
    return faces.map((f) => f.mediaItemId).toSet().toList();
  }

  Future<void> mergePersons(int sourceId, int targetId) async {
    await faceDao.mergePersons(sourceId, targetId);
    await recomputeCentroid(targetId);
    await reclusterOrphans();
  }

  /// Merge multiple people into [targetId]. All faces from the other people
  /// are reassigned to [targetId], then the source people are deleted.
  /// Centroid is recomputed and orphans are reclustered once at the end.
  Future<void> bulkMergePersons(List<int> sourceIds, int targetId) async {
    for (final sourceId in sourceIds) {
      if (sourceId == targetId) continue;
      await faceDao.mergePersons(sourceId, targetId);
    }
    await recomputeCentroid(targetId);
    await reclusterOrphans();
  }

  /// Delete multiple people, unassigning all their faces.
  /// Orphans are reclustered once at the end.
  Future<void> bulkDeletePersons(List<int> personIds) async {
    for (final personId in personIds) {
      await faceDao.deletePerson(personId);
    }
    await reclusterOrphans();
  }

  Future<void> deletePerson(int personId) async {
    await faceDao.deletePerson(personId);
    await reclusterOrphans();
  }

  Future<int> getFaceCount() => faceDao.faceCount();
  Future<bool> isScanningComplete() => faceDao.isScanningComplete();

  Face _rowToFace(FaceRow row) {
    return Face(
      id: row.id,
      mediaItemId: row.mediaItemId,
      boundingBoxX: row.boundingBoxX,
      boundingBoxY: row.boundingBoxY,
      boundingBoxWidth: row.boundingBoxWidth,
      boundingBoxHeight: row.boundingBoxHeight,
      landmarks: row.landmarks,
      embedding: row.embedding,
      confidence: row.confidence,
      thumbnailPath: row.thumbnailPath,
      createdAt: row.createdAt,
    );
  }
}
