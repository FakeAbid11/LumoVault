import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';

import 'label_map.dart';

/// The labeling surface the AI scan controller consumes — kept as an
/// interface so tests can substitute a fake without ONNX or the platform.
abstract class AiLabeler {
  /// Load the ONNX model. Safe to call multiple times.
  Future<void> init();

  /// Whether [init] succeeded and [classify] can run.
  bool get isReady;

  /// Classify a device asset, returning human-readable labels.
  Future<List<String>> classify(AssetEntity asset);
}

/// Runs MobileOne-S2 image classification on photo thumbnails.
///
/// The model outputs a 1000-class softmax probability vector. We take the
/// top-N labels above a confidence threshold and return them as human-readable
/// strings.
class ImageClassifierService implements AiLabeler {
  ImageClassifierService._();

  static final ImageClassifierService instance = ImageClassifierService._();

  late OnnxRuntime _ort;
  late OrtSession _session;
  bool _initialized = false;
  String? _initError;

  /// Input size expected by MobileOne-S2.
  static const int _inputSize = 224;

  /// Minimum confidence to include a label.
  static const double _threshold = 0.15;

  /// Maximum labels to return per image.
  static const int _maxLabels = 5;

  @override
  bool get isReady => _initialized;

  String? get initError => _initError;

  /// Initializes the ONNX session. Safe to call multiple times.
  @override
  Future<void> init() async {
    if (_initialized) return;
    try {
      _ort = OnnxRuntime();
      _session = await _ort.createSessionFromAsset(
        'assets/models/mobileone_s2.onnx',
      );
      _initialized = true;
      _initError = null;
      debugPrint('[ImageClassifier] ONNX session ready');
    } catch (e) {
      _initError = e.toString();
      debugPrint('[ImageClassifier] Init failed: $e');
    }
  }

  /// Classifies a single photo and returns top labels (e.g. `['beach', 'sunset']`).
  ///
  /// [asset] is the device asset to classify. A 224×224 thumbnail is decoded
  /// on-device, normalized, and fed through the model.
  @override
  Future<List<String>> classify(AssetEntity asset) async {
    if (!_initialized) return const [];

    OrtValue? ortValue;
    OrtValue? output;
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

      ortValue = await OrtValue.fromList(inputTensor, [
        1,
        3,
        _inputSize,
        _inputSize,
      ]);
      final inputName = _session.inputNames.first;

      final outputs = await _session.run({inputName: ortValue});

      // Read output logits (shape [1, 1000]).
      final outputName = _session.outputNames.first;
      output = outputs[outputName];
      if (output == null) return const [];

      final logitsFlat = await output.asFlattenedList();
      final floats = logitsFlat.map((e) => (e as num).toDouble()).toList();

      return _decodeTopLabels(floats);
    } catch (e) {
      debugPrint('[ImageClassifier] classify failed: $e');
      return const [];
    } finally {
      await ortValue?.dispose();
      await output?.dispose();
    }
  }

  /// Preprocesses a 224×224 image into a normalized Float32List for MobileOne-S2.
  ///
  /// MobileOne-S2 expects ImageNet normalization: mean=[0.485, 0.456, 0.406],
  /// std=[0.229, 0.224, 0.225], channels RGB, stored as CHW (channel-first).
  Float32List _preprocess(img.Image image) {
    const mean = [0.485, 0.456, 0.406];
    const std = [0.229, 0.224, 0.225];
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
          buffer[idx++] = (value - mean[c]) / std[c];
        }
      }
    }
    return buffer;
  }

  /// Applies softmax and returns the top-N human-readable labels.
  List<String> _decodeTopLabels(List<double> logits) {
    // Softmax with numerical stability.
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final exps = logits.map((l) => exp(l - maxLogit)).toList();
    final sumExp = exps.reduce((a, b) => a + b);
    final probs = exps.map((e) => e / sumExp).toList();

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

  Future<void> dispose() async {
    await _session.close();
    _initialized = false;
  }
}
