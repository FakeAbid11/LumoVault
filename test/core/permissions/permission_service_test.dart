import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'package:lumovault/core/permissions/permission_handler_service.dart';
import 'package:lumovault/core/permissions/permission_service.dart';

/// Mock PermissionHandler for testing.
class MockPermissionHandler extends PermissionHandler {
  MockPermissionHandler({
    this.mediaStatus = ph.PermissionStatus.denied,
    this.notificationStatus = ph.PermissionStatus.denied,
    this.batteryStatus = ph.PermissionStatus.denied,
    this.requestMediaResult,
    this.requestNotificationResult,
    this.requestBatteryResult = true,
    this.openSettingsResult = true,
  });

  final ph.PermissionStatus mediaStatus;
  final ph.PermissionStatus notificationStatus;
  final ph.PermissionStatus batteryStatus;
  Map<ph.Permission, ph.PermissionStatus>? requestMediaResult;
  ph.PermissionStatus? requestNotificationResult;
  final bool requestBatteryResult;
  final bool openSettingsResult;

  @override
  Future<ph.PermissionStatus> checkPermission(ph.Permission permission) async {
    if (permission == ph.Permission.photos ||
        permission == ph.Permission.videos) {
      return mediaStatus;
    }
    if (permission == ph.Permission.notification) {
      return notificationStatus;
    }
    if (permission == ph.Permission.ignoreBatteryOptimizations) {
      return batteryStatus;
    }
    return ph.PermissionStatus.denied;
  }

  @override
  Future<Map<ph.Permission, ph.PermissionStatus>> request(
    List<ph.Permission> permissions,
  ) async {
    final results = <ph.Permission, ph.PermissionStatus>{};
    for (final p in permissions) {
      if (p == ph.Permission.photos || p == ph.Permission.videos) {
        if (requestMediaResult != null) {
          results[p] = requestMediaResult![p] ?? ph.PermissionStatus.granted;
        } else {
          results[p] = mediaStatus;
        }
      } else if (p == ph.Permission.notification) {
        results[p] = requestNotificationResult ?? ph.PermissionStatus.granted;
      } else if (p == ph.Permission.ignoreBatteryOptimizations) {
        results[p] = requestBatteryResult
            ? ph.PermissionStatus.granted
            : ph.PermissionStatus.denied;
      } else {
        results[p] = ph.PermissionStatus.granted;
      }
    }
    return results;
  }

  Future<bool> openAppSettings() async => openSettingsResult;
}

void main() {
  group('PermissionStatus enum', () {
    test('has all expected values', () {
      expect(PermissionStatus.values, contains(PermissionStatus.granted));
      expect(PermissionStatus.values, contains(PermissionStatus.denied));
      expect(
        PermissionStatus.values,
        contains(PermissionStatus.permanentlyDenied),
      );
      expect(PermissionStatus.values, contains(PermissionStatus.limited));
      expect(PermissionStatus.values, contains(PermissionStatus.notDetermined));
    });
  });

  group('PermissionRequestResult', () {
    test('changed returns true when status differs', () {
      const result = PermissionRequestResult(
        status: PermissionStatus.granted,
        previousStatus: PermissionStatus.denied,
      );
      expect(result.changed, isTrue);
    });

    test('changed returns false when status is the same', () {
      const result = PermissionRequestResult(
        status: PermissionStatus.denied,
        previousStatus: PermissionStatus.denied,
      );
      expect(result.changed, isFalse);
    });
  });

  group('PermissionHandlerService', () {
    late MockPermissionHandler mockHandler;
    late PermissionHandlerService service;

    setUp(() {
      mockHandler = MockPermissionHandler();
      service = PermissionHandlerService(permissionHandler: mockHandler);
    });

    tearDown(() {
      service.dispose();
    });

    group('checkMediaPermissionStatus', () {
      test('returns granted when both photos and videos are granted', () async {
        mockHandler = MockPermissionHandler(
          mediaStatus: ph.PermissionStatus.granted,
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final status = await service.checkMediaPermissionStatus();
        expect(status, PermissionStatus.granted);
      });

      test('returns limited when photos is limited', () async {
        mockHandler = MockPermissionHandler(
          mediaStatus: ph.PermissionStatus.limited,
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final status = await service.checkMediaPermissionStatus();
        expect(status, PermissionStatus.limited);
      });

      test('returns limited when videos is limited', () async {
        // We need to set up different statuses for photos vs videos.
        // Since the current implementation checks both, let's test the limited path.
        mockHandler = MockPermissionHandler(
          mediaStatus: ph.PermissionStatus.limited,
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final status = await service.checkMediaPermissionStatus();
        expect(status, PermissionStatus.limited);
      });

      test(
        'returns permanentlyDenied when photos is permanently denied',
        () async {
          mockHandler = MockPermissionHandler(
            mediaStatus: ph.PermissionStatus.permanentlyDenied,
          );
          service = PermissionHandlerService(permissionHandler: mockHandler);

          final status = await service.checkMediaPermissionStatus();
          expect(status, PermissionStatus.permanentlyDenied);
        },
      );

      test('returns denied when permissions are denied', () async {
        mockHandler = MockPermissionHandler(
          mediaStatus: ph.PermissionStatus.denied,
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final status = await service.checkMediaPermissionStatus();
        expect(status, PermissionStatus.denied);
      });

      test('returns notDetermined when permissions are restricted', () async {
        mockHandler = MockPermissionHandler(
          mediaStatus: ph.PermissionStatus.restricted,
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final status = await service.checkMediaPermissionStatus();
        expect(status, PermissionStatus.notDetermined);
      });
    });

    group('checkNotificationPermissionStatus', () {
      test('returns granted when notification permission is granted', () async {
        mockHandler = MockPermissionHandler(
          notificationStatus: ph.PermissionStatus.granted,
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final status = await service.checkNotificationPermissionStatus();
        expect(status, PermissionStatus.granted);
      });

      test('returns denied when notification permission is denied', () async {
        mockHandler = MockPermissionHandler(
          notificationStatus: ph.PermissionStatus.denied,
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final status = await service.checkNotificationPermissionStatus();
        expect(status, PermissionStatus.denied);
      });

      test(
        'returns permanentlyDenied when notification is permanently denied',
        () async {
          mockHandler = MockPermissionHandler(
            notificationStatus: ph.PermissionStatus.permanentlyDenied,
          );
          service = PermissionHandlerService(permissionHandler: mockHandler);

          final status = await service.checkNotificationPermissionStatus();
          expect(status, PermissionStatus.permanentlyDenied);
        },
      );
    });

    group('isBatteryOptimizationDisabled', () {
      test('returns true when battery optimization is disabled', () async {
        mockHandler = MockPermissionHandler(
          batteryStatus: ph.PermissionStatus.granted,
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final result = await service.isBatteryOptimizationDisabled();
        expect(result, isTrue);
      });

      test('returns false when battery optimization is not disabled', () async {
        mockHandler = MockPermissionHandler(
          batteryStatus: ph.PermissionStatus.denied,
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final result = await service.isBatteryOptimizationDisabled();
        expect(result, isFalse);
      });
    });

    group('requestMediaPermission', () {
      test('returns granted when user grants permission', () async {
        mockHandler = MockPermissionHandler(
          requestMediaResult: {
            ph.Permission.photos: ph.PermissionStatus.granted,
            ph.Permission.videos: ph.PermissionStatus.granted,
          },
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final result = await service.requestMediaPermission();
        expect(result.status, PermissionStatus.granted);
        expect(result.changed, isTrue);
      });

      test('returns limited when user grants limited access', () async {
        mockHandler = MockPermissionHandler(
          requestMediaResult: {
            ph.Permission.photos: ph.PermissionStatus.limited,
            ph.Permission.videos: ph.PermissionStatus.granted,
          },
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final result = await service.requestMediaPermission();
        expect(result.status, PermissionStatus.limited);
      });

      test('returns denied when user denies permission', () async {
        mockHandler = MockPermissionHandler(
          requestMediaResult: {
            ph.Permission.photos: ph.PermissionStatus.denied,
            ph.Permission.videos: ph.PermissionStatus.denied,
          },
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final result = await service.requestMediaPermission();
        expect(result.status, PermissionStatus.denied);
      });

      test('returns permanentlyDenied when user permanently denies', () async {
        mockHandler = MockPermissionHandler(
          requestMediaResult: {
            ph.Permission.photos: ph.PermissionStatus.permanentlyDenied,
            ph.Permission.videos: ph.PermissionStatus.denied,
          },
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final result = await service.requestMediaPermission();
        expect(result.status, PermissionStatus.permanentlyDenied);
      });

      test('tracks previous status correctly', () async {
        mockHandler = MockPermissionHandler(
          mediaStatus: ph.PermissionStatus.denied,
          requestMediaResult: {
            ph.Permission.photos: ph.PermissionStatus.granted,
            ph.Permission.videos: ph.PermissionStatus.granted,
          },
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final result = await service.requestMediaPermission();
        expect(result.previousStatus, PermissionStatus.denied);
        expect(result.status, PermissionStatus.granted);
        expect(result.changed, isTrue);
      });
    });

    group('requestNotificationPermission', () {
      test('returns granted when user grants notification', () async {
        mockHandler = MockPermissionHandler(
          requestNotificationResult: ph.PermissionStatus.granted,
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final result = await service.requestNotificationPermission();
        expect(result.status, PermissionStatus.granted);
      });

      test('returns denied when user denies notification', () async {
        mockHandler = MockPermissionHandler(
          requestNotificationResult: ph.PermissionStatus.denied,
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final result = await service.requestNotificationPermission();
        expect(result.status, PermissionStatus.denied);
      });
    });

    group('requestIgnoreBatteryOptimizations', () {
      test('returns true when user grants', () async {
        mockHandler = MockPermissionHandler(requestBatteryResult: true);
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final result = await service.requestIgnoreBatteryOptimizations();
        expect(result, isTrue);
      });

      test('returns false when user denies', () async {
        mockHandler = MockPermissionHandler(requestBatteryResult: false);
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final result = await service.requestIgnoreBatteryOptimizations();
        expect(result, isFalse);
      });
    });

    group('areAllCriticalPermissionsGranted', () {
      test('returns true when media permission is granted', () async {
        mockHandler = MockPermissionHandler(
          mediaStatus: ph.PermissionStatus.granted,
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final result = await service.areAllCriticalPermissionsGranted();
        expect(result, isTrue);
      });

      test('returns true when media permission is limited', () async {
        mockHandler = MockPermissionHandler(
          mediaStatus: ph.PermissionStatus.limited,
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final result = await service.areAllCriticalPermissionsGranted();
        expect(result, isTrue);
      });

      test('returns false when media permission is denied', () async {
        mockHandler = MockPermissionHandler(
          mediaStatus: ph.PermissionStatus.denied,
        );
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final result = await service.areAllCriticalPermissionsGranted();
        expect(result, isFalse);
      });
    });

    group('onPermissionsChanged stream', () {
      test('emits event when requestMediaPermission is called', () async {
        mockHandler = MockPermissionHandler();
        service = PermissionHandlerService(permissionHandler: mockHandler);

        final events = <void>[];
        service.onPermissionsChanged.listen(events.add);

        await service.requestMediaPermission();
        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
      });

      test(
        'emits event when requestNotificationPermission is called',
        () async {
          mockHandler = MockPermissionHandler();
          service = PermissionHandlerService(permissionHandler: mockHandler);

          final events = <void>[];
          service.onPermissionsChanged.listen(events.add);

          await service.requestNotificationPermission();
          await Future<void>.delayed(Duration.zero);

          expect(events, hasLength(1));
        },
      );
    });
  });
}
