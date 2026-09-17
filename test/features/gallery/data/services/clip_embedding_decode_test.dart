import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumovault/features/gallery/data/services/clip_embedding_service.dart';

/// A solid-color PNG of [size]×[size] — PNG is lossless, so the decoded pixel
/// is exactly what we encoded, which makes the [0,1] scaling assertions exact.
Uint8List _solidColorPng(int size, int r, int g, int b) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return img.encodePng(image);
}

void main() {
  group('decodeAndPreprocessForEmbedding', () {
    const size = 256;
    const plane = size * size; // CHW: R [0, plane), G [plane, 2*plane), …

    test('emits a 3×256×256 CHW tensor with pixels scaled to [0, 1]', () {
      final tensor = decodeAndPreprocessForEmbedding((
        _solidColorPng(64, 255, 128, 0),
        size,
      ));

      expect(tensor, isNotNull);
      expect(tensor!.length, 3 * plane);
      // No mean/std shift — the model's own normalization is identity — so a
      // channel's value is just pixel/255. Solid color ⇒ every element of a
      // plane equals its first element.
      expect(tensor[0], closeTo(1.0, 1e-5));
      expect(tensor[plane], closeTo(128 / 255, 1e-5));
      expect(tensor[2 * plane], closeTo(0.0, 1e-5));
    });

    test('stays within [0, 1] across a mid-gray image', () {
      final tensor = decodeAndPreprocessForEmbedding((
        _solidColorPng(17, 100, 150, 200),
        size,
      ))!;

      expect(tensor.length, 3 * plane);
      for (final v in tensor) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
      expect(tensor[0], closeTo(100 / 255, 1e-4));
    });

    test('resizes non-square input to the exact model input size', () {
      final tensor = decodeAndPreprocessForEmbedding((
        _solidColorPng(33, 10, 200, 77),
        size,
      ))!;

      expect(tensor.length, 3 * plane);
      // A solid color resizes to the same solid color, so each CHW plane is
      // constant. Sample first/middle/last of each plane.
      for (final i in [0, plane ~/ 2, plane - 1]) {
        expect(tensor[i], closeTo(10 / 255, 1e-4));
        expect(tensor[plane + i], closeTo(200 / 255, 1e-4));
        expect(tensor[2 * plane + i], closeTo(77 / 255, 1e-4));
      }
    });

    test('returns null for undecodable bytes', () {
      expect(decodeAndPreprocessForEmbedding((Uint8List(64), size)), isNull);
    });

    test('is resolvable as a compute() isolate entry point', () async {
      // Exercises the real isolate path: the record argument must cross the
      // boundary and the Float32List must come back. (In an AOT build this is
      // also what breaks first if the vm:entry-point pragma is dropped.)
      final tensor = await compute(
        decodeAndPreprocessForEmbedding,
        (_solidColorPng(48, 30, 60, 90), size),
      );
      expect(tensor, isNotNull);
      expect(tensor!.length, 3 * plane);
    });
  });
}
