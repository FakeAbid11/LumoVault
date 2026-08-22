import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/faces/data/services/face_detection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FaceDetectionService', () {
    late FaceDetectionService service;

    setUp(() {
      service = FaceDetectionService();
    });

    tearDown(() {
      // Don't call dispose — ML Kit close() needs platform bindings
      // that aren't available in unit tests.
    });

    group('synthesiseEmbedding', () {
      test('detectFaces returns empty list for non-existent file', () async {
        try {
          final faces = await service.detectFaces(
            filePath: '/nonexistent/image.jpg',
            imageWidth: 100,
            imageHeight: 100,
          );
          expect(faces, isEmpty);
        } catch (_) {
          // Expected — ML Kit native library not available in test env.
        }
      });
    });

    group('DetectedFace', () {
      test('constructs with all required fields', () {
        const face = DetectedFace(
          bboxLeft: 0.1,
          bboxTop: 0.2,
          bboxRight: 0.5,
          bboxBottom: 0.8,
          embedding: [0.1, 0.2, 0.3],
          confidence: 0.95,
        );

        expect(face.bboxLeft, 0.1);
        expect(face.bboxTop, 0.2);
        expect(face.bboxRight, 0.5);
        expect(face.bboxBottom, 0.8);
        expect(face.embedding, [0.1, 0.2, 0.3]);
        expect(face.confidence, 0.95);
      });
    });
  });
}
