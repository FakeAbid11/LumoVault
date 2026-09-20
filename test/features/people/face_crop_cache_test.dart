import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/people/data/services/face_detection_service.dart';

void main() {
  group('evictFaceCropCache', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lumovault_crop_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<File> writeCrop(String name, int bytes) async {
      final file = File('${tempDir.path}/$name');
      await file.writeAsBytes(List<int>.filled(bytes, 0), flush: true);
      return file;
    }

    test('is a no-op when under budget', () async {
      await writeCrop('face_1000_0.jpg', 100);
      await writeCrop('face_2000_1.jpg', 100);

      final deleted = await evictFaceCropCache(
        maxBytes: 1000,
        directoryOverride: tempDir,
      );

      expect(deleted, 0);
      expect(tempDir.listSync(), hasLength(2));
    });

    test('evicts oldest-first until back under budget', () async {
      // 3 x 400 = 1200 over a 900 budget -> drop the oldest one.
      final oldest = await writeCrop('face_1000_0.jpg', 400);
      final middle = await writeCrop('face_2000_1.jpg', 400);
      final newest = await writeCrop('face_3000_2.jpg', 400);

      final deleted = await evictFaceCropCache(
        maxBytes: 900,
        directoryOverride: tempDir,
      );

      expect(deleted, 1);
      expect(await oldest.exists(), isFalse);
      expect(await middle.exists(), isTrue);
      expect(await newest.exists(), isTrue);
    });

    // The names embed epoch millis, so a string sort would put a 13-digit
    // timestamp BEFORE a 14-digit one and evict the newer crop first.
    test('orders by parsed millis, not by name string', () async {
      final older = await writeCrop('face_9999999999999_0.jpg', 400);
      final newer = await writeCrop('face_10000000000000_1.jpg', 400);

      final deleted = await evictFaceCropCache(
        maxBytes: 400,
        directoryOverride: tempDir,
      );

      expect(deleted, 1);
      expect(await older.exists(), isFalse, reason: 'smaller millis is older');
      expect(await newer.exists(), isTrue);
    });

    test('leaves unrelated temp files alone', () async {
      await writeCrop('face_1000_0.jpg', 400);
      await writeCrop('face_2000_1.jpg', 400);
      final poster = await writeCrop('poster_5_900.jpg', 400);
      final thumbnail = await writeCrop('abc123.jpg', 400);

      final deleted = await evictFaceCropCache(
        maxBytes: 500,
        directoryOverride: tempDir,
      );

      // Only the two face_* crops are candidates; both go, budget permitting.
      expect(deleted, greaterThan(0));
      expect(await poster.exists(), isTrue);
      expect(await thumbnail.exists(), isTrue);
    });

    test('tolerates a missing directory', () async {
      final missing = Directory('${tempDir.path}/nope');

      final deleted = await evictFaceCropCache(
        maxBytes: 10,
        directoryOverride: missing,
      );

      expect(deleted, 0);
    });
  });

  group('faceCropFilePattern', () {
    test('matches the crop naming used by the detector', () {
      expect(faceCropFilePattern.hasMatch('face_1700000000000_7.jpg'), isTrue);
      expect(faceCropFilePattern.hasMatch('poster_1_2.jpg'), isFalse);
      expect(faceCropFilePattern.hasMatch('face_abc_1.jpg'), isFalse);
      expect(faceCropFilePattern.hasMatch('face_1_2.png'), isFalse);
    });
  });
}
