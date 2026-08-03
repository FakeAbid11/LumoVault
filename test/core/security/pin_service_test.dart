import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/security/pin_service.dart';

void main() {
  group('PinService.isValidPin', () {
    test('rejects PINs shorter than the minimum', () {
      expect(PinService.isValidPin('12345'), isFalse);
      expect(PinService.isValidPin(''), isFalse);
    });

    test('rejects PINs longer than the maximum', () {
      expect(PinService.isValidPin('1' * (kMaxPinLength + 1)), isFalse);
    });

    test('rejects non-digits', () {
      expect(PinService.isValidPin('12345a'), isFalse);
      expect(PinService.isValidPin('12 456'), isFalse);
    });

    test('accepts digit PINs within range', () {
      expect(PinService.isValidPin('123456'), isTrue);
      expect(PinService.isValidPin('1' * kMaxPinLength), isTrue);
    });
  });

  group('PinService hashing', () {
    // Low iteration count keeps the suite fast; the algorithm is unchanged.
    final service = PinService(iterations: 1000);

    test('hashPin never returns the PIN itself', () {
      final hash = service.hashPin('123456');

      expect(hash, isNot(contains('123456')));
      expect(hash, startsWith(r'pbkdf2-sha256$1000$'));
    });

    test('hashPin salts, so the same PIN hashes differently each time', () {
      expect(service.hashPin('123456'), isNot(service.hashPin('123456')));
    });

    test('verifyPin accepts the correct PIN', () {
      final hash = service.hashPin('135790');
      expect(service.verifyPin(pin: '135790', encoded: hash), isTrue);
    });

    test('verifyPin rejects an incorrect PIN', () {
      final hash = service.hashPin('135790');
      expect(service.verifyPin(pin: '135791', encoded: hash), isFalse);
    });

    test('verifyPin rejects null, empty and malformed hashes', () {
      expect(service.verifyPin(pin: '123456', encoded: null), isFalse);
      expect(service.verifyPin(pin: '123456', encoded: ''), isFalse);
      expect(service.verifyPin(pin: '123456', encoded: '123456'), isFalse);
      expect(
        service.verifyPin(pin: '123456', encoded: r'md5$1000$aa$bb'),
        isFalse,
      );
      expect(
        service.verifyPin(pin: '123456', encoded: r'pbkdf2-sha256$0$aa$bb'),
        isFalse,
      );
      expect(
        service.verifyPin(pin: '123456', encoded: r'pbkdf2-sha256$1000$!$!'),
        isFalse,
      );
    });

    test('hashPin refuses to hash an invalid PIN', () {
      expect(() => service.hashPin('1234'), throwsArgumentError);
      expect(() => service.hashPin('abcdef'), throwsArgumentError);
    });

    test('a hash stays verifiable under a service with more iterations', () {
      final old = PinService(iterations: 1000).hashPin('246810');
      final upgraded = PinService(iterations: 2000);

      expect(upgraded.verifyPin(pin: '246810', encoded: old), isTrue);
      expect(upgraded.needsRehash(old), isTrue);
    });

    test('needsRehash is false for a current-parameter hash', () {
      expect(service.needsRehash(service.hashPin('123456')), isFalse);
    });

    test('needsRehash is true for missing or foreign hashes', () {
      expect(service.needsRehash(null), isTrue);
      expect(service.needsRehash(''), isTrue);
      expect(service.needsRehash('123456'), isTrue);
    });

    test('derivation is deterministic for a fixed salt', () {
      // Seeded Random makes the salt reproducible, so two services with the
      // same seed must produce byte-identical hashes.
      final a = PinService(iterations: 1000, random: Random(42));
      final b = PinService(iterations: 1000, random: Random(42));

      expect(a.hashPin('112233'), b.hashPin('112233'));
    });
  });
}
