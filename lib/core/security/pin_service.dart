import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Minimum number of digits accepted for an app-lock PIN.
const int kMinPinLength = 6;

/// Maximum number of digits accepted for an app-lock PIN.
const int kMaxPinLength = 12;

/// Derives and verifies salted PIN hashes for the app lock.
///
/// PINs are short and low-entropy, so a plain digest is trivially reversible
/// with a rainbow table. Each PIN is therefore stretched with PBKDF2-HMAC-SHA256
/// over a per-user random salt, and the parameters are stored alongside the
/// digest so [iterations] can be raised later without invalidating old PINs.
///
/// The encoded form is a single string, which lets it live in the existing
/// `AppSettings.pinHash` field:
///
///     pbkdf2-sha256$<iterations>$<base64 salt>$<base64 digest>
class PinService {
  PinService({this.iterations = 120000, Random? random})
    : _random = random ?? Random.secure();

  /// PBKDF2 iteration count. Lowered in tests to keep them fast.
  final int iterations;

  final Random _random;

  static const String _algorithm = 'pbkdf2-sha256';
  static const int _saltBytes = 16;
  static const int _keyBytes = 32;

  /// Whether [pin] is an acceptable new PIN (digits only, long enough).
  static bool isValidPin(String pin) {
    if (pin.length < kMinPinLength || pin.length > kMaxPinLength) return false;
    return RegExp(r'^\d+$').hasMatch(pin);
  }

  /// Derive a storable, salted hash for [pin].
  ///
  /// Throws [ArgumentError] if [pin] fails [isValidPin].
  String hashPin(String pin) {
    if (!isValidPin(pin)) {
      throw ArgumentError.value(
        pin,
        'pin',
        'PIN must be $kMinPinLength-$kMaxPinLength digits',
      );
    }

    final salt = Uint8List.fromList(
      List<int>.generate(_saltBytes, (_) => _random.nextInt(256)),
    );
    final digest = _pbkdf2(pin: pin, salt: salt, iterations: iterations);

    return [
      _algorithm,
      '$iterations',
      base64Encode(salt),
      base64Encode(digest),
    ].join(r'$');
  }

  /// Verify [pin] against a hash previously produced by [hashPin].
  ///
  /// Returns false for malformed or empty [encoded] values rather than
  /// throwing, so a corrupted settings blob locks the user out of the PIN
  /// path instead of crashing the unlock screen.
  bool verifyPin({required String pin, required String? encoded}) {
    if (encoded == null || encoded.isEmpty) return false;

    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != _algorithm) return false;

    final storedIterations = int.tryParse(parts[1]);
    if (storedIterations == null || storedIterations <= 0) return false;

    final Uint8List salt;
    final Uint8List expected;
    try {
      salt = base64Decode(parts[2]);
      expected = base64Decode(parts[3]);
    } on FormatException {
      return false;
    }

    final actual = _pbkdf2(
      pin: pin,
      salt: salt,
      iterations: storedIterations,
      keyBytes: expected.length,
    );
    return _constantTimeEquals(actual, expected);
  }

  /// Whether [encoded] uses weaker parameters than this service would produce,
  /// meaning the PIN should be re-hashed the next time it is entered.
  bool needsRehash(String? encoded) {
    if (encoded == null || encoded.isEmpty) return true;
    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != _algorithm) return true;
    final storedIterations = int.tryParse(parts[1]) ?? 0;
    return storedIterations < iterations;
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018).
  Uint8List _pbkdf2({
    required String pin,
    required Uint8List salt,
    required int iterations,
    int keyBytes = _keyBytes,
  }) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    final blockCount = (keyBytes / 32).ceil();
    final output = Uint8List(blockCount * 32);

    for (var block = 1; block <= blockCount; block++) {
      // U1 = PRF(password, salt || INT_BE32(block))
      var u = Uint8List.fromList([
        ...salt,
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ]);
      u = Uint8List.fromList(hmac.convert(u).bytes);

      final accumulator = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < accumulator.length; j++) {
          accumulator[j] ^= u[j];
        }
      }
      output.setRange((block - 1) * 32, block * 32, accumulator);
    }

    return Uint8List.sublistView(output, 0, keyBytes);
  }

  /// Compare without leaking length-prefix timing information.
  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
