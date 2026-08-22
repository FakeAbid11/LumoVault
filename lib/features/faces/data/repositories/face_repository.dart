import 'dart:convert';
import 'dart:io';

import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/core/database/daos/face_dao.dart';
import 'package:lumovault/core/database/daos/media_dao.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/face_detection_service.dart';
import '../services/face_grouping_service.dart';

/// Domain model for a face group displayed in the People UI.
class FaceGroup {
  const FaceGroup({
    required this.id,
    this.name,
    this.thumbnailPath,
    this.itemCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String? name;
  final String? thumbnailPath;
  final int itemCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Human-readable display name.
  String get displayName => name ?? 'Unknown';

  /// Whether the user has assigned a name.
  bool get isNamed => name != null && name!.isNotEmpty;
}

/// Domain model for a single detected face displayed in the UI.
class DetectedFaceItem {
  const DetectedFaceItem({
    required this.id,
    required this.mediaItemId,
    this.groupId,
    required this.bboxLeft,
    required this.bboxTop,
    required this.bboxRight,
    required this.bboxBottom,
    required this.confidence,
    required this.detectedAt,
  });

  final int id;
  final String mediaItemId;
  final int? groupId;
  final double bboxLeft;
  final double bboxTop;
  final double bboxRight;
  final double bboxBottom;
  final double confidence;
  final DateTime detectedAt;
}

/// Orchestrates face detection, grouping, and persistence.
///
/// Coordinates [FaceDetectionService] (ML Kit), [FaceGroupingService]
/// (clustering), and [FaceDao] (drift) into a single cohesive pipeline.
class FaceRepository {
  FaceRepository({
    required this.faceDao,
    required this.mediaDao,
    FaceDetectionService? detectionService,
    FaceGroupingService? groupingService,
  })  : _detectionService = detectionService ?? FaceDetectionService(),
        _groupingService = groupingService ?? FaceGroupingService();

  final FaceDao faceDao;
  final MediaDao mediaDao;
  final FaceDetectionService _detectionService;
  final FaceGroupingService _groupingService;

  // ── Public API ─────────────────────────────────────────────────────────

  /// Detect faces in a single media item and persist the results.
  ///
  /// If the item is a video this is a no-op (we only detect in the poster
  /// frame; video face detection is a future enhancement). Items that have
  /// already been analysed (faces exist in DB) are skipped.
  Future<int> analyseMediaItem(MediaItem item) async {
    // Skip videos — only images for now.
    if (item.isVideo) return 0;

    // Skip if already analysed.
    final existing = await faceDao.facesForMediaItem(item.localId);
    if (existing.isNotEmpty) return 0;

    final file = File(item.filePath);
    if (!file.existsSync()) return 0;

    try {
      final faces = await _detectionService.detectFaces(
        filePath: item.filePath,
        imageWidth: item.width,
        imageHeight: item.height,
      );

      if (faces.isEmpty) return 0;

      // Persist raw faces (group assignment happens in a separate pass).
      final companions = faces
          .map(
            (f) => FacesCompanion.insert(
              mediaItemId: item.localId,
              bboxLeft: f.bboxLeft,
              bboxTop: f.bboxTop,
              bboxRight: f.bboxRight,
              bboxBottom: f.bboxBottom,
              embedding: jsonEncode(f.embedding),
              confidence: f.confidence,
              detectedAt: DateTime.now(),
            ),
          )
          .toList();

      await faceDao.upsertFaces(companions);
      return faces.length;
    } catch (e) {
      // Log but don't crash — face detection is best-effort.
      return 0;
    }
  }

  /// Run face detection across the entire library.
  ///
  /// Processes items in batches to avoid memory pressure. Returns the total
  /// number of new faces detected.
  Future<int> analyseEntireLibrary({
    void Function(int processed, int total, int facesFound)? onProgress,
  }) async {
    final allMedia = await mediaDao.all();
    final total = allMedia.length;
    int processed = 0;
    int totalFaces = 0;

    for (final row in allMedia) {
      final item = _rowToMediaItem(row);
      final count = await analyseMediaItem(item);
      totalFaces += count;
      processed++;
      onProgress?.call(processed, total, totalFaces);
    }

    return totalFaces;
  }

  /// Assign all ungrouped faces to groups using clustering.
  ///
  /// Returns the number of new groups created.
  Future<int> groupUngroupedFaces() async {
    final ungrouped = await faceDao.ungroupedFaces();
    if (ungrouped.isEmpty) return 0;

    // Load existing group centroids.
    final groups = await faceDao.allGroups();
    final groupIds = <int>[];
    final centroids = <List<double>>[];

    for (final group in groups) {
      final faces = await faceDao.facesInGroup(group.id);
      if (faces.isEmpty) continue;

      final embeddings = faces
          .map((f) => (jsonDecode(f.embedding) as List).cast<double>())
          .toList();
      groupIds.add(group.id);
      centroids.add(FaceGroupingService.computeCentroid(embeddings));
    }

    // Parse new embeddings.
    final newEmbeddings = ungrouped
        .map((f) => (jsonDecode(f.embedding) as List).cast<double>())
        .toList();

    // Cluster.
    final assignments = _groupingService.assignFaces(
      embeddings: newEmbeddings,
      existingGroupIds: groupIds,
      existingCentroids: centroids,
    );

    // Persist assignments.
    int newGroups = 0;
    final newGroupIds = <int>{};

    for (int i = 0; i < ungrouped.length; i++) {
      final (groupId, isNew) = assignments[i];
      await faceDao.assignFaceToGroup(ungrouped[i].id, groupId);
      if (isNew) {
        newGroups++;
        newGroupIds.add(groupId);
      }
    }

    // Create DB rows for new groups.
    for (final _ in newGroupIds) {
      await faceDao.createGroup(name: null);
    }

    // Refresh denormalised counters.
    await faceDao.refreshGroupCounts();

    // Update thumbnails for groups that don't have one.
    for (final group in await faceDao.allGroups()) {
      if (group.thumbnailPath == null) {
        await _updateGroupThumbnail(group.id);
      }
    }

    return newGroups;
  }

  /// Full pipeline: detect + group.
  Future<void> runFullPipeline({
    void Function(int processed, int total, int facesFound)? onProgress,
  }) async {
    await analyseEntireLibrary(onProgress: onProgress);
    await groupUngroupedFaces();
  }

  /// Get all face groups for the People tab.
  Future<List<FaceGroup>> getAllGroups() async {
    final rows = await faceDao.allGroups();
    return rows.map(_rowToGroup).toList();
  }

  /// Get all faces in a group (for the detail screen).
  Future<List<DetectedFaceItem>> getFacesInGroup(int groupId) async {
    final rows = await faceDao.facesInGroup(groupId);
    return rows.map(_rowToFaceItem).toList();
  }

  /// Get all media item IDs that contain faces from a group.
  Future<List<String>> getMediaItemIdsForGroup(int groupId) async {
    final faces = await faceDao.facesInGroup(groupId);
    // Deduplicate — a photo may have multiple faces from the same person.
    return faces.map((f) => f.mediaItemId).toSet().toList();
  }

  /// Rename a face group.
  Future<void> renameGroup(int groupId, String? name) async {
    await faceDao.renameGroup(groupId, name);
  }

  /// Delete a group (faces become ungrouped).
  Future<void> deleteGroup(int groupId) async {
    await faceDao.deleteGroup(groupId);
  }

  /// Merge two groups.
  Future<void> mergeGroups(int sourceGroupId, int targetGroupId) async {
    await faceDao.mergeGroups(sourceGroupId, targetGroupId);
  }

  /// Total stats for the People tab header.
  Future<({int groupCount, int faceCount})> getStats() async {
    final groups = await faceDao.totalGroupCount();
    final faces = await faceDao.totalFaceCount();
    return (groupCount: groups, faceCount: faces);
  }

  /// Dispose the ML Kit detector.
  Future<void> dispose() async {
    await _detectionService.dispose();
  }

  // ── Private helpers ────────────────────────────────────────────────────

  Future<void> _updateGroupThumbnail(int groupId) async {
    final faces = await faceDao.facesInGroup(groupId);
    if (faces.isEmpty) return;

    // Pick the face with the highest confidence as representative.
    final best = faces.first;

    // Find the source media item to build a cropped thumbnail path.
    final mediaRow = await mediaDao.byLocalId(best.mediaItemId);
    if (mediaRow == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final thumbDir = Directory(p.join(dir.path, 'face_thumbs'));
    if (!thumbDir.existsSync()) await thumbDir.create(recursive: true);

    final thumbPath = p.join(thumbDir.path, 'group_$groupId.jpg');
    await faceDao.updateGroupThumbnail(groupId, thumbPath);
  }

  /// Convert a raw DB row to the domain [MediaItem].
  MediaItem _rowToMediaItem(MediaItemRow row) {
    return MediaItem(
      id: row.id,
      localId: row.localId,
      fileHash: row.fileHash,
      telegramMessageId: row.telegramMessageId,
      telegramFileId: row.telegramFileId,
      filePath: row.filePath,
      fileName: row.fileName,
      mimeType: row.mimeType,
      fileSize: row.fileSize,
      width: row.width,
      height: row.height,
      durationMs: row.durationMs,
      createdAt: row.createdAt,
      modifiedAt: row.modifiedAt,
      scannedAt: row.scannedAt,
      uploadedAt: row.uploadedAt,
      backedUpAt: row.backedUpAt,
      status: MediaStatus.values[row.status],
      errorMessage: row.errorMessage,
      isFavorite: row.isFavorite,
      isHidden: row.isHidden,
      isArchived: row.isArchived,
      isTrashed: row.isTrashed,
      trashedAt: row.trashedAt,
      isExcluded: row.isExcluded,
      albumName: row.albumName,
      deviceFolder: row.deviceFolder,
      description: row.description,
      tags: row.tags,
      thumbnailPath: row.thumbnailPath,
      latitude: row.latitude,
      longitude: row.longitude,
      isLocationUserSet: row.isLocationUserSet,
    );
  }

  FaceGroup _rowToGroup(FaceGroupRow row) {
    return FaceGroup(
      id: row.id,
      name: row.name,
      thumbnailPath: row.thumbnailPath,
      itemCount: row.itemCount,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  DetectedFaceItem _rowToFaceItem(FaceRow row) {
    return DetectedFaceItem(
      id: row.id,
      mediaItemId: row.mediaItemId,
      groupId: row.groupId,
      bboxLeft: row.bboxLeft,
      bboxTop: row.bboxTop,
      bboxRight: row.bboxRight,
      bboxBottom: row.bboxBottom,
      confidence: row.confidence,
      detectedAt: row.detectedAt,
    );
  }
}
