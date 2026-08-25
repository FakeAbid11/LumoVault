import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// A detected face with bounding box, embedding, and confidence.
class DetectedFace {
  const DetectedFace({
    required this.boundingBox,
    required this.embedding,
    this.confidence = 0.0,
    this.landmarks = const [],
  });

  final ui.Rect boundingBox;
  final List<double> embedding;
  final double confidence;

  /// The five facial landmarks in source-image pixels, ordered left eye,
  /// right eye, nose, left mouth corner, right mouth corner.
  ///
  /// Empty when the detector export has no keypoint head, in which case the
  /// embedding came from an unaligned square crop.
  final List<ui.Offset> landmarks;
}

/// Faces found in one image, plus the pixel size of the decoded image the
/// bounding boxes are expressed in.
///
/// Callers must normalise boxes against [imageWidth]/[imageHeight] rather than
/// the gallery's own asset dimensions — the two disagree whenever a photo
/// carries an EXIF rotation.
class FaceDetectionResult {
  const FaceDetectionResult({
    required this.faces,
    required this.thumbnailPaths,
    required this.imageWidth,
    required this.imageHeight,
  });

  const FaceDetectionResult.empty()
    : faces = const [],
      thumbnailPaths = const [],
      imageWidth = 0,
      imageHeight = 0;

  final List<DetectedFace> faces;
  final List<String?> thumbnailPaths;
  final int imageWidth;
  final int imageHeight;
}

// ---------------------------------------------------------------------------
// Face alignment
//
// ArcFace was trained on faces warped onto a fixed 5-point template, so the
// eyes, nose and mouth land on the same pixels for every face. Feeding it a
// plain box crop instead leaves in-plane rotation and scale variation that the
// embedding then has to absorb, which spreads one person's embeddings apart
// and makes clustering split them. Warping to the template first removes that
// variation — it is the single biggest quality lever in this pipeline.
// ---------------------------------------------------------------------------

/// InsightFace's `arcface_dst` template: where the five landmarks must land in
/// a 112×112 crop, ordered left eye, right eye, nose, left mouth, right mouth.
const List<ui.Offset> arcFaceTemplate112 = [
  ui.Offset(38.2946, 51.6963),
  ui.Offset(73.5318, 51.5014),
  ui.Offset(56.0252, 71.7366),
  ui.Offset(41.5493, 92.3655),
  ui.Offset(70.7299, 92.2041),
];

/// The template scaled to a [size]×[size] crop.
List<ui.Offset> arcFaceTemplate(int size) {
  if (size == 112) return arcFaceTemplate112;
  final s = size / 112.0;
  return [for (final p in arcFaceTemplate112) ui.Offset(p.dx * s, p.dy * s)];
}

/// A 2-D similarity transform — uniform scale, rotation and translation, no
/// shear: `(x, y) → (a·x − b·y + tx, b·x + a·y + ty)`.
class SimilarityTransform {
  const SimilarityTransform({
    required this.a,
    required this.b,
    required this.tx,
    required this.ty,
  });

  final double a;
  final double b;
  final double tx;
  final double ty;

  /// Uniform scale factor applied by the transform.
  double get scale => sqrt(a * a + b * b);

  /// Maps a point forward, from source into destination space.
  ui.Offset apply(double x, double y) =>
      ui.Offset(a * x - b * y + tx, b * x + a * y + ty);

  /// Maps a destination point back into source space.
  ///
  /// This is the direction a warp actually needs: for each output pixel, find
  /// where to sample the input.
  ui.Offset inverse(double x, double y) {
    final det = a * a + b * b;
    final px = x - tx;
    final py = y - ty;
    return ui.Offset((a * px + b * py) / det, (-b * px + a * py) / det);
  }
}

/// Least-squares similarity transform mapping [src] onto [dst].
///
/// This is the closed form of Umeyama's algorithm for the 2-D
/// scale-plus-rotation case — the same fit `skimage.transform.SimilarityTransform`
/// (and therefore InsightFace's `norm_crop`) performs, without needing an SVD:
/// the model is linear in `(a, b, tx, ty)`, so the normal equations solve
/// directly. Returns null if the points are degenerate (fewer than two, or all
/// coincident), which no real 5-point face landmark set is.
SimilarityTransform? estimateSimilarityTransform(
  List<ui.Offset> src,
  List<ui.Offset> dst,
) {
  final n = min(src.length, dst.length);
  if (n < 2) return null;

  var meanSx = 0.0;
  var meanSy = 0.0;
  var meanDx = 0.0;
  var meanDy = 0.0;
  for (var i = 0; i < n; i++) {
    meanSx += src[i].dx;
    meanSy += src[i].dy;
    meanDx += dst[i].dx;
    meanDy += dst[i].dy;
  }
  meanSx /= n;
  meanSy /= n;
  meanDx /= n;
  meanDy /= n;

  var numA = 0.0;
  var numB = 0.0;
  var den = 0.0;
  for (var i = 0; i < n; i++) {
    final sx = src[i].dx - meanSx;
    final sy = src[i].dy - meanSy;
    final dx = dst[i].dx - meanDx;
    final dy = dst[i].dy - meanDy;
    numA += sx * dx + sy * dy;
    numB += sx * dy - sy * dx;
    den += sx * sx + sy * sy;
  }
  if (den <= 0) return null;

  final a = numA / den;
  final b = numB / den;
  if (a == 0 && b == 0) return null;

  return SimilarityTransform(
    a: a,
    b: b,
    tx: meanDx - (a * meanSx - b * meanSy),
    ty: meanDy - (b * meanSx + a * meanSy),
  );
}

/// Warps [src] through [transform] into a [size]×[size] image, sampling
/// bilinearly and clamping at the edges.
///
/// Integer output coordinates are treated as pixel centres, matching
/// `cv2.warpAffine` so the result lines up with InsightFace's `norm_crop`.
img.Image warpFace(img.Image src, SimilarityTransform transform, int size) {
  final out = img.Image(width: size, height: size);
  final maxX = (src.width - 1).toDouble();
  final maxY = (src.height - 1).toDouble();

  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final s = transform.inverse(x.toDouble(), y.toDouble());
      final sx = s.dx.clamp(0.0, maxX);
      final sy = s.dy.clamp(0.0, maxY);

      final x0 = sx.floor();
      final y0 = sy.floor();
      final x1 = min(x0 + 1, src.width - 1);
      final y1 = min(y0 + 1, src.height - 1);
      final fx = sx - x0;
      final fy = sy - y0;

      final p00 = src.getPixel(x0, y0);
      final p10 = src.getPixel(x1, y0);
      final p01 = src.getPixel(x0, y1);
      final p11 = src.getPixel(x1, y1);

      double lerp(num a00, num a10, num a01, num a11) {
        final top = a00 + (a10 - a00) * fx;
        final bottom = a01 + (a11 - a01) * fx;
        return top + (bottom - top) * fy;
      }

      out.setPixelRgb(
        x,
        y,
        lerp(p00.r, p10.r, p01.r, p11.r),
        lerp(p00.g, p10.g, p01.g, p11.g),
        lerp(p00.b, p10.b, p01.b, p11.b),
      );
    }
  }

  return out;
}

// ---------------------------------------------------------------------------
// SCRFD output decoding
//
// SCRFD is an anchor-based detector: each FPN level predicts, per anchor,
// a face score, four *distances* (left/top/right/bottom) from the anchor
// centre, and five landmark *offsets* from it — all in stride units. Boxes and
// landmarks only exist after combining those with the anchor grid; the raw
// tensors are not coordinates.
// ---------------------------------------------------------------------------

/// FPN strides of the bundled `det_500m.onnx` export.
const List<int> scrfdStrides = [8, 16, 32];

/// One decoded SCRFD detection in source-image coordinates.
class ScrfdDetection {
  const ScrfdDetection({
    required this.box,
    required this.score,
    this.landmarks = const [],
  });

  final ui.Rect box;
  final double score;

  /// Five landmarks (left eye, right eye, nose, left mouth, right mouth), or
  /// empty when the export carries no keypoint head.
  final List<ui.Offset> landmarks;
}

/// Which FPN level and anchor count produced a tensor with [rows] anchor rows.
class ScrfdLayout {
  const ScrfdLayout({required this.stride, required this.numAnchors});

  final int stride;
  final int numAnchors;
}

/// Resolves the FPN level for an output tensor with [rows] anchor rows.
///
/// For a 640×640 input the row counts are unambiguous: 12800/3200/800 for
/// two anchors per cell at strides 8/16/32, and 6400/1600/400 for one.
ScrfdLayout? resolveScrfdLayout(int rows, int inputSize) {
  if (rows <= 0 || inputSize <= 0) return null;
  for (final stride in scrfdStrides) {
    final grid = inputSize ~/ stride;
    final cells = grid * grid;
    if (cells == 0) continue;
    for (final numAnchors in const [2, 1]) {
      if (rows == cells * numAnchors) {
        return ScrfdLayout(stride: stride, numAnchors: numAnchors);
      }
    }
  }
  return null;
}

/// Decodes SCRFD score/box-distance/keypoint tensors into detections in
/// *source image* coordinates, keeping anything at or above [scoreThreshold].
///
/// Anchor rows are ordered (row, column, anchor) and anchor centres sit at
/// `(x * stride, y * stride)` in the detector's [inputSize] square space;
/// [scaleX]/[scaleY] map that space back onto the original image.
///
/// [kpsByStride] is optional: exports without a keypoint head still yield
/// boxes, just with empty [ScrfdDetection.landmarks].
List<ScrfdDetection> decodeScrfdOutputs({
  required Map<int, List<double>> scoresByStride,
  required Map<int, List<double>> bboxesByStride,
  required Map<int, int> anchorsByStride,
  required int inputSize,
  required double scoreThreshold,
  required double scaleX,
  required double scaleY,
  Map<int, List<double>> kpsByStride = const {},
}) {
  final results = <ScrfdDetection>[];

  for (final stride in scrfdStrides) {
    final scores = scoresByStride[stride];
    final boxes = bboxesByStride[stride];
    if (scores == null || boxes == null) continue;
    final kps = kpsByStride[stride];
    final numAnchors = anchorsByStride[stride] ?? 1;
    if (numAnchors <= 0) continue;
    final grid = inputSize ~/ stride;
    if (grid <= 0) continue;

    for (var i = 0; i < scores.length; i++) {
      if (scores[i] < scoreThreshold) continue;
      if (i * 4 + 3 >= boxes.length) break;

      final cell = i ~/ numAnchors;
      final anchorX = (cell % grid) * stride;
      final anchorY = (cell ~/ grid) * stride;

      final left = anchorX - boxes[i * 4] * stride;
      final top = anchorY - boxes[i * 4 + 1] * stride;
      final right = anchorX + boxes[i * 4 + 2] * stride;
      final bottom = anchorY + boxes[i * 4 + 3] * stride;
      if (right <= left || bottom <= top) continue;

      // Keypoints are signed offsets from the anchor centre, so they are added
      // in both axes — unlike the box's left/top distances, which subtract.
      var landmarks = const <ui.Offset>[];
      if (kps != null && i * 10 + 9 < kps.length) {
        landmarks = [
          for (var n = 0; n < 5; n++)
            ui.Offset(
              (anchorX + kps[i * 10 + n * 2] * stride) * scaleX,
              (anchorY + kps[i * 10 + n * 2 + 1] * stride) * scaleY,
            ),
        ];
      }

      results.add(
        ScrfdDetection(
          box: ui.Rect.fromLTRB(
            left * scaleX,
            top * scaleY,
            right * scaleX,
            bottom * scaleY,
          ),
          score: scores[i],
          landmarks: landmarks,
        ),
      );
    }
  }

  return results;
}

// ---------------------------------------------------------------------------
// Persistent worker isolate — processes all image decoding/preprocessing
// in a single long-lived isolate to avoid ~4000 isolate spawn/destroy cycles.
// ---------------------------------------------------------------------------

class _PreprocessRequest {
  _PreprocessRequest({
    required this.bboxes,
    required this.replyTo,
    this.imageBytes,
    this.landmarks = const [],
    this.reuseLastImage = false,
  });

  /// Encoded image to decode. Null only when [reuseLastImage] is set.
  final Uint8List? imageBytes;
  final List<ui.Rect> bboxes;

  /// Per-box landmark sets, index-aligned with [bboxes]. An entry that is not
  /// exactly five points falls back to an unaligned square crop.
  final List<List<ui.Offset>> landmarks;
  final SendPort replyTo;

  /// Reuse the image decoded for the previous request instead of decoding
  /// again.
  ///
  /// The crop pass always follows the detect pass on the same photo, and a
  /// SendPort copies its payload, so re-sending the bytes and decoding a second
  /// time doubled both the allocation and the CPU cost per photo for nothing.
  final bool reuseLastImage;
}

class PreprocessResult {
  PreprocessResult({
    required this.detectorTensor,
    required this.imgWidth,
    required this.imgHeight,
    required this.cropTensors,
    required this.thumbnailJpegs,
  });

  final Float32List detectorTensor;
  final int imgWidth;
  final int imgHeight;
  final List<Float32List> cropTensors;
  final List<Uint8List?> thumbnailJpegs;
}

void _workerEntry(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  const detectorSize = 640;
  const embedSize = 112;
  const detectorPixels = detectorSize * detectorSize;
  const embedPixels = embedSize * embedSize;

  // Held between the detect pass and the crop pass, which run against the same
  // photo. Cleared as soon as the crop pass is done so a full-resolution decode
  // is not kept alive while the main isolate runs the next photo's inference.
  img.Image? lastImage;

  receivePort.listen((dynamic message) {
    final req = message as _PreprocessRequest;

    final img.Image? image;
    if (req.reuseLastImage) {
      image = lastImage;
    } else {
      // Released before decoding, not after, so the previous photo's buffer is
      // not still live while the next one is being allocated.
      lastImage = null;
      final bytes = req.imageBytes;
      image = bytes == null ? null : img.decodeImage(bytes);
      lastImage = image;
    }

    if (image == null) {
      lastImage = null;
      req.replyTo.send(
        PreprocessResult(
          detectorTensor: Float32List(0),
          imgWidth: 0,
          imgHeight: 0,
          cropTensors: List.generate(
            req.bboxes.length,
            (_) => Float32List(0),
            growable: false,
          ),
          thumbnailJpegs: List.filled(req.bboxes.length, null),
        ),
      );
      return;
    }

    // 1. If bboxes empty → detector preprocessing
    if (req.bboxes.isEmpty) {
      // Callers pass a downscaled image (see FaceRepository.detectionMaxSide),
      // so this resize is cheap — but handle any size.
      final resized =
          image.width == detectorSize && image.height == detectorSize
          ? image
          : img.copyResize(image, width: detectorSize, height: detectorSize);

      final floatData = Float32List(3 * detectorPixels);
      for (var y = 0; y < detectorSize; y++) {
        for (var x = 0; x < detectorSize; x++) {
          final pixel = resized.getPixel(x, y);
          final idx = y * detectorSize + x;
          // SCRFD was trained with (rgb - 127.5) / 128 — the same
          // blobFromImage scaling InsightFace uses. Plain x/255 shifts the
          // input distribution and the detector scores collapse.
          floatData[idx] = (pixel.r - 127.5) / 128.0;
          floatData[detectorPixels + idx] = (pixel.g - 127.5) / 128.0;
          floatData[2 * detectorPixels + idx] = (pixel.b - 127.5) / 128.0;
        }
      }

      req.replyTo.send(
        PreprocessResult(
          detectorTensor: floatData,
          imgWidth: image.width,
          imgHeight: image.height,
          cropTensors: const [],
          thumbnailJpegs: const [],
        ),
      );
      return;
    }

    // 2. Bboxes present → face crop preprocessing + thumbnails.
    // This is the same decode the detect pass measured the boxes against, so
    // the boxes/landmarks are already in this image's coordinate space (scaled
    // back from detector space by decodeScrfdOutputs).
    final cropTensors = <Float32List>[];
    final thumbnails = <Uint8List?>[];
    final embedTemplate = arcFaceTemplate(embedSize);

    for (var bi = 0; bi < req.bboxes.length; bi++) {
      final bbox = req.bboxes[bi];
      final landmarks = bi < req.landmarks.length
          ? req.landmarks[bi]
          : const <ui.Offset>[];

      // Preferred path: warp the five landmarks onto ArcFace's template so
      // every face reaches the embedder at the same scale and rotation.
      img.Image? embedResized;
      if (landmarks.length == 5) {
        final transform = estimateSimilarityTransform(landmarks, embedTemplate);
        if (transform != null && transform.scale > 0) {
          embedResized = warpFace(image, transform, embedSize);
        }
      }

      if (embedResized == null) {
        // Fallback for exports without a keypoint head: a square, face-centred
        // crop. Expanding the box to a square before the resize at least
        // avoids the aspect-ratio squash, but leaves rotation uncorrected.
        final side = max(bbox.width, bbox.height) * 1.2;
        final centerX = bbox.left + bbox.width / 2;
        final centerY = bbox.top + bbox.height / 2;
        final cx = (centerX - side / 2)
            .clamp(0.0, (image.width - 1).toDouble())
            .toInt();
        final cy = (centerY - side / 2)
            .clamp(0.0, (image.height - 1).toDouble())
            .toInt();
        final cw = side.clamp(1.0, (image.width - cx).toDouble()).toInt();
        final ch = side.clamp(1.0, (image.height - cy).toDouble()).toInt();

        if (cw <= 0 || ch <= 0) {
          cropTensors.add(Float32List(0));
          thumbnails.add(null);
          continue;
        }

        final crop = img.copyCrop(image, x: cx, y: cy, width: cw, height: ch);
        embedResized = img.copyResize(
          crop,
          width: embedSize,
          height: embedSize,
        );
      }

      final embedData = Float32List(3 * embedPixels);
      for (var py = 0; py < embedSize; py++) {
        for (var px = 0; px < embedSize; px++) {
          final pixel = embedResized.getPixel(px, py);
          final idx = py * embedSize + px;
          embedData[idx] = (pixel.r / 127.5) - 1.0;
          embedData[embedPixels + idx] = (pixel.g / 127.5) - 1.0;
          embedData[2 * embedPixels + idx] = (pixel.b / 127.5) - 1.0;
        }
      }
      cropTensors.add(embedData);

      // Thumbnail: an upright, padded box crop — the aligned tensor is for the
      // embedder, but a rotated thumbnail would look wrong in the People grid.
      final tPad = min(bbox.width, bbox.height) * 0.2;
      final tx = (bbox.left - tPad)
          .clamp(0.0, (image.width - 1).toDouble())
          .toInt();
      final ty = (bbox.top - tPad)
          .clamp(0.0, (image.height - 1).toDouble())
          .toInt();
      final tw = (bbox.width + tPad * 2)
          .clamp(1.0, (image.width - tx).toDouble())
          .toInt();
      final th = (bbox.height + tPad * 2)
          .clamp(1.0, (image.height - ty).toDouble())
          .toInt();

      final thumbCrop = img.copyCrop(
        image,
        x: tx,
        y: ty,
        width: tw,
        height: th,
      );
      final thumbResized = img.copyResize(thumbCrop, width: 200, height: 200);
      thumbnails.add(
        Uint8List.fromList(img.encodeJpg(thumbResized, quality: 85)),
      );
    }

    // Done with this photo — drop the decode rather than holding it while the
    // main isolate embeds and moves on to the next one.
    lastImage = null;

    req.replyTo.send(
      PreprocessResult(
        detectorTensor: Float32List(0),
        imgWidth: image.width,
        imgHeight: image.height,
        cropTensors: cropTensors,
        thumbnailJpegs: thumbnails,
      ),
    );
  });
}

// ---------------------------------------------------------------------------
// FaceDetectionService
// ---------------------------------------------------------------------------

class FaceDetectionService {
  FaceDetectionService() {
    _init();
  }

  late OnnxRuntime _ort;
  late OrtSession _detectorSession;
  late OrtSession _embedderSession;
  bool _initialized = false;

  // Persistent worker isolate for image preprocessing
  Isolate? _workerIsolate;
  SendPort? _workerPort;
  ReceivePort? _workerExitPort;
  bool _workerReady = false;

  static const int _detectorInputSize = 640;
  static const double _scoreThreshold = 0.5;
  static const double _nmsThreshold = 0.4;
  static const int _embedderInputSize = 112;
  static const int _embedBatchSize = 8;

  /// How long one worker round-trip may take before the worker is presumed
  /// dead.
  ///
  /// A decode that runs the isolate out of memory kills it outright, and a dead
  /// isolate never replies — without this the scan waited on a corpse forever
  /// and the People progress bar froze mid-library.
  static const Duration _workerTimeout = Duration(seconds: 30);

  /// Monotonic suffix so two thumbnails written in the same millisecond
  /// cannot land on the same path.
  static int _thumbnailSeq = 0;

  /// Set once the first inference confirms the export has no keypoint head, so
  /// the degraded-quality warning is logged once rather than per photo.
  static bool _warnedNoKeypoints = false;

  Future<void> _init() async {
    try {
      // Load ONNX models
      _ort = OnnxRuntime();
      _detectorSession = await _ort.createSessionFromAsset(
        'assets/models/det_500m.onnx',
      );
      _embedderSession = await _ort.createSessionFromAsset(
        'assets/models/w600k_mbf.onnx',
      );

      // Spawn persistent worker isolate
      await _spawnWorker();

      _initialized = true;
      debugPrint('[FaceDetectionService] ONNX models + worker isolate ready');
    } catch (e) {
      debugPrint('[FaceDetectionService] Failed to init: $e');
    }
  }

  /// Starts the preprocessing isolate and completes the SendPort handshake.
  ///
  /// [Isolate.spawn] is given an exit/error port so a worker that dies — an
  /// out-of-memory kill on an oversized decode is the realistic cause — is
  /// noticed instead of leaving requests hanging.
  Future<void> _spawnWorker() async {
    final handshake = ReceivePort();
    final exit = ReceivePort();
    exit.listen((dynamic message) {
      if (!_workerReady) return;
      _workerReady = false;
      debugPrint('[FaceDetectionService] Worker isolate died: $message');
    });
    _workerExitPort = exit;

    try {
      _workerIsolate = await Isolate.spawn(
        _workerEntry,
        handshake.sendPort,
        onExit: exit.sendPort,
        onError: exit.sendPort,
      );
      _workerPort = await handshake.first as SendPort;
      _workerReady = true;
    } finally {
      handshake.close();
    }
  }

  /// Replaces a wedged or dead worker so the rest of the scan still runs.
  Future<void> _respawnWorker() async {
    _workerReady = false;
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _workerPort = null;
    _workerExitPort?.close();
    _workerExitPort = null;

    try {
      await _spawnWorker();
    } catch (e) {
      // Leaves _workerReady false, so detectFacesWithThumbnails returns empty
      // for every later photo rather than throwing on each one.
      debugPrint('[FaceDetectionService] Worker respawn failed: $e');
    }
  }

  /// Sends one request to the worker and waits for its reply.
  ///
  /// Returns null when the worker does not answer within [_workerTimeout],
  /// having respawned it first so the next photo is not lost as well.
  Future<PreprocessResult?> _askWorker(
    _PreprocessRequest Function(SendPort replyTo) build,
  ) async {
    final port = _workerPort;
    // A port whose isolate has already exited accepts sends silently and never
    // replies, so an unready worker is a fast null rather than a 30s timeout.
    if (port == null || !_workerReady) return null;

    final reply = ReceivePort();
    try {
      port.send(build(reply.sendPort));
      return await reply.first.timeout(_workerTimeout) as PreprocessResult;
    } on TimeoutException {
      debugPrint(
        '[FaceDetectionService] Worker silent for '
        '${_workerTimeout.inSeconds}s — respawning',
      );
      await _respawnWorker();
      return null;
    } finally {
      reply.close();
    }
  }

  Future<void> ensureInitialized() async {
    if (!_initialized) await _init();
  }

  /// Detects faces, embeds them, and writes a thumbnail crop per face.
  ///
  /// [imageBytes] should already be downscaled — see
  /// `FaceRepository.detectionMaxSide`. Boxes and landmarks come back in the
  /// coordinate space of that decode, which is what [FaceDetectionResult]'s
  /// `imageWidth`/`imageHeight` report.
  ///
  /// The returned faces and thumbnail paths are index-aligned.
  Future<FaceDetectionResult> detectFacesWithThumbnails(
    Uint8List imageBytes,
  ) async {
    if (!_initialized) await _init();
    if (!_workerReady) return const FaceDetectionResult.empty();
    try {
      // Step 1: decode + detector preprocessing, both in the worker isolate.
      final firstResult = await _askWorker(
        (replyTo) => _PreprocessRequest(
          imageBytes: imageBytes,
          bboxes: const [],
          replyTo: replyTo,
        ),
      );
      if (firstResult == null || firstResult.imgWidth == 0) {
        return const FaceDetectionResult.empty();
      }

      // Step 2: Detector inference
      final detections = await _detectFaces(firstResult);
      if (detections.isEmpty) {
        return FaceDetectionResult(
          faces: const [],
          thumbnailPaths: const [],
          imageWidth: firstResult.imgWidth,
          imageHeight: firstResult.imgHeight,
        );
      }

      // Step 3: All face crops + thumbnails in one worker call, against the
      // decode step 1 already produced. Landmarks ride along so the worker can
      // warp each face onto the ArcFace template.
      final bboxes = detections.map((d) => d.box).toList();
      final landmarks = detections.map((d) => d.landmarks).toList();
      final faceResult = await _askWorker(
        (replyTo) => _PreprocessRequest(
          bboxes: bboxes,
          landmarks: landmarks,
          replyTo: replyTo,
          reuseLastImage: true,
        ),
      );
      if (faceResult == null) return const FaceDetectionResult.empty();

      // Step 4: Batch embedder
      final embeddings = await _batchEmbed(faceResult.cropTensors);

      // Step 5: Keep only faces that embedded successfully, writing one
      // thumbnail per kept face so both lists stay index-aligned.
      final tempDir = await getTemporaryDirectory();
      final faces = <DetectedFace>[];
      final thumbnailPaths = <String?>[];
      for (var i = 0; i < detections.length; i++) {
        if (i >= embeddings.length) break;
        final embedding = embeddings[i];
        if (embedding.isEmpty) continue;

        faces.add(
          DetectedFace(
            boundingBox: detections[i].box,
            embedding: embedding,
            confidence: detections[i].score,
            landmarks: detections[i].landmarks,
          ),
        );

        final jpegBytes = i < faceResult.thumbnailJpegs.length
            ? faceResult.thumbnailJpegs[i]
            : null;
        if (jpegBytes == null) {
          thumbnailPaths.add(null);
          continue;
        }
        final cropPath = p.join(
          tempDir.path,
          'face_${DateTime.now().millisecondsSinceEpoch}_${_thumbnailSeq++}.jpg',
        );
        await File(cropPath).writeAsBytes(jpegBytes);
        thumbnailPaths.add(cropPath);
      }

      return FaceDetectionResult(
        faces: faces,
        thumbnailPaths: thumbnailPaths,
        imageWidth: firstResult.imgWidth,
        imageHeight: firstResult.imgHeight,
      );
    } catch (e) {
      debugPrint('[FaceDetectionService] Detection failed: $e');
      return const FaceDetectionResult.empty();
    }
  }

  // ---------------------------------------------------------------------------
  // ONNX inference (stays on main thread — platform channel requirement)
  // ---------------------------------------------------------------------------

  Future<List<ScrfdDetection>> _detectFaces(PreprocessResult preprocess) async {
    final inputTensor = await OrtValue.fromList(preprocess.detectorTensor, [
      1,
      3,
      _detectorInputSize,
      _detectorInputSize,
    ]);

    final inputName = _detectorSession.inputNames.first;
    final outputs = await _detectorSession.run({inputName: inputTensor});

    try {
      // SCRFD emits, per FPN stride, a score tensor shaped [rows, 1], a
      // box-distance tensor shaped [rows, 4] and a keypoint tensor shaped
      // [rows, 10]. Outputs are classified by shape because the exported names
      // are opaque numbers.
      final scoresByStride = <int, List<double>>{};
      final bboxesByStride = <int, List<double>>{};
      final kpsByStride = <int, List<double>>{};
      final anchorsByStride = <int, int>{};

      for (final tensor in outputs.values) {
        final shape = tensor.shape;
        if (shape.isEmpty) continue;
        final total = shape.fold<int>(1, (a, b) => a * b);
        final lastDim = shape.last;

        final int rows;
        final int channels;
        if (lastDim == 1 || lastDim == 4 || lastDim == 10) {
          rows = total ~/ lastDim;
          channels = lastDim;
        } else if (resolveScrfdLayout(total, _detectorInputSize) != null) {
          // Score head exported as [1, rows] rather than [rows, 1].
          rows = total;
          channels = 1;
        } else {
          continue;
        }

        final layout = resolveScrfdLayout(rows, _detectorInputSize);
        if (layout == null) continue;

        final values = (await tensor.asFlattenedList())
            .map((v) => (v as num).toDouble())
            .toList(growable: false);
        anchorsByStride[layout.stride] = layout.numAnchors;
        switch (channels) {
          case 1:
            scoresByStride[layout.stride] = values;
          case 4:
            bboxesByStride[layout.stride] = values;
          case 10:
            kpsByStride[layout.stride] = values;
        }
      }

      if (scoresByStride.isEmpty || bboxesByStride.isEmpty) {
        debugPrint(
          '[FaceDetectionService] Unrecognised detector output shapes: '
          '${outputs.values.map((t) => t.shape).toList()}',
        );
        return const [];
      }
      if (kpsByStride.isEmpty && !_warnedNoKeypoints) {
        _warnedNoKeypoints = true;
        debugPrint(
          '[FaceDetectionService] Detector export has no keypoint head — '
          'falling back to unaligned crops, which clusters less accurately.',
        );
      }

      final decoded = decodeScrfdOutputs(
        scoresByStride: scoresByStride,
        bboxesByStride: bboxesByStride,
        kpsByStride: kpsByStride,
        anchorsByStride: anchorsByStride,
        inputSize: _detectorInputSize,
        scoreThreshold: _scoreThreshold,
        scaleX: preprocess.imgWidth / _detectorInputSize,
        scaleY: preprocess.imgHeight / _detectorInputSize,
      );

      return _nonMaxSuppression(decoded, _nmsThreshold);
    } finally {
      await inputTensor.dispose();
      for (final tensor in outputs.values) {
        await tensor.dispose();
      }
    }
  }

  Future<List<List<double>>> _batchEmbed(List<Float32List> cropTensors) async {
    final allEmbeddings = <List<double>>[];
    final inputName = _embedderSession.inputNames.first;
    final outputName = _embedderSession.outputNames.first;

    for (var i = 0; i < cropTensors.length; i += _embedBatchSize) {
      final end = min(i + _embedBatchSize, cropTensors.length);
      final batch = cropTensors.sublist(i, end);

      final validIndices = <int>[];
      final validTensors = <Float32List>[];
      const expectedLength = 3 * _embedderInputSize * _embedderInputSize;
      for (var j = 0; j < batch.length; j++) {
        if (batch[j].length == expectedLength) {
          // Global index into allEmbeddings, not the index within this batch.
          validIndices.add(i + j);
          validTensors.add(batch[j]);
        }
      }

      for (var j = 0; j < batch.length; j++) {
        allEmbeddings.add([]);
      }

      if (validTensors.isEmpty) continue;

      final n = validTensors.length;
      const channels = 3;
      const h = _embedderInputSize;
      const w = _embedderInputSize;
      final batchData = Float32List(n * channels * h * w);
      for (var k = 0; k < n; k++) {
        final offset = k * channels * h * w;
        // Index validTensors, not batch — batch may contain skipped crops,
        // which would shift every later face's embedding onto the wrong face.
        batchData.setRange(
          offset,
          offset + validTensors[k].length,
          validTensors[k],
        );
      }

      final batchTensor = await OrtValue.fromList(batchData, [
        n,
        channels,
        h,
        w,
      ]);
      final outputs = await _embedderSession.run({inputName: batchTensor});

      try {
        final flatOutput = (await outputs[outputName]!.asFlattenedList())
            .map((v) => (v as num).toDouble())
            .toList(growable: false);
        const embeddingDim = 512;

        for (var k = 0; k < n; k++) {
          final start = k * embeddingDim;
          if (start + embeddingDim > flatOutput.length) break;
          final rawEmbedding = flatOutput
              .sublist(start, start + embeddingDim)
              .toList();
          allEmbeddings[validIndices[k]] = _l2Normalize(rawEmbedding);
        }
      } finally {
        await batchTensor.dispose();
        for (final tensor in outputs.values) {
          await tensor.dispose();
        }
      }
    }

    return allEmbeddings;
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  List<double> _l2Normalize(List<double> vector) {
    var norm = 0.0;
    for (final v in vector) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm == 0) return vector;
    return [for (final v in vector) v / norm];
  }

  List<ScrfdDetection> _nonMaxSuppression(
    List<ScrfdDetection> detections,
    double threshold,
  ) {
    if (detections.isEmpty) return [];

    final sorted = List<ScrfdDetection>.from(detections)
      ..sort((a, b) => b.score.compareTo(a.score));

    final kept = <ScrfdDetection>[];
    final suppressed = List<bool>.filled(sorted.length, false);

    for (var i = 0; i < sorted.length; i++) {
      if (suppressed[i]) continue;
      kept.add(sorted[i]);

      for (var j = i + 1; j < sorted.length; j++) {
        if (suppressed[j]) continue;
        if (_iou(sorted[i].box, sorted[j].box) > threshold) {
          suppressed[j] = true;
        }
      }
    }

    return kept;
  }

  double _iou(ui.Rect a, ui.Rect b) {
    final interLeft = max(a.left, b.left);
    final interTop = max(a.top, b.top);
    final interRight = min(a.right, b.right);
    final interBottom = min(a.bottom, b.bottom);

    final interArea =
        max(0, interRight - interLeft) * max(0, interBottom - interTop);
    final aArea = a.width * a.height;
    final bArea = b.width * b.height;
    final unionArea = aArea + bArea - interArea;

    return unionArea > 0 ? interArea / unionArea : 0;
  }

  Future<void> dispose() async {
    _workerReady = false;
    _workerIsolate?.kill();
    _workerIsolate = null;
    _workerPort = null;
    _workerExitPort?.close();
    _workerExitPort = null;
    if (_initialized) {
      await _detectorSession.close();
      await _embedderSession.close();
    }
  }
}
