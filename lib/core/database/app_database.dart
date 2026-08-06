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
/// This is the persisted schema that replaces the previous in-memory list.
/// [GalleryRepository] is wired onto this table via [MediaDao].
///
/// Query hot-path indexes: `byHash` dedup checks, status filters, album
/// queries, and every `createdAt`-ordered timeline sort.
@DataClassName('MediaItemRow')
@TableIndex(name: 'idx_media_items_file_hash', columns: {#fileHash})
@TableIndex(name: 'idx_media_items_status', columns: {#status})
@TableIndex(name: 'idx_media_items_album_name', columns: {#albumName})
@TableIndex(name: 'idx_media_items_created_at', columns: {#createdAt})
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

  /// Indexed: the timeline and every album/favorite/search query sorts by
  /// `createdAt` descending.
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

/// The application's drift database.
///
/// Opened once at startup (see main.dart bootstrap, follow-up) and shared via
/// the DI layer. Schema version tracks [DatabaseConstants.schemaVersion].
@DriftDatabase(tables: [MediaItems], daos: [MediaDao])
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
    onUpgrade: (m, from, to) async {
      // v1 -> v2: UploadTasks was removed — the live upload queue is now
      // persisted to JSON by TransferQueuePersistence, and this drift table
      // was never read by the engine. Drop it for existing installs.
      if (from < 2) {
        await m.database.customStatement('DROP TABLE IF EXISTS upload_tasks');
      }
      // v2 -> v3: query hot-path indexes on MediaItems. The annotations on
      // the table only apply to fresh databases (onCreate -> createAll), so
      // existing installs get the same indexes here. IF NOT EXISTS keeps the
      // branch idempotent for any future re-runs.
      if (from < 3) {
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_media_items_file_hash '
          'ON media_items (file_hash)',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_media_items_status '
          'ON media_items (status)',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_media_items_album_name '
          'ON media_items (album_name)',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_media_items_created_at '
          'ON media_items (created_at)',
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

    // Work around old Android sqlite3 limitations and ensure a writable temp dir.
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }
    final cachebase = (await getTemporaryDirectory()).path;
    sqlite3.tempDirectory = cachebase;

    return NativeDatabase.createInBackground(file);
  });
}
