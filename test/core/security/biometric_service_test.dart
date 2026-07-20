import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/security/biometric_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BiometricService', () {
    late BiometricService service;
    const channel = MethodChannel('com.lumovault/biometric');

    setUp(() {
      service = BiometricService();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('isAvailable returns true when platform returns true', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            return true;
          });

      final result = await service.isAvailable();
      expect(result, isTrue);
    });

    test('isAvailable returns false when platform returns false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            return false;
          });

      final result = await service.isAvailable();
      expect(result, isFalse);
    });

    test('isAvailable returns false on platform exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            throw PlatformException(code: 'NOT_AVAILABLE');
          });

      final result = await service.isAvailable();
      expect(result, isFalse);
    });

    test('getAvailableTypes returns list from platform', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            return ['fingerprint', 'face'];
          });

      final result = await service.getAvailableTypes();
      expect(result, equals(['fingerprint', 'face']));
    });

    test('getAvailableTypes returns empty on exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            throw PlatformException(code: 'ERROR');
          });

      final result = await service.getAvailableTypes();
      expect(result, isEmpty);
    });

    test('authenticate returns true on success', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            if (methodCall.method == 'authenticate') {
              return true;
            }
            return null;
          });

      final result = await service.authenticate(reason: 'Unlock');
      expect(result, isTrue);
    });

    test('authenticate returns false on failure', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            if (methodCall.method == 'authenticate') {
              return false;
            }
            return null;
          });

      final result = await service.authenticate(reason: 'Unlock');
      expect(result, isFalse);
    });

    test('authenticate returns false on exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            throw PlatformException(code: 'AUTH_FAILED');
          });

      final result = await service.authenticate(reason: 'Unlock');
      expect(result, isFalse);
    });

    test('hasFaceId returns true when face is available', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            return ['face'];
          });

      final result = await service.hasFaceId();
      expect(result, isTrue);
    });

    test('hasFaceId returns false when only fingerprint', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            return ['fingerprint'];
          });

      final result = await service.hasFaceId();
      expect(result, isFalse);
    });

    test('hasFingerprint returns true when fingerprint is available', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            return ['fingerprint'];
          });

      final result = await service.hasFingerprint();
      expect(result, isTrue);
    });

    test('hasFingerprint returns false when only face', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            return ['face'];
          });

      final result = await service.hasFingerprint();
      expect(result, isFalse);
    });
  });
}
