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
import 'daos/upload_task_dao.dart';

part 'app_database.g.dart';

/// JSON <-> `List<String>` converter used for columns that store a list of
/// strings (e.g. media tags) as a single JSON-encoded text value.
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

/// Drift table mirroring PRD §5 `MediaItem`.
///
/// This is the persisted schema that replaces the previous in-memory list and
/// the abandoned Isar collection. The plain [MediaItem] domain model still
/// exists; wiring [GalleryRepository] onto this table is a follow-up step.
@DataClassName('MediaItemRow')
class MediaItems extends Table {
  /// Local autoincrement primary key.
  IntColumn get id => integer().autoIncrement()();

  /// Stable platform media id (photo_manager asset id).
  TextColumn get localId => text()();

  /// Content hash used for dedup.
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

  /// Stored as the enum index of `MediaStatus`.
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

  /// JSON-encoded `List<String>`.
  TextColumn get tags => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();

  TextColumn get thumbnailPath => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {localId},
  ];
}

/// Drift table mirroring PRD §5 `UploadTask`.
///
/// The `TransferError` object is flattened into [errorCategory] and
/// [errorMessage] columns; reconstruction is handled at the repository layer.
@DataClassName('UploadTaskRow')
class UploadTasks extends Table {
  TextColumn get id => text()();
  TextColumn get mediaItemId => text()();
  TextColumn get localFilePath => text()();
  TextColumn get fileName => text()();
  IntColumn get fileSize => integer()();
  TextColumn get fileHash => text()();

  TextColumn get telegramFileId => text().nullable()();
  TextColumn get telegramMessageId => text().nullable()();

  /// Stored as the enum index of `UploadStatus`.
  IntColumn get status => integer().withDefault(const Constant(0))();
  RealColumn get progress => real().withDefault(const Constant(0.0))();

  /// Flattened `TransferError` (see UploadTaskRowMapper). Null when no error.
  TextColumn get errorCategory => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get errorDetail => text().nullable()();
  BoolColumn get errorRetryable =>
      boolean().withDefault(const Constant(false))();
  IntColumn get errorRetryAfterSeconds => integer().nullable()();
  DateTimeColumn get errorOccurredAt => dateTime().nullable()();

  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get failedAt => dateTime().nullable()();
  DateTimeColumn get pausedAt => dateTime().nullable()();
  DateTimeColumn get lastActivityAt => dateTime().nullable()();

  IntColumn get priority => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// The application's drift database.
///
/// Opened once at startup (see main.dart bootstrap, follow-up) and shared via
/// the DI layer. Schema version tracks [DatabaseConstants.schemaVersion].
@DriftDatabase(
  tables: [MediaItems, UploadTasks],
  daos: [MediaDao, UploadTaskDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Test constructor: pass an in-memory or custom executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => DatabaseConstants.schemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      p.join(dir.path, '${DatabaseConstants.databaseName}.sqlite'),
    );

    // Work around old Android sqlite3 limitations and ensure a writable temp dir.
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }
    final cachebase = (await getTemporaryDirectory()).path;
    sqlite3.tempDirectory = cachebase;

    return NativeDatabase.createInBackground(file);
  });
}
