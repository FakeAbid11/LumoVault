import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/constants/database_constants.dart';
import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/core/database/media_item_mapper.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';

/// Opens the real [AppDatabase] pinned to schema version 18, so the next
/// open exercises the v19 wipe of AI labels + CLIP embeddings WITHOUT the
/// v18 face-wipe step having to mean anything (from==18 skips it).
class _DbAtV18 extends AppDatabase {
  _DbAtV18(super.e) : super.forTesting();

  @override
  int get schemaVersion => 18;
}

void main() {
  late File dbFile;

  setUp(() {
    dbFile = File(
      '${Directory.systemTemp.path}/'
      'v19_migration_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
  });

  tearDown(() {
    if (dbFile.existsSync()) dbFile.deleteSync();
  });

  test(
    'v18 → v19 wipes ai_labels + clip_embedding, keeps faces and rows',
    () async {
      // Phase 1: seed a row with WRONG-ERA derived data (labels from the
      // fabricated map, a vector from the raw-0-255 preprocessing) plus face
      // rows the v19 step must not touch.
      final db18 = _DbAtV18(NativeDatabase(dbFile));
      await db18.mediaDao.upsert(
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
          aiLabels: const ['ai_shed', 'ai_other'],
          clipEmbedding: Uint8List(2048),
        ).toCompanion(),
      );
      final personId = await db18.faceDao.createPerson('Alice');
      await db18.faceDao.insertFace(
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
      await db18.close();

      // Phase 2: reopen at the current version.
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      expect(DatabaseConstants.schemaVersion, 19);
      final media = await db.mediaDao.all();
      expect(media.map((r) => r.localId), ['m1']);
      expect(
        media.single.aiLabels,
        isEmpty,
        reason: 'stale mis-mapped labels must be cleared for regeneration',
      );
      expect(
        media.single.clipEmbedding,
        isNull,
        reason: 'stale wrong-range vectors must be cleared for re-embedding',
      );
      // v19 is labels/embeddings only — People data survives.
      expect(await db.faceDao.allFaces(), hasLength(1));
      expect((await db.faceDao.allPeopleRows()).single.name, 'Alice');
    },
  );
}
