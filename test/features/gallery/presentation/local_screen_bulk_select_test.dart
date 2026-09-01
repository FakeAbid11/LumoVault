import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:lumovault/core/di/gallery_providers.dart';
import 'package:lumovault/core/di/providers.dart';
import 'package:lumovault/core/permissions/permission_service.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';
import 'package:lumovault/features/gallery/presentation/screens/local_screen.dart';
import 'package:lumovault/features/gallery/presentation/widgets/asset_tile.dart';

/// Reproduction for the bulk-select black screen: long-pressing a tile in the
/// Local tab flips the whole Scaffold into selection mode (AppBar swap, FAB
/// removal, selection bar, per-tile overlays). If any widget in that rebuild
/// throws, the app's ErrorBoundary swallows it into a blank frame â€” surfacing
/// here as a test failure with the real exception instead.
class _FakeScannerService implements MediaScannerService {
  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<ScanResult> scanDevice({
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
  }) async {
    return const ScanResult(
      mediaItems: [],
      folders: [],
      totalScanned: 0,
      newItems: 0,
      updatedItems: 0,
      duration: Duration.zero,
    );
  }

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

Widget wrap(List<AssetEntity> assets) {
  return ProviderScope(
    overrides: [
      mediaPermissionStatusProvider.overrideWith(
        (ref) async => PermissionStatus.granted,
      ),
      deviceAssetsProvider.overrideWith((ref) => Future.value(assets)),
      galleryRepositoryProvider.overrideWith(
        (ref) => GalleryRepository(
          scannerService: _FakeScannerService(),
          mediaDao: null,
        ),
      ),
    ],
    child: const MaterialApp(home: LocalScreen()),
  );
}

AssetEntity asset(String id, {int createdSecond = 1000}) => AssetEntity(
  id: id,
  typeInt: 1,
  width: 100,
  height: 100,
  title: 'IMG_$id.jpg',
  createDateSecond: createdSecond,
);

void main() {
  testWidgets('long-press enters bulk-select mode without any widget error', (
    tester,
  ) async {
    final assets = [asset('a1'), asset('a2'), asset('a3')];

    await tester.pumpWidget(wrap(assets));
    await tester.pump(const Duration(milliseconds: 100));

    // Long-press the first tile â€” the bulk-select entry gesture.
    await tester.longPress(find.byType(AssetTile).first);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('1 selected'), findsOneWidget);
    // The FAB is animating out while the selection bar animates in, so
    // 'Backup' can legitimately appear twice mid-transition.
    expect(find.text('Backup'), findsWidgets);
    expect(find.text('Select all'), findsOneWidget);
  });

  testWidgets('tapping a selected tile exits selection mode without errors', (
    tester,
  ) async {
    final assets = [asset('a1'), asset('a2')];

    await tester.pumpWidget(wrap(assets));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.longPress(find.byType(AssetTile).first);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byType(AssetTile).first);
    await tester.pump(const Duration(milliseconds: 100));

    // Toggling the only selection off returns to the normal app bar.
    expect(find.text('LumoVault'), findsOneWidget);
  });
}
