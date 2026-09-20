import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/constants/database_constants.dart';
import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/core/database/media_item_mapper.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';

/// Opens the real [AppDatabase] pinned to schema version 19, so the next
/// open exercises the v20 provenance columns + full People wipe in
/// isolation (v20's ALTERs must run BEFORE the DELETEs).
class _DbAtV19 extends AppDatabase {
  _DbAtV19(super.e) : super.forTesting();

  @override
  int get schemaVersion => 19;
}

void main() {
  late File dbFile;

  setUp(() {
    dbFile = File(
      '${Directory.systemTemp.path}/'
      'v20_migration_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
  });

  tearDown(() {
    if (dbFile.existsSync()) dbFile.deleteSync();
  });

  test(
    'v19 → v20 adds provenance columns and wipes the unverifiable face graph',
    () async {
      // Phase 1: seed a v19-era person graph with UNTAGGED vectors (the
      // rows v20 can never trust — embedder provenance is unknowable) plus
      // media the wipe must leave alone. createAll() builds the CURRENT
      // schema, so drop the v20 columns to reproduce a genuine v19 file.
      final db19 = _DbAtV19(NativeDatabase(dbFile));
      await db19.customStatement(
        'ALTER TABLE faces DROP COLUMN embedding_model',
      );
      await db19.customStatement('ALTER TABLE faces DROP COLUMN excluded');
      await db19.customStatement(
        'ALTER TABLE people DROP COLUMN centroid_model',
      );
      await db19.mediaDao.upsert(
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
      final personId = await db19.faceDao.createPerson('Alice');
      await db19.faceDao.insertFace(
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
      await db19.faceDao.markMediaItemScanned('m1', 1);
      await db19.close();

      // Phase 2: reopen at the current app version.
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      expect(DatabaseConstants.schemaVersion, 20);
      final media = await db.mediaDao.all();
      expect(media.map((r) => r.localId), ['m1']);

      // The unverifiable face graph is gone…
      expect(await db.faceDao.allFaces(), isEmpty);
      expect(await db.faceDao.allPeopleRows(), isEmpty);
      expect(await db.faceDao.scannedMediaItemIds(), isEmpty);

      // …and the new provenance columns exist: a model-tagged, non-excluded
      // face round-trips through them.
      await db.faceDao.insertFaces([
        FacesCompanion.insert(
          mediaItemId: 'm1',
          boundingBoxX: 0.1,
          boundingBoxY: 0.1,
          boundingBoxWidth: 0.2,
          boundingBoxHeight: 0.2,
          embedding: const Value([1.0, 0.0]),
          embeddingModel: const Value('edgeface_xs_gamma_06.onnx'),
          confidence: 0.9,
          createdAt: DateTime(2026, 1, 1),
        ),
      ]);
      final face = (await db.faceDao.allFaces()).single;
      expect(face.embeddingModel, 'edgeface_xs_gamma_06.onnx');
      expect(face.excluded, isFalse);
    },
  );
}
