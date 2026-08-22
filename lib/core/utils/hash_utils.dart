import 'dart:io';

import 'package:convert/convert.dart' show AccumulatorSink;
import 'package:crypto/crypto.dart';

/// Compute the SHA-256 hash of a file, streamed in chunks.
///
/// Must be a top-level function — [compute] spawns an isolate that can't
/// capture instance state. Shared by [MediaScannerService] and
/// [IncrementalScanner] to avoid code duplication.
Future<String> hashFileInIsolate(String path) async {
  final file = File(path);
  if (!await file.exists()) return '';
  final output = AccumulatorSink<Digest>();
  final input = sha256.startChunkedConversion(output);
  await for (final chunk in file.openRead()) {
    input.add(chunk);
  }
  input.close();
  return output.events.single.toString();
}
