import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumovault/features/people/data/services/face_detection_service.dart';

/// Applies a scale + rotation + translation to [points], simulating a face
/// photographed at a different size, angle and position.
List<ui.Offset> _transform(
  List<ui.Offset> points, {
  double scale = 1.0,
  double radians = 0.0,
  double dx = 0.0,
  double dy = 0.0,
}) {
  final c = math.cos(radians) * scale;
  final s = math.sin(radians) * scale;
  return [
    for (final p in points)
      ui.Offset(c * p.dx - s * p.dy + dx, s * p.dx + c * p.dy + dy),
  ];
}

void main() {
  group('arcFaceTemplate', () {
    test('returns the canonical 112 template unscaled', () {
      expect(arcFaceTemplate(112), same(arcFaceTemplate112));
      expect(arcFaceTemplate112, hasLength(5));
    });

    test('scales proportionally for other crop sizes', () {
      final t = arcFaceTemplate(224);
      expect(t.first.dx, closeTo(arcFaceTemplate112.first.dx * 2, 1e-9));
      expect(t.first.dy, closeTo(arcFaceTemplate112.first.dy * 2, 1e-9));
    });

    test('places the eyes symmetrically about the nose', () {
      const leftEye = 0, rightEye = 1, nose = 2;
      const t = arcFaceTemplate112;
      final leftGap = t[nose].dx - t[leftEye].dx;
      final rightGap = t[rightEye].dx - t[nose].dx;
      expect(leftGap, closeTo(rightGap, 0.5));
      // Eyes sit above the nose, nose above the mouth.
      expect(t[leftEye].dy, lessThan(t[nose].dy));
      expect(t[nose].dy, lessThan(t[3].dy));
    });
  });

  group('estimateSimilarityTransform', () {
    test('recovers a known scale, rotation and translation exactly', () {
      const src = arcFaceTemplate112;
      final dst = _transform(
        src,
        scale: 2.0,
        radians: math.pi / 6,
        dx: 30,
        dy: -12,
      );

      final t = estimateSimilarityTransform(src, dst)!;

      expect(t.scale, closeTo(2.0, 1e-9));
      for (var i = 0; i < src.length; i++) {
        final mapped = t.apply(src[i].dx, src[i].dy);
        expect(mapped.dx, closeTo(dst[i].dx, 1e-9));
        expect(mapped.dy, closeTo(dst[i].dy, 1e-9));
      }
    });

    test('maps a rotated, off-centre face back onto the template', () {
      // This is the real use: landmarks measured in a photo → template.
      final observed = _transform(
        arcFaceTemplate112,
        scale: 3.4,
        radians: -0.35,
        dx: 512,
        dy: 200,
      );

      final t = estimateSimilarityTransform(observed, arcFaceTemplate112)!;

      for (var i = 0; i < observed.length; i++) {
        final mapped = t.apply(observed[i].dx, observed[i].dy);
        expect(mapped.dx, closeTo(arcFaceTemplate112[i].dx, 1e-6));
        expect(mapped.dy, closeTo(arcFaceTemplate112[i].dy, 1e-6));
      }
    });

    test('inverse undoes apply', () {
      final t = estimateSimilarityTransform(
        arcFaceTemplate112,
        _transform(arcFaceTemplate112, scale: 1.7, radians: 0.9, dx: 5, dy: 9),
      )!;

      final forward = t.apply(42, 17);
      final back = t.inverse(forward.dx, forward.dy);

      expect(back.dx, closeTo(42, 1e-9));
      expect(back.dy, closeTo(17, 1e-9));
    });

    test('fits a least-squares compromise for noisy landmarks', () {
      // A real detector never places all five points perfectly; the fit should
      // still land close, not blow up.
      final noisy = [
        for (var i = 0; i < arcFaceTemplate112.length; i++)
          ui.Offset(
            arcFaceTemplate112[i].dx * 2 + (i.isEven ? 0.8 : -0.8),
            arcFaceTemplate112[i].dy * 2 + (i.isEven ? -0.6 : 0.6),
          ),
      ];

      final t = estimateSimilarityTransform(noisy, arcFaceTemplate112)!;

      for (var i = 0; i < noisy.length; i++) {
        final mapped = t.apply(noisy[i].dx, noisy[i].dy);
        expect(mapped.dx, closeTo(arcFaceTemplate112[i].dx, 1.5));
        expect(mapped.dy, closeTo(arcFaceTemplate112[i].dy, 1.5));
      }
    });

    test('returns null for degenerate point sets', () {
      expect(estimateSimilarityTransform(const [], const []), isNull);
      expect(
        estimateSimilarityTransform(
          const [ui.Offset(1, 1)],
          const [ui.Offset(2, 2)],
        ),
        isNull,
      );
      // All source points coincident — no scale or rotation is recoverable.
      expect(
        estimateSimilarityTransform(
          List.filled(5, const ui.Offset(3, 3)),
          arcFaceTemplate112,
        ),
        isNull,
      );
    });
  });

  group('warpFace', () {
    /// A source image with a distinctly coloured 20×20 marker at [markerX],
    /// [markerY] on a black field.
    img.Image sourceWithMarker(int markerX, int markerY) {
      final src = img.Image(width: 400, height: 400);
      img.fill(src, color: img.ColorRgb8(0, 0, 0));
      img.fillRect(
        src,
        x1: markerX,
        y1: markerY,
        x2: markerX + 19,
        y2: markerY + 19,
        color: img.ColorRgb8(255, 0, 0),
      );
      return src;
    }

    test('produces an image of the requested size', () {
      final src = sourceWithMarker(100, 100);
      final t = estimateSimilarityTransform(
        _transform(arcFaceTemplate112, scale: 2, dx: 80, dy: 80),
        arcFaceTemplate112,
      )!;

      final out = warpFace(src, t, 112);

      expect(out.width, 112);
      expect(out.height, 112);
    });

    test('lands the face landmarks on the template positions', () {
      // Put a marker where the left eye is in a scaled, shifted face, then
      // check the warp moves it to the template's left-eye position.
      final observed = _transform(
        arcFaceTemplate112,
        scale: 2.0,
        dx: 100,
        dy: 60,
      );
      final leftEye = observed.first;
      final src = sourceWithMarker(
        leftEye.dx.round() - 10,
        leftEye.dy.round() - 10,
      );

      final t = estimateSimilarityTransform(observed, arcFaceTemplate112)!;
      final out = warpFace(src, t, 112);

      final target = arcFaceTemplate112.first;
      final atEye = out.getPixel(target.dx.round(), target.dy.round());
      expect(atEye.r, greaterThan(200));
      expect(atEye.g, lessThan(60));

      // And the opposite corner of the crop is still background.
      final corner = out.getPixel(111, 111);
      expect(corner.r, lessThan(60));
    });

    test('cancels in-plane rotation', () {
      // The same face rotated 25° should warp to the same template positions.
      final upright = _transform(
        arcFaceTemplate112,
        scale: 2.0,
        dx: 120,
        dy: 90,
      );
      final rotated = _transform(
        arcFaceTemplate112,
        scale: 2.0,
        radians: 25 * math.pi / 180,
        dx: 120,
        dy: 90,
      );

      final nose = arcFaceTemplate112[2];
      for (final landmarks in [upright, rotated]) {
        final src = sourceWithMarker(
          landmarks[2].dx.round() - 10,
          landmarks[2].dy.round() - 10,
        );
        final t = estimateSimilarityTransform(landmarks, arcFaceTemplate112)!;
        final out = warpFace(src, t, 112);

        final atNose = out.getPixel(nose.dx.round(), nose.dy.round());
        expect(
          atNose.r,
          greaterThan(200),
          reason: 'nose marker should land on the template nose position',
        );
      }
    });

    test('clamps at the edges rather than sampling out of bounds', () {
      // A transform that pulls most of the crop outside the source must not
      // throw — out-of-range samples clamp to the border.
      final src = sourceWithMarker(0, 0);
      final t = estimateSimilarityTransform(
        _transform(arcFaceTemplate112, scale: 0.05, dx: -200, dy: -200),
        arcFaceTemplate112,
      )!;

      expect(() => warpFace(src, t, 112), returnsNormally);
    });
  });
}
