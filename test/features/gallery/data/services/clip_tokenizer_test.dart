import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/services/clip_tokenizer.dart';

/// A minimal but structurally faithful vocab file (version header + merges).
///
/// Byte chars are derived by the tokenizer itself (CLIP's reversible table),
/// so the fixture only needs merge lines. With the canonical byte order the
/// relevant ids are: 'h'=71 'e'=68 'l'=75 'o'=78, the `</w>` variants add
/// 256 (`'e</w>'` = 324), and the three merges get ids 512, 513, 514. SOT and
/// EOT are the tokenizer's fixed canonical ids (49406 / 49407) regardless of
/// fixture size — all hand-computable.
const List<String> _lines = [
  '#version: 0.2',
  'h e', // ('h','e')       -> 'he',    id 512, rank 0
  'he l', // ('he','l')      -> 'hel',   id 513, rank 1
  'l o</w>', // ('l','o</w>') -> 'lo</w>', id 514, rank 2
];

const int contextLength = 8;

ClipTokenizer _tokenizer() =>
    ClipTokenizer.fromLines(_lines, contextLength: contextLength);

void main() {
  group('ClipTokenizer (mini vocab)', () {
    test('base byte chars tokenize to their canonical ids', () {
      // 'h' alone: chars ['h</w>'] — no merge applies to a single char.
      expect(_tokenizer().tokenize('h'), [
        49406, // <|startoftext|>
        327, // 'h</w>'  (71 + 256)
        49407, // <|endoftext|>
        0, 0, 0, 0, 0,
      ]);
    });

    test('BPE merges follow rank order ("he" stays unmerged: no rank)', () {
      // chars ['h', 'e</w>'] — the ('h','e') merge has rank 0, but the
      // trailing </w> means the actual pair is ('h','e</w>'), which has no
      // rank in this fixture — so no merge happens.
      expect(_tokenizer().tokenize('he'), [
        49406,
        71, // 'h'
        324, // 'e</w>'
        49407,
        0, 0, 0, 0,
      ]);
    });

    test('"hello" merges through he -> hel, lo</w>', () {
      expect(_tokenizer().tokenize('hello'), [
        49406,
        513, // 'hel'
        514, // 'lo</w>'
        49407,
        0, 0, 0, 0,
      ]);
    });

    test('input is lowercased before tokenizing', () {
      expect(_tokenizer().tokenize('HeLLo'), _tokenizer().tokenize('hello'));
    });

    test('multiple words concatenate before truncation', () {
      // 'a b c d e f g h i j k l' -> 12 single-char '</w>' tokens; only the
      // first contextLength - 2 fit, so EOT lands at the LAST slot.
      final tokens = _tokenizer().tokenize('a b c d e f g h i j k l');
      expect(tokens.length, contextLength);
      expect(tokens.first, 49406);
      expect(tokens.last, 49407);
      expect(tokens[1], 320); // 'a</w>'  (0x61 - 0x21 = 64, +256)
      expect(tokens[6], 325); // 'f</w>'  (0x66 - 0x21 = 69, +256)
    });

    test('tokenization is deterministic', () {
      final a = _tokenizer().tokenize('a photo of a cat');
      final b = _tokenizer().tokenize('a photo of a cat');
      expect(a, b);
    });

    test('vocabulary boundary: full-size vocab yields exactly 49408 ids', () {
      // Build a full-size vocab file: 48,894 merge lines (the canonical
      // count) where the last in-slice merge is 'z z</w>' (id 49405) and the
      // first EXCLUDED merge is 'q q</w>'. The old 49415-based slice pulled
      // such excluded merges into the vocab, colliding with SOT/EOT ids and
      // running past the model's 49,408-row embedding table.
      final merges = List<String>.generate(48895, (i) => 'm$i n$i');
      merges[48893] = 'z z</w>'; // last in-slice merge -> id 49405

      final lines = ['#version: 0.2', ...merges];
      final tokenizer = ClipTokenizer.fromLines(lines, contextLength: 8);

      // 'zz' merges through the boundary merge -> exactly 49405, never the
      // hardcoded SOT id that a colliding vocab entry would produce.
      expect(tokenizer.tokenize('zz'), [49406, 49405, 49407, 0, 0, 0, 0, 0]);

      // 'qq' exercises the first EXCLUDED merge: its pair is unknown, so the
      // pieces fall back to byte ids — never reaching SOT/EOT ids.
      expect(tokenizer.tokenize('qq'), [
        49406,
        80, // 'q'      (0x71 - 0x21 = 80)
        336, // 'q</w>' (80 + 256)
        49407,
        0, 0, 0, 0,
      ]);
    });

    test('fromVocabBytes round-trips through gzip', () {
      final gz = Uint8List.fromList(
        gzip.encode(utf8.encode(_lines.join('\n'))),
      );
      final tokenizer = ClipTokenizer.fromVocabBytes(
        gz,
        contextLength: contextLength,
      );
      expect(tokenizer.tokenize('hello'), _tokenizer().tokenize('hello'));
    });
  });
}
