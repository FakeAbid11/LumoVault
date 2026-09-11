import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/constants/database_constants.dart';
import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/core/database/media_item_mapper.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';

/// Opens the real [AppDatabase] pinned to schema version 17, so the next
/// open at version 18 exercises the onUpgrade detector-swap wipe.
class _DbAtV17 extends AppDatabase {
  _DbAtV17(super.e) : super.forTesting();

  @override
  int get schemaVersion => 17;
}

void main() {
  late File dbFile;

  setUp(() {
    dbFile = File(
      '${Directory.systemTemp.path}/'
      'v18_migration_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
  });

  tearDown(() {
    if (dbFile.existsSync()) dbFile.deleteSync();
  });

  test('v17 → v18 wipes face tables but leaves media_items alone', () async {
    // Phase 1: create the database at v17 and seed face data + one media row.
    final db17 = _DbAtV17(NativeDatabase(dbFile));
    await db17.mediaDao.upsert(
      MediaItem(
        localId: 'm1',
        fileHash: 'h-m1',
        filePath: '/p/m1',
        fileName: 'm1.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1,
        width: 1,
        height: 1,
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 1),
        scannedAt: DateTime(2026, 1, 1),
      ).toCompanion(),
    );
    final personId = await db17.faceDao.createPerson('Alice');
    await db17.faceDao.insertFace(
      FacesCompanion.insert(
        mediaItemId: 'm1',
        boundingBoxX: 0.1,
        boundingBoxY: 0.1,
        boundingBoxWidth: 0.2,
        boundingBoxHeight: 0.2,
        confidence: 0.9,
        personId: Value(personId),
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await db17.customStatement(
      'INSERT INTO face_scans (media_item_id, face_count, scanned_at) '
      "VALUES ('m1', 1, ?)",
      [DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000],
    );
    await db17.close();

    // Phase 2: reopen at v18 — onUpgrade must wipe all four face tables
    // (People rebuilds under the new detector tier) while media rows survive.
    final db18 = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db18.close);

    expect(DatabaseConstants.schemaVersion, 18);
    expect(await db18.faceDao.allPeopleRows(), isEmpty);
    expect(await db18.faceDao.allFaces(), isEmpty);
    expect(await db18.faceDao.scannedMediaItemIds(), isEmpty);
    final media = await db18.mediaDao.all();
    expect(media.map((r) => r.localId), ['m1']);
  });
}
