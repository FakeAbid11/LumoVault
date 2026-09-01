import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:lumovault/core/di/gallery_providers.dart';
import 'package:lumovault/core/di/tdlib_providers.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';
import 'package:lumovault/features/gallery/presentation/screens/timeline_screen.dart';
import 'package:lumovault/features/settings/data/models/app_settings.dart';
import 'package:lumovault/features/settings/data/repositories/settings_repository.dart';
import 'package:lumovault/features/settings/presentation/providers/settings_providers.dart';

/// Regression tests for the timeline's empty-state auth handling.
///
/// The empty state used to key purely off `isAuthenticatedProvider`, which is
/// false for the first seconds of EVERY cold start (the TDLib session restores
/// asynchronously and nothing read it before the first frame). Signed-in users
/// were therefore flashed a "Sign in to Telegram" prompt after every restart —
/// most visibly the skip-user who signed in later and then relaunched the app.
class _FakeScannerService implements MediaScannerService {
  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<ScanResult> scanDevice({
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
  }) async => const ScanResult(
    mediaItems: [],
    folders: [],
    totalScanned: 0,
    newItems: 0,
    updatedItems: 0,
    duration: Duration.zero,
  );

  @override
  Future<List<AssetEntity>> listAllAssets({
    void Function(int loaded)? onProgress,
  }) async => const [];

  @override
  Future<Uint8List?> getThumbnail(String assetId) async => null;

  @override
  Future<File?> getFullFile(String assetId) async => null;

  @override
  Future<List<DeviceFolder>> getDeviceFolders() async => const [];
}

/// In-memory stand-in for flutter_secure_storage so the real
/// [SettingsRepository]/settings notifier chain can run without the platform
/// channel (which never resolves in the flutter test VM).
class _InMemorySecureStorage implements FlutterSecureStorage {
  _InMemorySecureStorage([Map<String, String?>? initial])
    : _data = initial ?? {};

  final Map<String, String?> _data;

  @override
  Future<void> write({
    required String key,
    String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data[key] = value;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data.remove(key);

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data.clear();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget wrap({
  required bool authenticated,
  required bool authSettled,
  required AppSettings settings,
}) {
  return ProviderScope(
    overrides: [
      galleryRepositoryProvider.overrideWith(
        (ref) => GalleryRepository(
          scannerService: _FakeScannerService(),
          mediaDao: null,
        ),
      ),
      isAuthenticatedProvider.overrideWithValue(authenticated),
      authSettledProvider.overrideWith((ref) => Future.value(authSettled)),
      settingsRepositoryProvider.overrideWithValue(
        SettingsRepository(
          storage: _InMemorySecureStorage({
            'lumovault_settings': settings.toJsonString(),
          }),
        ),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: TimelineScreen())),
  );
}

void main() {
  testWidgets('skip-user (never signed in): offers the sign-in prompt', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        authenticated: false,
        authSettled: true,
        settings: const AppSettings(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in to Telegram'), findsOneWidget);
    expect(find.text('Connecting to Telegram…'), findsNothing);
  });

  testWidgets(
    'signed-in user, session still restoring: connecting state, NOT the prompt',
    (tester) async {
      // This is the bug: a signed-in user (persisted hasTelegramAccount)
      // whose TDLib session hasn't finished restoring must not be shown a
      // login prompt — it made them believe they'd been signed out.
      await tester.pumpWidget(
        wrap(
          authenticated: false,
          authSettled: false,
          settings: const AppSettings(hasTelegramAccount: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connecting to Telegram…'), findsOneWidget);
      expect(find.text('Sign in to Telegram'), findsNothing);
    },
  );

  testWidgets(
    'session failed to restore (settled + unauthenticated): actionable prompt',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          authenticated: false,
          authSettled: true,
          settings: const AppSettings(hasTelegramAccount: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign in to Telegram'), findsOneWidget);
    },
  );

  testWidgets('authenticated: generic empty state, never a sign-in prompt', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        authenticated: true,
        authSettled: true,
        settings: const AppSettings(hasTelegramAccount: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No backed up photos yet'), findsOneWidget);
    expect(find.text('Sign in to Telegram'), findsNothing);
    expect(find.text('Connecting to Telegram…'), findsNothing);
  });
}
