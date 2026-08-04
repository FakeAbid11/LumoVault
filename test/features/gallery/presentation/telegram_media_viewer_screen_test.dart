import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/di/tdlib_providers.dart';
import 'package:lumovault/core/storage/storage_channel_service.dart';
import 'package:lumovault/core/tdlib/tdlib_client.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/repositories/telegram_download_service.dart';
import 'package:lumovault/features/gallery/presentation/screens/telegram_media_viewer_screen.dart';
import 'package:lumovault/features/restore/presentation/providers/restore_providers.dart';

/// Behavioural coverage for [TelegramMediaViewerScreen].
///
/// The viewer's image page downloads the original via
/// [DownloadService.downloadFile]; the fake below keeps the download open so
/// the test can assert the request (mode/channel/message) and the in-flight
/// UI without real TDLib or real file I/O — which a widget test's fake-async
/// zone can't drive anyway.
void main() {
  const int channelId = -10042;

  MediaItem telegramItem({String localId = 'tg_1', String messageId = '7'}) {
    return MediaItem(
      localId: localId,
      fileHash: 'hash_$localId',
      telegramMessageId: messageId,
      telegramFileId: '900',
      filePath: 'telegram://$messageId',
      fileName: 'photo.jpg',
      mimeType: 'image/jpeg',
      fileSize: 0,
      width: 0,
      height: 0,
      createdAt: DateTime(2026, 1, 15),
      modifiedAt: DateTime(2026, 1, 15),
      scannedAt: DateTime(2026, 1, 15),
      status: MediaStatus.uploaded,
    );
  }

  Widget app({
    required DownloadService downloadService,
    required StorageChannelService channels,
    required List<MediaItem> items,
    int initialIndex = 0,
  }) {
    return ProviderScope(
      overrides: [
        downloadServiceProvider.overrideWithValue(downloadService),
        storageChannelServiceProvider.overrideWithValue(channels),
      ],
      child: MaterialApp(
        home: TelegramMediaViewerScreen(
          items: items,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  StorageChannelService cachedChannel() {
    return StorageChannelService(
      client: TdLibClient.instance,
      requestSender: _NoopSend().send,
    )..setCachedChannelId(channelId);
  }

  testWidgets('downloads the original for the tapped item with progress UI', (
    tester,
  ) async {
    final downloads = _HoldingDownloadService();
    final items = [
      telegramItem(),
      telegramItem(localId: 'tg_2', messageId: '8'),
    ];

    await tester.pumpWidget(
      app(downloadService: downloads, channels: cachedChannel(), items: items),
    );
    await tester.pump();

    // Swipe-through counter + the in-flight download state.
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('Downloading original…'), findsOneWidget);
    expect(downloads.calls.length, 1);
    expect(downloads.calls.single.messageId, 7);
    expect(downloads.calls.single.channelId, channelId);
    expect(downloads.calls.single.mode, DownloadMode.original);
  });

  testWidgets('shows an error state with retry when the download fails', (
    tester,
  ) async {
    final downloads = _HoldingDownloadService()..failNext = true;

    await tester.pumpWidget(
      app(
        downloadService: downloads,
        channels: cachedChannel(),
        items: [telegramItem()],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Bad state: download failed'), findsOneWidget);

    // Retry issues a fresh download for the same item.
    downloads.failNext = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(downloads.calls.length, 2);
    expect(downloads.calls.last.messageId, 7);
    expect(find.text('Downloading original…'), findsOneWidget);
  });

  testWidgets('video items show the play badge without downloading', (
    tester,
  ) async {
    final downloads = _HoldingDownloadService();
    final video = telegramItem().copyWith(
      mimeType: 'video/mp4',
      fileName: 'clip.mp4',
      durationMs: 30000,
    );

    await tester.pumpWidget(
      app(
        downloadService: downloads,
        channels: cachedChannel(),
        items: [video],
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('0:30 · Stored in Telegram'), findsOneWidget);
    // Videos never fetch the original — only the thumbnail is requested.
    expect(downloads.calls.length, 1);
    expect(downloads.calls.single.mode, DownloadMode.thumbnail);
  });

  testWidgets('the info action opens the backup detail sheet', (tester) async {
    final downloads = _HoldingDownloadService();

    await tester.pumpWidget(
      app(
        downloadService: downloads,
        channels: cachedChannel(),
        items: [telegramItem()],
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('Backed up to Telegram'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
  });
}

/// Keeps downloads pending (or fails them) so no real file I/O happens.
class _HoldingDownloadService implements DownloadService {
  bool failNext = false;

  final calls = <_DownloadCall>[];

  @override
  Stream<DownloadProgress> get progressStream => const Stream.empty();

  @override
  Future<DownloadResult> downloadFile({
    required String taskId,
    required int messageId,
    required int channelId,
    DownloadMode mode = DownloadMode.original,
  }) {
    calls.add(_DownloadCall(taskId, messageId, channelId, mode));
    if (failNext) {
      failNext = false;
      return Future.error(StateError('download failed'));
    }
    return Completer<DownloadResult>().future;
  }

  @override
  Future<void> cancelDownload(String taskId) async {}
}

class _DownloadCall {
  const _DownloadCall(this.taskId, this.messageId, this.channelId, this.mode);
  final String taskId;
  final int messageId;
  final int channelId;
  final DownloadMode mode;
}

class _NoopSend {
  Future<Map<String, dynamic>> send({
    required String method,
    Map<String, dynamic>? params,
  }) async {
    return const {'@type': 'ok'};
  }
}
