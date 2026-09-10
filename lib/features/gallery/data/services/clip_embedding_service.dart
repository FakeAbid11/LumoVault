import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

/// Generates 512-dim CLIP embeddings for images and text.
///
/// Uses MobileCLIP S0 (Apple's mobile-optimized CLIP model). The model
/// must be downloaded separately and placed at `assets/models/mobileclip_s0.onnx`.
///
/// When the model is not available, semantic search is gracefully disabled.
class ClipEmbeddingService {
  ClipEmbeddingService._();

  static final ClipEmbeddingService instance = ClipEmbeddingService._();

  late OnnxRuntime _ort;
  late OrtSession _session;
  bool _initialized = false;
  String? _initError;

  /// Input size expected by MobileCLIP S0.
  static const int _inputSize = 336;

  /// CLIP normalization mean (per channel).
  static const List<double> _mean = [0.48145466, 0.4578275, 0.40821073];

  /// CLIP normalization std (per channel).
  static const List<double> _std = [0.26862954, 0.26130258, 0.27577711];

  /// Embedding dimension.
  static const int embeddingDimension = 512;

  bool get isReady => _initialized;
  String? get initError => _initError;

  /// Initializes the ONNX session. Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    try {
      _ort = OnnxRuntime();
      _session = await _ort.createSessionFromAsset(
        'assets/models/mobileclip_s0.onnx',
      );
      _initialized = true;
      _initError = null;
      debugPrint('[ClipEmbedding] ONNX session ready');
    } catch (e) {
      _initError = e.toString();
      debugPrint('[ClipEmbedding] Init failed: $e');
    }
  }

  /// Generates a 512-dim L2-normalized embedding for an image.
  ///
  /// [asset] is the device asset to embed. A 336×336 thumbnail is decoded
  /// on-device, CLIP-normalized, and fed through the model.
  Future<List<double>?> embedImage(Uint8List imageBytes) async {
    if (!_initialized) return null;

    OrtValue? ortValue;
    OrtValue? output;
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return null;

      final resized = img.copyResize(
        decoded,
        width: _inputSize,
        height: _inputSize,
      );

      final inputTensor = _preprocess(resized);

      ortValue = await OrtValue.fromList(inputTensor, [
        1,
        3,
        _inputSize,
        _inputSize,
      ]);
      final inputName = _session.inputNames.first;

      final outputs = await _session.run({inputName: ortValue});

      final outputName = _session.outputNames.first;
      output = outputs[outputName];
      if (output == null) return null;

      final embedding = await output.asFlattenedList();
      final floats = embedding.map((e) => (e as num).toDouble()).toList();

      return _l2Normalize(floats);
    } catch (e) {
      debugPrint('[ClipEmbedding] embedImage failed: $e');
      return null;
    } finally {
      await ortValue?.dispose();
      await output?.dispose();
    }
  }

  /// Preprocesses a 336×336 image into a normalized Float32List for CLIP.
  ///
  /// CLIP expects pixels normalized with mean/std subtraction, channels RGB,
  /// stored as CHW (channel-first) layout.
  Float32List _preprocess(img.Image image) {
    final buffer = Float32List(3 * _inputSize * _inputSize);
    var idx = 0;
    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < _inputSize; y++) {
        for (var x = 0; x < _inputSize; x++) {
          final pixel = image.getPixel(x, y);
          double value;
          switch (c) {
            case 0:
              value = pixel.r / 255.0;
            case 1:
              value = pixel.g / 255.0;
            case 2:
              value = pixel.b / 255.0;
            default:
              value = 0;
          }
          buffer[idx++] = (value - _mean[c]) / _std[c];
        }
      }
    }
    return buffer;
  }

  /// L2-normalizes a vector to unit length.
  List<double> _l2Normalize(List<double> vector) {
    double norm = 0;
    for (final v in vector) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm == 0) return vector;
    return vector.map((v) => v / norm).toList();
  }

  /// Cosine similarity between two L2-normalized vectors (just dot product).
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0;
    double dot = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  Future<void> dispose() async {
    await _session.close();
    _initialized = false;
  }
}
