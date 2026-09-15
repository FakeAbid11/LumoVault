import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/services/image_classifier_service.dart';

/// Logits vector for a canonical class index (ImageNet-1k order).
List<double> _logitsFor(Map<int, double> scores) {
  final v = List<double>.filled(1000, 0.0);
  scores.forEach((k, val) => v[k] = val);
  return v;
}

void main() {
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
