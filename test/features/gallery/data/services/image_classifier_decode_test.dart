import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumovault/features/gallery/data/services/image_classifier_service.dart';

/// Logits vector for a canonical class index (ImageNet-1k order).
List<double> _logitsFor(Map<int, double> scores) {
  final v = List<double>.filled(1000, 0.0);
  scores.forEach((k, val) => v[k] = val);
  return v;
}

/// A solid-color PNG of [size]×[size] — PNG is lossless, so the decoded pixel
/// is exactly what we encoded, which makes the normalization assertions exact.
Uint8List _solidColorPng(int size, int r, int g, int b) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return img.encodePng(image);
}

void main() {
  group('decodeAndPreprocessForClassification', () {
    const plane = 224 * 224; // CHW: R occupies [0, plane), G [plane, 2*plane)…

    test('emits a 3×224×224 CHW tensor with ImageNet normalization', () {
      final tensor = decodeAndPreprocessForClassification((
        _solidColorPng(64, 255, 128, 0),
        224,
      ));

      expect(tensor, isNotNull);
      expect(tensor!.length, 3 * 224 * 224);
      // (pixel/255 - mean) / std per channel — solid color, so every element
      // of a plane equals the plane's first element.
      expect(tensor[0], closeTo((1.00 - 0.485) / 0.229, 1e-5));
      expect(tensor[plane], closeTo((128 / 255 - 0.456) / 0.224, 1e-5));
      expect(tensor[2 * plane], closeTo((0.0 - 0.406) / 0.225, 1e-5));
    });

    test('resizes non-square input to the exact model input size', () {
      final tensor = decodeAndPreprocessForClassification((
        _solidColorPng(33, 10, 200, 77),
        224,
      ))!;

      expect(tensor.length, 3 * 224 * 224);
      // A solid color resizes to the same solid color, so each CHW plane is
      // constant. Sample first/middle/last of each plane.
      for (final i in [0, plane ~/ 2, plane - 1]) {
        expect(tensor[i], closeTo((10 / 255 - 0.485) / 0.229, 1e-4));
        expect(tensor[plane + i], closeTo((200 / 255 - 0.456) / 0.224, 1e-4));
        expect(
          tensor[2 * plane + i],
          closeTo((77 / 255 - 0.406) / 0.225, 1e-4),
        );
      }
    });

    test('returns null for undecodable bytes', () {
      expect(
        decodeAndPreprocessForClassification((Uint8List(64), 224)),
        isNull,
      );
    });

    test('is resolvable as a compute() isolate entry point', () async {
      // Exercises the real isolate path: the record argument must cross the
      // boundary and the Float32List must come back. (In an AOT build this is
      // also what breaks first if the vm:entry-point pragma is dropped.)
      final tensor = await compute(decodeAndPreprocessForClassification, (
        _solidColorPng(48, 30, 60, 90),
        224,
      ));
      expect(tensor, isNotNull);
      expect(tensor!.length, 3 * 224 * 224);
    });
  });

  group('decodeTopLabels', () {
    test('a confident cat photo gets its breed AND the generic cat tag', () {
      // 281 = 'tabby' — no substring relation to "cat", which is exactly why
      // searching "cat" found nothing before the expansion existed.
      final labels = ImageClassifierService.decodeTopLabels(
        _logitsFor({281: 10.0}),
      );
      expect(labels, contains('ai_tabby'));
      expect(labels, contains('ai_cat'));
    });

    test('sibling cat classes co-tag under the lowered threshold', () {
      final labels = ImageClassifierService.decodeTopLabels(
        _logitsFor({281: 6.0, 283: 5.0, 285: 4.9}),
      );
      expect(labels, containsAll(['ai_tabby', 'ai_persian_cat']));
      expect(labels, contains('ai_cat'));
      expect(labels.length, lessThanOrEqualTo(4));
    });

    test('dog breeds expand to ai_dog', () {
      final labels = ImageClassifierService.decodeTopLabels(
        _logitsFor({207: 10.0}), // golden retriever
      );
      expect(labels, containsAll(['ai_golden_retriever', 'ai_dog']));
    });

    test(
      'word-boundary match: catamaran and caterpillar-like names stay fish/vehicles, not cats',
      () {
        final labels = ImageClassifierService.decodeTopLabels(
          _logitsFor({484: 10.0}), // catamaran (boat)
        );
        expect(labels, contains('ai_catamaran'));
        expect(labels, contains('ai_boat'));
        expect(labels, isNot(contains('ai_cat')));
      },
    );

    test('multi-word names are underscore-joined and expand', () {
      final labels = ImageClassifierService.decodeTopLabels(
        _logitsFor({2: 10.0}), // great white shark
      );
      expect(labels, contains('ai_great_white_shark'));
      expect(labels, contains('ai_fish'));
    });

    test('nothing above the threshold yields no labels', () {
      final labels = ImageClassifierService.decodeTopLabels(
        _logitsFor({42: 0.05}),
      );
      expect(labels, isEmpty);
    });

    test('empty logits are safe', () {
      expect(ImageClassifierService.decodeTopLabels(const []), isEmpty);
    });
  });
}
