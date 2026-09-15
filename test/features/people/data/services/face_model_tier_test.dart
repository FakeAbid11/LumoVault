import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/people/data/services/face_detection_service.dart';

void main() {
  group('selectDetectorAsset', () {
    test('8+ core SoCs get the higher-recall SCRFD-2.5G', () {
      expect(selectDetectorAsset(processorCount: 8), contains('2_5g'));
      expect(selectDetectorAsset(processorCount: 10), contains('2_5g'));
    });

    test(
      'fewer cores keep the tiny 500M model (low-end behavior unchanged)',
      () {
        expect(
          selectDetectorAsset(processorCount: 4),
          FaceDetectionConfig.defaultDetectorAsset,
        );
        expect(
          selectDetectorAsset(processorCount: 6),
          FaceDetectionConfig.defaultDetectorAsset,
        );
      },
    );

    test('the tier threshold is exactly 8 cores', () {
      expect(
        selectDetectorAsset(processorCount: 7),
        FaceDetectionConfig.defaultDetectorAsset,
      );
      expect(
        selectDetectorAsset(processorCount: 8),
        isNot(FaceDetectionConfig.defaultDetectorAsset),
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
  });
}
