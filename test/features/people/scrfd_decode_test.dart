import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/people/data/services/face_detection_service.dart';

/// Builds a score list of [rows] entries with [hits] mapping row index → score.
List<double> _scores(int rows, Map<int, double> hits) {
  return List<double>.generate(rows, (i) => hits[i] ?? 0.0);
}

/// Builds a box-distance list of `rows * 4` entries, with [hits] mapping a row
/// index to its (left, top, right, bottom) distances in stride units.
List<double> _boxes(int rows, Map<int, List<double>> hits) {
  final out = List<double>.filled(rows * 4, 0.0);
  hits.forEach((row, d) => out.setRange(row * 4, row * 4 + 4, d));
  return out;
}

/// Builds a keypoint list of `rows * 10` entries, with [hits] mapping a row
/// index to its five (x, y) offsets from the anchor centre, in stride units.
List<double> _kps(int rows, Map<int, List<double>> hits) {
  final out = List<double>.filled(rows * 10, 0.0);
  hits.forEach((row, d) => out.setRange(row * 10, row * 10 + 10, d));
  return out;
}

void main() {
  group('resolveScrfdLayout', () {
    test('maps two-anchor row counts for a 640 input to their stride', () {
      // 80×80 cells × 2, 40×40 × 2, 20×20 × 2.
      expect(resolveScrfdLayout(12800, 640)?.stride, 8);
      expect(resolveScrfdLayout(12800, 640)?.numAnchors, 2);
      expect(resolveScrfdLayout(3200, 640)?.stride, 16);
      expect(resolveScrfdLayout(800, 640)?.stride, 32);
      expect(resolveScrfdLayout(800, 640)?.numAnchors, 2);
    });

    test('maps single-anchor row counts too', () {
      expect(resolveScrfdLayout(6400, 640)?.stride, 8);
      expect(resolveScrfdLayout(6400, 640)?.numAnchors, 1);
      expect(resolveScrfdLayout(1600, 640)?.stride, 16);
      expect(resolveScrfdLayout(400, 640)?.stride, 32);
    });

    test('returns null for counts that match no FPN level', () {
      expect(resolveScrfdLayout(1234, 640), isNull);
      expect(resolveScrfdLayout(0, 640), isNull);
      expect(resolveScrfdLayout(-1, 640), isNull);
      expect(resolveScrfdLayout(12800, 0), isNull);
    });
  });

  group('decodeScrfdOutputs', () {
    test('turns anchor distances into a box at the anchor centre', () {
      // Stride 32 → 20×20 grid, 2 anchors per cell. Cell (x=5, y=3) is
      // cell index 3 * 20 + 5 = 65, so its first anchor is row 130.
      // Anchor centre = (5 * 32, 3 * 32) = (160, 96).
      // Distances of 1 stride each → LTRB (128, 64, 192, 128).
      const row = 130;
      final decoded = decodeScrfdOutputs(
        scoresByStride: {
          32: _scores(800, {row: 0.9}),
        },
        bboxesByStride: {
          32: _boxes(800, {
            row: [1, 1, 1, 1],
          }),
        },
        anchorsByStride: {32: 2},
        inputSize: 640,
        scoreThreshold: 0.5,
        scaleX: 1.0,
        scaleY: 1.0,
      );

      expect(decoded, hasLength(1));
      expect(decoded.single.box, const ui.Rect.fromLTRB(128, 64, 192, 128));
      expect(decoded.single.score, 0.9);
    });

    test('scales boxes from detector space back onto the source image', () {
      const row = 130;
      final decoded = decodeScrfdOutputs(
        scoresByStride: {
          32: _scores(800, {row: 0.8}),
        },
        bboxesByStride: {
          32: _boxes(800, {
            row: [1, 1, 1, 1],
          }),
        },
        anchorsByStride: {32: 2},
        inputSize: 640,
        scoreThreshold: 0.5,
        // A 1920×1280 source downscaled to 640×640.
        scaleX: 3.0,
        scaleY: 2.0,
      );

      expect(decoded.single.box, const ui.Rect.fromLTRB(384, 128, 576, 256));
    });

    test('drops rows below the score threshold', () {
      final decoded = decodeScrfdOutputs(
        scoresByStride: {
          32: _scores(800, {10: 0.49, 130: 0.51}),
        },
        bboxesByStride: {
          32: _boxes(800, {
            10: [1, 1, 1, 1],
            130: [1, 1, 1, 1],
          }),
        },
        anchorsByStride: {32: 2},
        inputSize: 640,
        scoreThreshold: 0.5,
        scaleX: 1.0,
        scaleY: 1.0,
      );

      expect(decoded, hasLength(1));
      expect(decoded.single.score, closeTo(0.51, 1e-9));
    });

    test('drops degenerate boxes with zero or negative extent', () {
      final decoded = decodeScrfdOutputs(
        scoresByStride: {
          32: _scores(800, {130: 0.9}),
        },
        bboxesByStride: {
          32: _boxes(800, {
            // right/bottom distances of 0 collapse the box onto the anchor.
            130: [0, 0, 0, 0],
          }),
        },
        anchorsByStride: {32: 2},
        inputSize: 640,
        scoreThreshold: 0.5,
        scaleX: 1.0,
        scaleY: 1.0,
      );

      expect(decoded, isEmpty);
    });

    test('decodes every stride that has both score and box tensors', () {
      final decoded = decodeScrfdOutputs(
        scoresByStride: {
          8: _scores(12800, {0: 0.9}),
          16: _scores(3200, {0: 0.9}),
          32: _scores(800, {0: 0.9}),
        },
        bboxesByStride: {
          8: _boxes(12800, {
            0: [1, 1, 1, 1],
          }),
          16: _boxes(3200, {
            0: [1, 1, 1, 1],
          }),
          32: _boxes(800, {
            0: [1, 1, 1, 1],
          }),
        },
        anchorsByStride: {8: 2, 16: 2, 32: 2},
        inputSize: 640,
        scoreThreshold: 0.5,
        scaleX: 1.0,
        scaleY: 1.0,
      );

      // Row 0 of each level sits at anchor centre (0, 0); a distance of one
      // stride on each side makes the box 2 × stride wide, so each FPN level
      // yields a distinctly larger box.
      expect(
        decoded.map((e) => e.box.width).toList(),
        containsAll(<double>[16, 32, 64]),
      );
    });

    test('ignores a stride whose box tensor is missing', () {
      final decoded = decodeScrfdOutputs(
        scoresByStride: {
          32: _scores(800, {130: 0.9}),
        },
        bboxesByStride: const {},
        anchorsByStride: {32: 2},
        inputSize: 640,
        scoreThreshold: 0.5,
        scaleX: 1.0,
        scaleY: 1.0,
      );

      expect(decoded, isEmpty);
    });
  });

  group('decodeScrfdOutputs landmarks', () {
    test('has no landmarks when no keypoint tensor is supplied', () {
      final decoded = decodeScrfdOutputs(
        scoresByStride: {
          32: _scores(800, {130: 0.9}),
        },
        bboxesByStride: {
          32: _boxes(800, {
            130: [1, 1, 1, 1],
          }),
        },
        anchorsByStride: {32: 2},
        inputSize: 640,
        scoreThreshold: 0.5,
        scaleX: 1.0,
        scaleY: 1.0,
      );

      expect(decoded.single.landmarks, isEmpty);
    });

    test('decodes keypoints as signed offsets from the anchor centre', () {
      // Row 130 at stride 32 → anchor centre (160, 96). Keypoint offsets are
      // added in both axes, unlike the box's left/top distances.
      const row = 130;
      final decoded = decodeScrfdOutputs(
        scoresByStride: {
          32: _scores(800, {row: 0.9}),
        },
        bboxesByStride: {
          32: _boxes(800, {
            row: [1, 1, 1, 1],
          }),
        },
        kpsByStride: {
          32: _kps(800, {
            row: [
              -1, -1, // left eye  → (128, 64)
              1, -1, //  right eye → (192, 64)
              0, 0, //   nose      → (160, 96)
              -1, 1, //  left mouth  → (128, 128)
              1, 1, //   right mouth → (192, 128)
            ],
          }),
        },
        anchorsByStride: {32: 2},
        inputSize: 640,
        scoreThreshold: 0.5,
        scaleX: 1.0,
        scaleY: 1.0,
      );

      expect(decoded.single.landmarks, [
        const ui.Offset(128, 64),
        const ui.Offset(192, 64),
        const ui.Offset(160, 96),
        const ui.Offset(128, 128),
        const ui.Offset(192, 128),
      ]);
    });

    test('scales landmarks onto the source image alongside the box', () {
      const row = 130;
      final decoded = decodeScrfdOutputs(
        scoresByStride: {
          32: _scores(800, {row: 0.9}),
        },
        bboxesByStride: {
          32: _boxes(800, {
            row: [1, 1, 1, 1],
          }),
        },
        kpsByStride: {
          32: _kps(800, {
            row: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
          }),
        },
        anchorsByStride: {32: 2},
        inputSize: 640,
        scoreThreshold: 0.5,
        scaleX: 3.0,
        scaleY: 2.0,
      );

      // Anchor centre (160, 96) × (3, 2) = (480, 192).
      expect(decoded.single.landmarks.first, const ui.Offset(480, 192));
    });

    test('skips landmarks when the keypoint tensor is truncated', () {
      final decoded = decodeScrfdOutputs(
        scoresByStride: {
          32: _scores(800, {130: 0.9}),
        },
        bboxesByStride: {
          32: _boxes(800, {
            130: [1, 1, 1, 1],
          }),
        },
        // Only 10 rows of keypoints for 800 rows of scores.
        kpsByStride: {32: _kps(10, const {})},
        anchorsByStride: {32: 2},
        inputSize: 640,
        scoreThreshold: 0.5,
        scaleX: 1.0,
        scaleY: 1.0,
      );

      // The box still survives — a missing keypoint just means no alignment.
      expect(decoded, hasLength(1));
      expect(decoded.single.landmarks, isEmpty);
    });
  });
}
