import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/services/label_map.dart';

/// Guards the invariant that made every AI label wrong before regeneration:
/// the map must cover the FULL 0-999 range of the official ImageNet-1k
/// class order that tool/export_classifier.py (timm mobileone_s2) emits.
/// The hand-written map this replaced had 538 entries at fabricated indices
/// — e.g. cats (281-285) were mapped to 'shed'/'garage'/'tent'.
void main() {
  test('covers every class index 0..999', () {
    expect(imageNetLabels.length, 1000);
    for (var i = 0; i < 1000; i++) {
      expect(imageNetLabels.containsKey(i), isTrue, reason: 'missing $i');
      expect(imageNetLabels[i]!.trim(), isNotEmpty, reason: 'empty $i');
    }
  });

  test('anchors follow the canonical torchvision/WordNet order', () {
    expect(imageNetLabels[0], 'tench');
    expect(imageNetLabels[1], 'goldfish');
    expect(imageNetLabels[2], 'great white shark');
    expect(imageNetLabels[10], 'brambling');
    expect(imageNetLabels[12], 'house finch');
    expect(imageNetLabels[207], 'golden retriever');
    // The five cat classes the bug report is about:
    expect(imageNetLabels[281], 'tabby');
    expect(imageNetLabels[282], 'tiger cat');
    expect(imageNetLabels[283], 'Persian cat');
    expect(imageNetLabels[284], 'Siamese cat');
    expect(imageNetLabels[285], 'Egyptian cat');
    expect(imageNetLabels[291], 'lion');
    expect(imageNetLabels[292], 'tiger');
    expect(imageNetLabels[999], 'toilet tissue');
  });

  test('dog breeds occupy the canonical 151-290 region, not 60-86', () {
    // The old map placed breeds at 60-86 (actually fish/reptiles/insects).
    expect(imageNetLabels[207], contains('retriever'));
    expect(imageNetLabels[258], 'Samoyed');
  });
}
