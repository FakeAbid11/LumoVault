import 'dart:convert';

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import '../constants/database_constants.dart';
import 'daos/media_dao.dart';
import 'daos/face_dao.dart';

part 'app_database.g.dart';

class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const [];
    final decoded = jsonDecode(fromDb);
    if (decoded is! List) return const [];
    return decoded.map((e) => e.toString()).toList();
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

class LandmarksConverter
    extends TypeConverter<Map<String, (double, double)>, String> {
  const LandmarksConverter();

  @override
  Map<String, (double, double)> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const {};
    final decoded = jsonDecode(fromDb);
    if (decoded is! Map) return const {};
    return decoded.map((key, value) {
      if (value is List && value.length == 2) {
        return MapEntry(key, (value[0] as double, value[1] as double));
      }
      return MapEntry(key, (0.0, 0.0));
    });
  }

  @override
  String toSql(Map<String, (double, double)> value) {
    return jsonEncode(value.map((key, val) => MapEntry(key, [val.$1, val.$2])));
  }
}

class EmbeddingConverter extends TypeConverter<List<double>, String> {
  const EmbeddingConverter();

  @override
  List<double> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const [];
    final decoded = jsonDecode(fromDb);
    if (decoded is! List) return const [];
    return decoded.map((e) => (e as num).toDouble()).toList();
  }

  @override
  String toSql(List<double> value) => jsonEncode(value);
}

@DataClassName('MediaItemRow')
@TableIndex(name: 'idx_media_items_file_hash', columns: {#fileHash})
@TableIndex(name: 'idx_media_items_status', columns: {#status})
@TableIndex(name: 'idx_media_items_album_name', columns: {#albumName})
@TableIndex(name: 'idx_media_items_created_at', columns: {#createdAt})
@TableIndex(name: 'idx_media_items_is_favorite', columns: {#isFavorite})
@TableIndex(
  name: 'idx_media_items_trashed_trashed_at',
  columns: {#isTrashed, #trashedAt},
)
class MediaItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get localId => text()();
  TextColumn get fileHash => text()();
  TextColumn get telegramMessageId => text().nullable()();
  TextColumn get telegramFileId => text().nullable()();
  TextColumn get filePath => text()();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text()();
  IntColumn get fileSize => integer()();
  IntColumn get width => integer()();
  IntColumn get height => integer()();
  IntColumn get durationMs => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();
  DateTimeColumn get scannedAt => dateTime()();
  DateTimeColumn get uploadedAt => dateTime().nullable()();
  DateTimeColumn get backedUpAt => dateTime().nullable()();
  IntColumn get status => integer().withDefault(const Constant(0))();
  TextColumn get errorMessage => text().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isTrashed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get trashedAt => dateTime().nullable()();
  BoolColumn get isExcluded => boolean().withDefault(const Constant(false))();
  TextColumn get albumName => text().nullable()();
  TextColumn get deviceFolder => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get tags => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get aiLabels => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get thumbnailPath => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  BoolColumn get isLocationUserSet =>
      boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {localId},
  ];
}

@DataClassName('FaceRow')
@TableIndex(name: 'idx_faces_media_item_id', columns: {#mediaItemId})
@TableIndex(name: 'idx_faces_person_id', columns: {#personId})
class Faces extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get mediaItemId => text()();
  RealColumn get boundingBoxX => real()();
  RealColumn get boundingBoxY => real()();
  RealColumn get boundingBoxWidth => real()();
  RealColumn get boundingBoxHeight => real()();
  TextColumn get landmarks => text()
      .map(const LandmarksConverter())
      .withDefault(const Constant('{}'))();
  TextColumn get embedding => text()
      .map(const EmbeddingConverter())
      .withDefault(const Constant('[]'))();
  RealColumn get confidence => real()();
  TextColumn get thumbnailPath => text().nullable()();
  IntColumn get personId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('PersonRow')
class People extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().nullable()();
  IntColumn get thumbnailFaceId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get centroidEmbedding => text()
      .map(const EmbeddingConverter())
      .withDefault(const Constant('[]'))();
}

@DataClassName('FacePersonRow')
class FacePersons extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get faceId => integer()();
  IntColumn get personId => integer()();
  DateTimeColumn get assignedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {faceId, personId},
  ];
}

/// One row per photo that has been through face detection, including photos
/// where no face was found.
///
/// Without this, "already scanned" had to be inferred from the faces table,
/// so every face-less photo was re-detected on each scan pass.
@DataClassName('FaceScanRow')
class FaceScans extends Table {
  TextColumn get mediaItemId => text()();
  DateTimeColumn get scannedAt => dateTime()();
  IntColumn get faceCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {mediaItemId};
}

@DriftDatabase(
  tables: [MediaItems, Faces, People, FacePersons, FaceScans],
  daos: [MediaDao, FaceDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => DatabaseConstants.schemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.database.customStatement('DROP TABLE IF EXISTS upload_tasks');
      }
      if (from < 3) {
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_media_items_file_hash ON media_items (file_hash)',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_media_items_status ON media_items (status)',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_media_items_album_name ON media_items (album_name)',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_media_items_created_at ON media_items (created_at)',
        );
      }
      if (from < 4) {
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_media_items_is_favorite ON media_items (is_favorite)',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_media_items_trashed_trashed_at ON media_items (is_trashed, trashed_at)',
        );
      }
      if (from < 5) {
        await m.addColumn(mediaItems, mediaItems.latitude);
        await m.addColumn(mediaItems, mediaItems.longitude);
      }
      if (from < 6) {
        await m.addColumn(mediaItems, mediaItems.isLocationUserSet);
      }
      if (from < 7) {
        // createTable uses the current schema (v9) which already includes
        // embedding and centroid_embedding columns, so no ALTER needed.
        await m.createTable(faces);
        await m.createTable(people);
        await m.createTable(facePersons);
      } else {
        // Upgrading from v7: add columns that were introduced in v8/v9.
        if (from < 8) {
          await m.database.customStatement(
            'ALTER TABLE faces ADD COLUMN embedding TEXT NOT NULL DEFAULT \'[]\'',
          );
        }
        if (from < 9) {
          await m.database.customStatement(
            'ALTER TABLE people ADD COLUMN centroid_embedding TEXT NOT NULL DEFAULT \'[]\'',
          );
        }
      }
      if (from < 10) {
        // Clear all face data — 192-dim embeddings are incompatible with
        // the new 512-dim InsightFace ArcFace model. A full re-scan is
        // required after upgrade.
        await m.database.customStatement('DELETE FROM face_persons');
        await m.database.customStatement(
          "UPDATE faces SET embedding = '[]', person_id = NULL",
        );
        await m.database.customStatement('DELETE FROM people');
      }
      if (from < 11) {
        await m.createTable(faceScans);
        if (from >= 7) {
          // Faces detected before the SCRFD anchor-decode fix have bogus
          // boxes and embeddings and cannot be clustered meaningfully.
          // Drop them and let the next scan rebuild from scratch.
          await m.database.customStatement('DELETE FROM face_persons');
          await m.database.customStatement('DELETE FROM faces');
          await m.database.customStatement('DELETE FROM people');
        }
      }
      if (from < 12) {
        // Faces are now aligned to the ArcFace 5-point template before
        // embedding. Old unaligned embeddings sit elsewhere in the vector
        // space, so keeping them would poison every cluster they touch.
        // Clear the scan log too, so the next pass re-detects everything.
        await m.database.customStatement('DELETE FROM face_persons');
        await m.database.customStatement('DELETE FROM faces');
        await m.database.customStatement('DELETE FROM people');
        await m.database.customStatement('DELETE FROM face_scans');
      }
      if (from < 13) {
        await m.database.customStatement(
          "ALTER TABLE media_items ADD COLUMN ai_labels TEXT NOT NULL DEFAULT '[]'",
        );
      }
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      p.join(dir.path, '${DatabaseConstants.databaseName}.sqlite'),
    );
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }
    final cachebase = (await getTemporaryDirectory()).path;
    sqlite3.tempDirectory = cachebase;
    return NativeDatabase.createInBackground(file);
  });
}
