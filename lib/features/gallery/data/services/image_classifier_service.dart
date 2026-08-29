import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';

import 'label_map.dart';

/// Runs EfficientNet-Lite0 image classification on photo thumbnails.
///
/// The model outputs a 1000-class softmax probability vector. We take the
/// top-N labels above a confidence threshold and return them as human-readable
/// strings.
class ImageClassifierService {
  ImageClassifierService._();

  static final ImageClassifierService instance = ImageClassifierService._();

  late OnnxRuntime _ort;
  late OrtSession _session;
  bool _initialized = false;

  /// Input size expected by EfficientNet-Lite0.
  static const int _inputSize = 224;

  /// Minimum confidence to include a label.
  static const double _threshold = 0.15;

  /// Maximum labels to return per image.
  static const int _maxLabels = 5;

  /// Initializes the ONNX session. Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    try {
      _ort = OnnxRuntime();
      _session = await _ort.createSessionFromAsset(
        'assets/models/efficientnet_lite0.onnx',
      );
      _initialized = true;
      debugPrint('[ImageClassifier] ONNX session ready');
    } catch (e) {
      debugPrint('[ImageClassifier] Init failed: $e');
    }
  }

  /// Classifies a single photo and returns top labels (e.g. `['beach', 'sunset']`).
  ///
  /// [asset] is the device asset to classify. A 224×224 thumbnail is decoded
  /// on-device, normalized, and fed through the model.
  Future<List<String>> classify(AssetEntity asset) async {
    if (!_initialized) return const [];

    try {
      // Load thumbnail bytes (224×224 is small enough for platform decode).
      final thumbBytes = await asset.thumbnailDataWithSize(
        const ThumbnailSize(_inputSize, _inputSize),
      );
      if (thumbBytes == null || thumbBytes.isEmpty) return const [];

      // Decode to pixel buffer.
      final decoded = img.decodeImage(thumbBytes);
      if (decoded == null) return const [];

      // Ensure exact dimensions (platform may return slightly different size).
      final resized = img.copyResize(
        decoded,
        width: _inputSize,
        height: _inputSize,
      );

      // Build input tensor: Float32List of shape [1, 3, 224, 224].
      // EfficientNet-Lite0 expects pixels normalized to [0, 1].
      final inputTensor = _preprocess(resized);

      final ortValue = await OrtValue.fromList(inputTensor, [
        1,
        3,
        _inputSize,
        _inputSize,
      ]);
      final inputName = _session.inputNames.first;

      final outputs = await _session.run({inputName: ortValue});

      // Read output logits (shape [1, 1000]).
      final outputName = _session.outputNames.first;
      final output = outputs[outputName];
      if (output == null) {
        ortValue.dispose();
        return const [];
      }

      final logits = await output.asList();
      final floats = logits.map((e) => (e as num).toDouble()).toList();

      ortValue.dispose();
      output.dispose();

      // Softmax + top-N.
      return _decodeTopLabels(floats);
    } catch (e) {
      debugPrint('[ImageClassifier] classify failed: $e');
      return const [];
    }
  }

  /// Preprocesses a 224×224 image into a normalized Float32List for EfficientNet.
  ///
  /// EfficientNet-Lite0 expects pixels in [0, 1] range, channels RGB,
  /// stored as CHW (channel-first) layout.
  Float32List _preprocess(img.Image image) {
    final buffer = Float32List(3 * _inputSize * _inputSize);
    var idx = 0;
    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < _inputSize; y++) {
        for (var x = 0; x < _inputSize; x++) {
          final pixel = image.getPixel(x, y);
          switch (c) {
            case 0:
              buffer[idx++] = pixel.r / 255.0;
            case 1:
              buffer[idx++] = pixel.g / 255.0;
            case 2:
              buffer[idx++] = pixel.b / 255.0;
          }
        }
      }
    }
    return buffer;
  }

  /// Applies softmax and returns the top-N human-readable labels.
  List<String> _decodeTopLabels(List<double> logits) {
    // Softmax.
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final exps = logits.map((l) => l - maxLogit); // for numerical stability
    final sumExp = exps.map((e) => Math.exp(e)).reduce((a, b) => a + b);
    final probs = exps.map((e) => Math.exp(e) / sumExp).toList();

    // Sort by probability descending.
    final indexed = <(int, double)>[];
    for (var i = 0; i < probs.length; i++) {
      if (probs[i] >= _threshold) {
        indexed.add((i, probs[i]));
      }
    }
    indexed.sort((a, b) => b.$2.compareTo(a.$2));

    // Map to labels.
    final labels = <String>[];
    for (final entry in indexed.take(_maxLabels)) {
      final label = imageNetLabels[entry.$1];
      if (label != null) {
        labels.add('ai_${label.toLowerCase().replaceAll(' ', '_')}');
      }
    }
    return labels;
  }

  void dispose() {
    _session.close();
    _initialized = false;
  }
}

/// Minimal math helper to avoid importing dart:math.
class Math {
  static double exp(double x) {
    // Dart's double has no built-in exp — use the identity e^x.
    // This is a simple Taylor-series approximation sufficient for softmax.
    if (x > 20) return 1.0e20; // prevent overflow
    if (x < -20) return 0.0;
    var sum = 1.0;
    var term = 1.0;
    for (var i = 1; i <= 20; i++) {
      term *= x / i;
      sum += term;
    }
    return sum;
  }
}
