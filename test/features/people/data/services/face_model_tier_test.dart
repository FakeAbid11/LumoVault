import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/people/data/services/face_detection_service.dart';

/// Guards the SINGLE-detector state of the People pipeline.
///
/// There used to be a `selectDetectorAsset(processorCount:)` that gave 8+
/// core devices scrfd_2_5g_kps_fp16.onnx. That asset was a 1.6 MB truncated
/// placeholder — smaller than the 2.5 MB det_500m it was meant to upgrade —
/// so every high-core device failed to load it, silently fell back to 500M
/// behind a debug-only log, and the "adaptive tiering" delivered nothing
/// while hiding a broken asset. The branch and the asset are gone.
///
/// If tiering is ever re-added with a real export, do it together with an
/// asset-integrity test that loads the model, so a placeholder can't ship
/// behind a silent fallback again.
void main() {
  group('detector configuration', () {
    test('the only detector is the 500M SCRFD', () {
      expect(
        FaceDetectionConfig.defaultDetectorAsset,
        'assets/models/det_500m.onnx',
      );
    });

    test(
      'default config points at the 500M asset with the canonical threshold',
      () {
        const config = FaceDetectionConfig();
        expect(config.detectorAsset, 'assets/models/det_500m.onnx');
        expect(config.scoreThreshold, 0.5);
      },
    );

    test('the 2.5G placeholder is not referenced by any default', () {
      expect(FaceDetectionConfig.defaultDetectorAsset, isNot(contains('2_5g')));
    });
  });
}
