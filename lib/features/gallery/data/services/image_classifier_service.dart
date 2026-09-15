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
  ///
  /// 0.10 made `_maxLabels` dead in practice — only the argmax of a
  /// confident prediction clears an absolute 0.10, so every photo got exactly
  /// one tag. 0.08 lets sibling classes (e.g. the five cat classes) co-tag.
  static const double _threshold = 0.08;

  /// Maximum labels to return per image.
  static const int _maxLabels = 4;

  /// Generic search categories expanded from specific class names.
  ///
  /// Search matches keywords as substrings of the stored labels, so an
  /// expansion is only needed when the category word is NOT a substring of
  /// the class name already — a 'tabby' photo must answer to 'cat' (no
  /// substring relation), while searching 'shark' already matches
  /// 'great white shark' without help. Matched with word boundaries against
  /// the lowercased class name, so 'catamaran'/'caterpillar' never match
  /// 'cat' while 'Egyptian cat' matches 'cat'.
  static const Map<String, List<String>> _hypernyms = {
    'cat': [
      'cat',
      'tabby',
      'lynx',
      'cougar',
      'panther',
      'jaguar',
      'leopard',
      'cheetah',
      'siamese',
      'persian',
    ],
    'dog': [
      'dog',
      'retriever',
      'spaniel',
      'terrier',
      'hound',
      'shepherd',
      'poodle',
      'bulldog',
      'schnauzer',
      'corgi',
      'husky',
      'malamute',
      'dalmatian',
      'boxer',
      'beagle',
      'collie',
      'pointer',
      'chow',
      'pekingese',
      'pekinese',
      'pinscher',
      'schipperke',
      'malinois',
      'borzoi',
      'whippet',
      'vizsla',
      'weimaraner',
      'basenji',
      'basset',
      'komondor',
      'keeshond',
      'pug',
    ],
    'bird': [
      'bird',
      'finch',
      'sparrow',
      'robin',
      'eagle',
      'owl',
      'parrot',
      'cockatoo',
      'macaw',
      'gull',
      'loon',
      'swan',
      'goose',
      'duck',
      'chicken',
      'cock',
      'hen',
      'turkey',
      'peacock',
      'hummingbird',
      'woodpecker',
      'kingfisher',
      'jay',
      'magpie',
      'crow',
      'raven',
      'falcon',
      'hawk',
      'ostrich',
      'penguin',
      'flamingo',
      'heron',
      'stork',
      'quail',
      'partridge',
      'pheasant',
      'kiwi',
    ],
    'fish': [
      'fish',
      'shark',
      'ray',
      'stingray',
      'skate',
      'trout',
      'salmon',
      'carp',
      'perch',
      'bass',
      'eel',
      'herring',
      'barracouta',
      'gar',
      'coho',
    ],
    'car': [
      'car',
      'convertible',
      'jeep',
      'sedan',
      'limousine',
      'taxi',
      'minivan',
      'racer',
    ],
    'truck': ['truck', 'pickup', 'tractor', 'trailer'],
    'bus': ['bus', 'minibus', 'trolleybus'],
    'train': ['train', 'locomotive', 'streetcar', 'tram'],
    'boat': [
      'boat',
      'canoe',
      'kayak',
      'catamaran',
      'gondola',
      'ferry',
      'speedboat',
      'house boat',
    ],
    'plane': ['plane', 'airliner', 'jet'],
    'horse': ['horse', 'pony', 'mustang', 'stallion', 'clydesdale'],
    'cow': ['cow', 'cattle', 'bull', 'ox', 'heifer', 'steer'],
    'sheep': ['sheep', 'lamb', 'ewe', 'ram'],
    'goat': ['goat', 'ibex', 'kid'],
    'pig': ['pig', 'hog', 'boar', 'swine', 'piglet'],
    'deer': ['deer', 'elk', 'moose', 'antelope', 'gazelle', 'caribou'],
    'monkey': [
      'monkey',
      'chimpanzee',
      'gorilla',
      'orangutan',
      'ape',
      'baboon',
      'macaque',
      'lemur',
      'marmoset',
    ],
    'bear': ['bear', 'panda'],
    'snake': ['snake', 'cobra', 'viper', 'python', 'boa', 'mamba', 'asp'],
    'rabbit': ['rabbit', 'hare', 'bunny'],
    'fruit': [
      'banana',
      'apple',
      'orange',
      'lemon',
      'lime',
      'peach',
      'pear',
      'plum',
      'cherry',
      'strawberry',
      'pineapple',
      'grape',
      'watermelon',
      'cantaloupe',
      'mango',
      'kiwi',
      'apricot',
      'pomegranate',
    ],
    'vegetable': [
      'broccoli',
      'carrot',
      'cucumber',
      'eggplant',
      'mushroom',
      'onion',
      'garlic',
      'tomato',
      'potato',
      'zucchini',
      'spaghetti squash',
      'artichoke',
      'bell pepper',
    ],
    'flower': [
      'rose',
      'tulip',
      'daisy',
      'dandelion',
      'orchid',
      'daffodil',
      'lily',
      'lilac',
      'hibiscus',
      'petunia',
      'peony',
      'poppy',
    ],
  };

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
        options: OrtSessionOptions(intraOpNumThreads: 2, interOpNumThreads: 2),
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
      // MobileOne-S2 expects [0,1] pixels normalized by ImageNet mean/std.
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

      return decodeTopLabels(floats);
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

  /// Applies softmax and returns the top-N human-readable labels, followed
  /// by the generic search categories they expand to (see [_hypernyms]).
  ///
  /// Static and exposed for tests: the label DECODE path — thresholds,
  /// the canonical-index mapping and the expansion — is pure math over the
  /// logits and must be testable without ONNX or a platform.
  @visibleForTesting
  static List<String> decodeTopLabels(
    List<double> logits, {
    double threshold = _threshold,
    int maxLabels = _maxLabels,
  }) {
    if (logits.isEmpty) return const [];

    // Softmax with numerical stability.
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final exps = logits.map((l) => exp(l - maxLogit)).toList();
    final sumExp = exps.reduce((a, b) => a + b);
    final probs = exps.map((e) => e / sumExp).toList();

    // Collect candidates above the confidence floor.
    final indexed = <(int, double)>[];
    for (var i = 0; i < probs.length; i++) {
      if (probs[i] >= threshold) {
        indexed.add((i, probs[i]));
      }
    }
    indexed.sort((a, b) => b.$2.compareTo(a.$2));

    // Map to labels + generic categories.
    final labels = <String>[];
    for (final entry in indexed.take(maxLabels)) {
      final label = imageNetLabels[entry.$1];
      if (label == null) continue;
      labels.add('ai_${label.toLowerCase().replaceAll(' ', '_')}');
      for (final hypernym in _hypernymsFor(label.toLowerCase())) {
        final tag = 'ai_$hypernym';
        if (!labels.contains(tag)) labels.add(tag);
      }
    }
    return labels;
  }

  /// Generic categories a class name belongs to (word-boundary matched, so
  /// 'tabby' → 'cat' but 'catamaran' does not).
  static Iterable<String> _hypernymsFor(String lowerCasedName) {
    return _hypernyms.entries
        .where(
          (rule) => rule.value.any(
            (word) =>
                RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(lowerCasedName),
          ),
        )
        .map((rule) => rule.key);
  }

  Future<void> dispose() async {
    await _session.close();
    _initialized = false;
  }
}
