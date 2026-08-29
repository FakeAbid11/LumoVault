import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/device/device_info_service.dart';

void main() {
  group('DeviceInfoService', () {
    test('isMiuiDevice returns true for Xiaomi manufacturer', () async {
      final service = DeviceInfoService(
        manufacturerProvider: () async => 'Xiaomi',
      );

      expect(await service.isMiuiDevice(), isTrue);
    });

    test('isMiuiDevice returns true for Redmi manufacturer', () async {
      final service = DeviceInfoService(
        manufacturerProvider: () async => 'Redmi',
      );

      expect(await service.isMiuiDevice(), isTrue);
    });

    test('isMiuiDevice returns true for POCO manufacturer', () async {
      final service = DeviceInfoService(
        manufacturerProvider: () async => 'POCO',
      );

      expect(await service.isMiuiDevice(), isTrue);
    });

    test(
      'isMiuiDevice returns true for lowercase manufacturer variants',
      () async {
        final service = DeviceInfoService(
          manufacturerProvider: () async => 'xiaomi',
        );

        expect(await service.isMiuiDevice(), isTrue);
      },
    );

    test('isMiuiDevice returns false for Samsung', () async {
      final service = DeviceInfoService(
        manufacturerProvider: () async => 'Samsung',
      );

      expect(await service.isMiuiDevice(), isFalse);
    });

    test('isMiuiDevice returns false for Google', () async {
      final service = DeviceInfoService(
        manufacturerProvider: () async => 'Google',
      );

      expect(await service.isMiuiDevice(), isFalse);
    });

    test('isMiuiDevice returns false for OnePlus', () async {
      final service = DeviceInfoService(
        manufacturerProvider: () async => 'OnePlus',
      );

      expect(await service.isMiuiDevice(), isFalse);
    });

    test('isMiuiDevice caches result', () async {
      int callCount = 0;
      final service = DeviceInfoService(
        manufacturerProvider: () async {
          callCount++;
          return 'Xiaomi';
        },
      );

      // First call
      await service.isMiuiDevice();
      // Second call should use cache
      await service.isMiuiDevice();

      // Only one call to manufacturerProvider should have been made
      expect(callCount, equals(1));
    });

    test('getManufacturer returns manufacturer name', () async {
      final service = DeviceInfoService(
        manufacturerProvider: () async => 'Xiaomi',
      );

      expect(await service.getManufacturer(), equals('Xiaomi'));
    });
  });
}
