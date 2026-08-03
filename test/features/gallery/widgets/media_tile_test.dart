import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/storage/thumbnail_cache.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/presentation/widgets/media_tile.dart';

/// 1x1 transparent PNG — valid bytes so Image.memory decodes without error.
final Uint8List kTransparentImage = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

void main() {
  MediaItem makeItem({
    String localId = 'test_123',
    String? telegramMessageId,
    String filePath = '/storage/emulated/0/DCIM/photo.jpg',
    MediaStatus status = MediaStatus.pending,
    bool isVideo = false,
  }) {
    return MediaItem(
      localId: localId,
      fileHash: 'abc123',
      telegramMessageId: telegramMessageId,
      filePath: filePath,
      fileName: isVideo ? 'video.mp4' : 'photo.jpg',
      mimeType: isVideo ? 'video/mp4' : 'image/jpeg',
      fileSize: 1024 * 100,
      width: 800,
      height: 600,
      durationMs: isVideo ? 30000 : null,
      createdAt: DateTime(2026, 1, 15),
      modifiedAt: DateTime(2026, 1, 15),
      scannedAt: DateTime(2026, 1, 15),
      status: status,
    );
  }

  Widget wrapInApp(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  // Hermetic loader: thumbnail sourcing via photo_manager/ThumbnailCache is
  // unavailable in widget tests, so non-thumbnail tests inject a stub that
  // simply reports "no thumbnail".
  Future<Uint8List?> noThumbnailLoader(MediaItem _) async => null;

  group('MediaTile', () {
    testWidgets('renders placeholder when no thumbnail is available', (
      tester,
    ) async {
      final item = makeItem();

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(mediaItem: item, thumbnailLoader: noThumbnailLoader),
        ),
      );

      // Two pumps: the default loader hits the (unavailable) photo_manager
      // channel before falling back, which resolves a tick later.
      await tester.pump();
      await tester.pumpAndSettle();

      // Should show the placeholder icon (image icon for non-video)
      expect(find.byIcon(Icons.image), findsOneWidget);
    });

    testWidgets('renders video icon for video items', (tester) async {
      final item = makeItem(isVideo: true);

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(mediaItem: item, thumbnailLoader: noThumbnailLoader),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      // Should show the video placeholder icon
      expect(find.byIcon(Icons.videocam), findsOneWidget);
    });

    testWidgets('shows status indicator when showStatus is true', (
      tester,
    ) async {
      final item = makeItem(status: MediaStatus.uploaded);

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(
            mediaItem: item,
            showStatus: true,
            thumbnailLoader: noThumbnailLoader,
          ),
        ),
      );

      await tester.pump();

      // Should show the cloud done icon for uploaded status
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
    });

    testWidgets('hides status indicator when showStatus is false', (
      tester,
    ) async {
      final item = makeItem(status: MediaStatus.uploaded);

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(
            mediaItem: item,
            showStatus: false,
            thumbnailLoader: noThumbnailLoader,
          ),
        ),
      );

      await tester.pump();

      // Should NOT show the cloud done icon
      expect(find.byIcon(Icons.cloud_done), findsNothing);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      final item = makeItem();
      bool tapped = false;

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(
            mediaItem: item,
            onTap: () => tapped = true,
            thumbnailLoader: noThumbnailLoader,
          ),
        ),
      );

      await tester.tap(find.byType(MediaTile));
      expect(tapped, isTrue);
    });

    testWidgets('shows selection overlay when isSelected is true', (
      tester,
    ) async {
      final item = makeItem();

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(
            mediaItem: item,
            isSelected: true,
            thumbnailLoader: noThumbnailLoader,
          ),
        ),
      );

      await tester.pump();

      // Should show the check icon in the selection overlay
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('applies border when isSelected is true', (tester) async {
      final item = makeItem();

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(
            mediaItem: item,
            isSelected: true,
            thumbnailLoader: noThumbnailLoader,
          ),
        ),
      );

      await tester.pump();

      // The container should have a border decoration
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(MediaTile),
          matching: find.byType(Container).first,
        ),
      );
      expect(container.decoration, isNotNull);
    });

    testWidgets('renders with custom size', (tester) async {
      final item = makeItem();

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(
            mediaItem: item,
            size: 100,
            thumbnailLoader: noThumbnailLoader,
          ),
        ),
      );

      await tester.pump();

      // Should render without errors
      expect(find.byType(MediaTile), findsOneWidget);
    });

    testWidgets('shows pending status icon', (tester) async {
      final item = makeItem(status: MediaStatus.pending);

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(
            mediaItem: item,
            showStatus: true,
            thumbnailLoader: noThumbnailLoader,
          ),
        ),
      );

      await tester.pump();

      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    });

    testWidgets('shows uploading status icon', (tester) async {
      final item = makeItem(status: MediaStatus.uploading);

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(
            mediaItem: item,
            showStatus: true,
            thumbnailLoader: noThumbnailLoader,
          ),
        ),
      );

      await tester.pump();

      expect(find.byIcon(Icons.cloud_sync), findsOneWidget);
    });

    testWidgets('shows failed status icon', (tester) async {
      final item = makeItem(status: MediaStatus.failed);

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(
            mediaItem: item,
            showStatus: true,
            thumbnailLoader: noThumbnailLoader,
          ),
        ),
      );

      await tester.pump();

      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });

    testWidgets('shows excluded status icon', (tester) async {
      final item = makeItem(status: MediaStatus.excluded);

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(
            mediaItem: item,
            showStatus: true,
            thumbnailLoader: noThumbnailLoader,
          ),
        ),
      );

      await tester.pump();

      expect(find.byIcon(Icons.block), findsOneWidget);
    });

    testWidgets('video item shows play indicator', (tester) async {
      final item = makeItem(isVideo: true);

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(mediaItem: item, thumbnailLoader: noThumbnailLoader),
        ),
      );

      await tester.pump();

      // Should show the play arrow icon
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('renders thumbnail image when thumbnail loader returns bytes', (
      tester,
    ) async {
      final item = makeItem();

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(
            mediaItem: item,
            thumbnailLoader: (_) async => kTransparentImage,
          ),
        ),
      );

      await tester.pump();

      // Cache-hit path: image bytes render instead of the placeholder.
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.image), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps placeholder when thumbnail loader returns null', (
      tester,
    ) async {
      final item = makeItem();

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(mediaItem: item, thumbnailLoader: (_) async => null),
        ),
      );

      await tester.pump();

      expect(find.byIcon(Icons.image), findsOneWidget);
    });

    testWidgets('falls back to placeholder when default loader times out '
        'on a non-telegram item', (tester) async {
      final item = makeItem();

      // Default loader attempts AssetEntity.fromId, which is unavailable in
      // the widget test environment — it must time out and fall back to the
      // placeholder instead of crashing or blocking the grid.
      await tester.pumpWidget(wrapInApp(MediaTile(mediaItem: item)));

      await tester.pump();
      // Advance fake time past the loader's 15s photo_manager timeout and the
      // 5s on-disk file-read timeout so the pending timers fire and the
      // future completes with the placeholder.
      await tester.pump(const Duration(seconds: 16));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();

      expect(find.byIcon(Icons.image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reloads the thumbnail when reloadGeneration changes', (
      tester,
    ) async {
      final item = makeItem();
      var loaderCalls = 0;
      Future<Uint8List?> countingLoader(MediaItem _) async {
        loaderCalls++;
        return null;
      }

      await tester.pumpWidget(
        wrapInApp(
          MediaTile(
            mediaItem: item,
            thumbnailLoader: countingLoader,
            reloadGeneration: 0,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(loaderCalls, 1);

      // Same generation, rebuilt widget — must NOT reload.
      await tester.pumpWidget(
        wrapInApp(
          MediaTile(
            mediaItem: item,
            thumbnailLoader: countingLoader,
            reloadGeneration: 0,
          ),
        ),
      );
      await tester.pump();
      expect(loaderCalls, 1);

      // Generation bump — must reload.
      await tester.pumpWidget(
        wrapInApp(
          MediaTile(
            mediaItem: item,
            thumbnailLoader: countingLoader,
            reloadGeneration: 1,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(loaderCalls, 2);
    });
  });

  group('MediaTile.defaultThumbnailLoader file fallback', () {
    // Plain tests (no FakeAsync) so the loader's real dart:io fallback can
    // actually complete — a widget test's fake-async zone can't drive it.
    setUp(() => ThumbnailCache.instance.clear());

    test('reads the on-disk file when photo_manager is unavailable', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'lumovault_media_tile_loader_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/photo.jpg');
      await file.writeAsBytes(kTransparentImage);
      final item = makeItem(localId: 'fallback_image_1', filePath: file.path);

      final bytes = await MediaTile.defaultThumbnailLoader(item);

      expect(bytes, isNotNull);
      expect(bytes, kTransparentImage);
    });

    test('does not read the file for video items', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'lumovault_media_tile_loader_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/video.mp4');
      await file.writeAsBytes(kTransparentImage);
      final item = makeItem(
        localId: 'fallback_video_1',
        filePath: file.path,
        isVideo: true,
      );

      final bytes = await MediaTile.defaultThumbnailLoader(item);

      expect(bytes, isNull);
    });

    test('returns null when the on-disk file is missing', () async {
      final item = makeItem(
        localId: 'fallback_missing_1',
        filePath: '/nonexistent/path/photo.jpg',
      );

      final bytes = await MediaTile.defaultThumbnailLoader(item);

      expect(bytes, isNull);
    });
  });
}
