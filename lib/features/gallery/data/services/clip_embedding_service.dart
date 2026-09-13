import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'clip_tokenizer.dart';

/// The text-embedding surface the semantic search pipeline consumes — kept
/// as an interface so tests can substitute a fake without ONNX, and so the
/// app degrades gracefully when the text model isn't shipped.
abstract class AiTextEmbedder {
  /// Load the text-tower ONNX session. Safe to call multiple times.
  Future<void> initText();

  /// Whether [initText] succeeded and [embedText] can run.
  bool get isTextReady;

  /// Why [initText] failed, if it did.
  String? get textInitError;

  /// Embed a search query into the same 512-dim space as the image
  /// embeddings (L2-normalized). Returns null when embedding fails.
  Future<List<double>?> embedText(String query);
}

/// Generates 512-dim CLIP embeddings for images and text.
///
/// Uses MobileCLIP S1 (Apple's mobile-optimized CLIP model). The image tower
/// ships at `assets/models/mobileclip_s1.onnx`; the text tower is exported
/// separately by `tool/export_text_tower.py --model mobileclip_s1` and lazily
/// loaded on the first text search — when it's absent, text embedding fails
/// gracefully.
class ClipEmbeddingService implements AiTextEmbedder {
  ClipEmbeddingService._();

  static final ClipEmbeddingService instance = ClipEmbeddingService._();

  late OnnxRuntime _ort;
  late OrtSession _session;
  bool _initialized = false;
  String? _initError;
  Future<void>? _initInFlight;

  /// Input size expected by MobileCLIP S1.
  static const int _inputSize = 336;

  /// CLIP normalization mean (per channel).
  static const List<double> _mean = [0.48145466, 0.4578275, 0.40821073];

  /// CLIP normalization std (per channel).
  static const List<double> _std = [0.26862954, 0.26130258, 0.27577711];

  /// Embedding dimension.
  static const int embeddingDimension = 512;

  bool get isReady => _initialized;
  String? get initError => _initError;

  /// Initializes the ONNX session. Safe to call multiple times — concurrent
  /// callers share one in-flight init instead of each creating a session
  /// (the loser of that race leaked native memory).
  Future<void> init() {
    if (_initialized) return Future.value();
    return _initInFlight ??= _initNow();
  }

  Future<void> _initNow() async {
    try {
      _ort = OnnxRuntime();
      _session = await _ort.createSessionFromAsset(
        'assets/models/mobileclip_s1.onnx',
        options: OrtSessionOptions(
          intraOpNumThreads: 2,
          interOpNumThreads: 2,
        ),
      );
      _initialized = true;
      _initError = null;
      debugPrint('[ClipEmbedding] ONNX session ready');
    } catch (e) {
      _initError = e.toString();
      debugPrint('[ClipEmbedding] Init failed: $e');
    } finally {
      _initInFlight = null;
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
    // _session/_textSession are `late` and only assigned on successful init —
    // guard so dispose after a failed init doesn't throw LateInitializationError.
    if (_initialized) {
      await _session.close();
      _initialized = false;
    }
    if (_textInitialized) {
      await _textSession.close();
      _textInitialized = false;
    }
  }

  // --- Text tower (semantic search) ---

  static const String _textModelAsset =
      'assets/models/mobileclip_s1_text_int8.onnx';

  late OnnxRuntime _textOrt;
  late OrtSession _textSession;
  bool _textInitialized = false;
  String? _textInitError;
  Future<void>? _textInitInFlight;
  ClipTokenizer? _tokenizer;

  @override
  bool get isTextReady => _textInitialized;

  @override
  String? get textInitError => _textInitError;

  @override
  Future<void> initText() {
    if (_textInitialized) return Future.value();
    return _textInitInFlight ??= _initTextNow();
  }

  Future<void> _initTextNow() async {
    try {
      _textOrt = OnnxRuntime();
      _textSession = await _textOrt.createSessionFromAsset(
        _textModelAsset,
        options: OrtSessionOptions(
          intraOpNumThreads: 2,
          interOpNumThreads: 2,
        ),
      );
      try {
        _tokenizer = await ClipTokenizer.fromAssets();
      } catch (e) {
        // Tokenizer asset missing after the model loaded — close the session
        // so a later attempt (once the asset lands) doesn't leak this one.
        await _textSession.close();
        rethrow;
      }
      _textInitialized = true;
      _textInitError = null;
      debugPrint('[ClipEmbedding] text-tower session ready');
    } catch (e) {
      _textInitError = e.toString();
      debugPrint('[ClipEmbedding] text-tower init failed: $e');
    } finally {
      _textInitInFlight = null;
    }
  }

  /// Embeds a search query into the same 512-dim space as the image
  /// embeddings. The query is tokenized with CLIP's BPE (padded to the
  /// model's context length) and run through the text tower.
  @override
  Future<List<double>?> embedText(String query) async {
    if (!_textInitialized) return null;
    final tokenizer = _tokenizer;
    if (tokenizer == null) return null;

    OrtValue? ortValue;
    OrtValue? output;
    try {
      final tokens = tokenizer.tokenize(query);
      ortValue = await OrtValue.fromList(Int64List.fromList(tokens), [
        1,
        tokens.length,
      ]);

      final outputs = await _textSession.run({
        _textSession.inputNames.first: ortValue,
      });

      output = outputs[_textSession.outputNames.first];
      if (output == null) return null;

      final embedding = await output.asFlattenedList();
      final floats = embedding.map((e) => (e as num).toDouble()).toList();
      // The export already L2-normalizes; normalize again defensively so a
      // quantization wobble can't skew cosine ranking.
      return _l2Normalize(floats);
    } catch (e) {
      debugPrint('[ClipEmbedding] embedText failed: $e');
      return null;
    } finally {
      await ortValue?.dispose();
      await output?.dispose();
    }
  }
}
