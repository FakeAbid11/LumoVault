import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// Asset paths for the exported text-tower tokenizer. The files only exist
/// after running `tool/export_text_tower.py`; until then [fromAssets] throws
/// and semantic search shows an explicit unavailable state.
const String kClipVocabAsset = 'assets/tokenizer/bpe_simple_vocab_16e6.txt.gz';
const String kClipTokenizerConfigAsset = 'assets/tokenizer/config.json';

/// CLIP byte-pair tokenizer — a faithful Dart port of OpenCLIP's
/// `SimpleTokenizer`, which is exactly what MobileCLIP uses to encode text
/// into the same token space its text tower was trained on.
///
/// The resulting id sequence ([tokenize]) is fed to the exported text-tower
/// ONNX; its output embedding lives in the same 512-dim space as the stored
/// image embeddings, which is what makes text-to-image ranking work.
class ClipTokenizer {
  ClipTokenizer._(this._encoder, this._bpeRanks, this.contextLength);

  /// Builds from the raw (decompressed) vocab file lines. Mirrors OpenCLIP's
  /// `SimpleTokenizer.__init__` line-for-line so ids match the canonical
  /// tokenizer exactly.
  factory ClipTokenizer.fromLines(
    List<String> lines, {
    required int contextLength,
  }) {
    final byteEncoder = _buildByteEncoder();
    final byteValues = byteEncoder.values.toList();

    // open_clip: merges = lines[1 : 49415 - 256 - 2 + 1]. The end is clamped
    // so the tiny synthetic vocabs used in tests don't range-error.
    final end = (49415 - 256 - 2 + 1).clamp(1, lines.length);
    final merges = lines
        .sublist(1, end)
        .map((line) => line.split(' '))
        .toList();

    final vocab = <String>[
      ...byteValues,
      ...byteValues.map((v) => '$v</w>'),
      ...merges.map((pair) => pair.join()),
      '<|startoftext|>',
      '<|endoftext|>',
    ];
    final encoder = {for (var i = 0; i < vocab.length; i++) vocab[i]: i};
    final bpeRanks = <(String, String), int>{
      for (var i = 0; i < merges.length; i++) (merges[i][0], merges[i][1]): i,
    };

    return ClipTokenizer._(encoder, bpeRanks, contextLength);
  }

  /// Loads the exported vocab + config from the app's assets.
  static Future<ClipTokenizer> fromAssets() async {
    final configRaw = await rootBundle.loadString(kClipTokenizerConfigAsset);
    final config = jsonDecode(configRaw) as Map<String, dynamic>;
    final contextLength = (config['contextLength'] as num).toInt();
    final data = await rootBundle.load(kClipVocabAsset);
    return ClipTokenizer.fromVocabBytes(
      data.buffer.asUint8List(),
      contextLength: contextLength,
    );
  }

  /// Builds from raw gzipped vocab bytes (the file the export script ships).
  static ClipTokenizer fromVocabBytes(
    Uint8List gzBytes, {
    required int contextLength,
  }) {
    return ClipTokenizer.fromLines(
      utf8.decode(gzip.decode(gzBytes)).split('\n'),
      contextLength: contextLength,
    );
  }

  static const int _sotId = 49406;
  static const int _eotId = 49407;

  static final RegExp _tokenPattern = RegExp(
    // The first fragment contains literal apostrophes ('s, 't, …), so it
    // must stay double-quoted; the second has none and satisfies the lint.
    r"<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|"
    r'[\p{N}]|[^\s\p{L}\p{N}]+',
    caseSensitive: false,
    dotAll: true,
    unicode: true,
  );

  final Map<String, int> _encoder;
  final Map<(String, String), int> _bpeRanks;

  /// Token budget of the exported text model (SOT + ids + EOT, zero-padded).
  final int contextLength;

  /// Encodes [text] into exactly [contextLength] token ids:
  /// [SOT, word ids..., EOT, 0-padding...]. Queries longer than the context
  /// are truncated (CLIP-standard behavior).
  List<int> tokenize(String text) {
    final cleaned = _whitespaceClean(text.toLowerCase());
    final ids = <int>[];
    for (final match in _tokenPattern.allMatches(cleaned)) {
      final token = match.group(0)!;
      for (final piece in _bpe(token).split(' ')) {
        final id = _encoder[piece];
        if (id != null) ids.add(id);
      }
    }

    final kept = ids.take(contextLength - 2).toList();
    final tokens = List<int>.filled(contextLength, 0);
    tokens[0] = _sotId;
    for (var i = 0; i < kept.length; i++) {
      tokens[i + 1] = kept[i];
    }
    tokens[kept.length + 1] = _eotId;
    return tokens;
  }

  /// Byte-pair merge on one word's characters, with CLIP's `</w>` suffix on
  /// the trailing character marking the end of the word. Repeatedly merges
  /// the lowest-ranked adjacent pair until no ranked pair remains.
  String _bpe(String word) {
    if (word.length <= 1) return '$word</w>';

    var parts = <String>[
      ...word.split('').sublist(0, word.length - 1),
      '${word[word.length - 1]}</w>',
    ];

    while (parts.length > 1) {
      var bestRank = 1 << 30;
      var bestIndex = -1;
      for (var i = 0; i < parts.length - 1; i++) {
        final rank = _bpeRanks[(parts[i], parts[i + 1])];
        if (rank != null && rank < bestRank) {
          bestRank = rank;
          bestIndex = i;
        }
      }
      if (bestIndex == -1) break;
      parts = [
        ...parts.sublist(0, bestIndex),
        parts[bestIndex] + parts[bestIndex + 1],
        ...parts.sublist(bestIndex + 2),
      ];
    }

    return parts.join(' ');
  }

  /// CLIP's reversible byte-to-unicode table: printable ASCII/latin-1 map to
  /// themselves, the other 68 bytes map to code points 256+, so arbitrary
  /// bytes stay visible tokens.
  static Map<int, String> _buildByteEncoder() {
    final bs = <int>[
      for (var b = 0x21; b <= 0x7E; b++) b,
      for (var b = 0xA1; b <= 0xAC; b++) b,
      for (var b = 0xAE; b <= 0xFF; b++) b,
    ];
    final cs = [...bs];
    var n = 0;
    for (var b = 0; b <= 0xFF; b++) {
      if (!bs.contains(b)) {
        bs.add(b);
        cs.add(0x100 + n);
        n++;
      }
    }
    return {
      for (var i = 0; i < bs.length; i++) bs[i]: String.fromCharCode(cs[i]),
    };
  }

  static String _whitespaceClean(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), ' ')
        .split('\n')
        .map((line) => line.trim())
        .join(' ')
        .trim();
  }
}
