import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/di/channel_scan_providers.dart';
import 'package:lumovault/core/storage/storage_channel_service.dart';
import 'package:lumovault/core/storage/thumbnail_cache.dart';
import 'package:lumovault/core/tdlib/tdlib_client.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/repositories/telegram_download_service.dart';

/// 1x1 transparent PNG — valid image bytes so cache assertions are meaningful.
final Uint8List kPngBytes = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const int channelId = -10042;

  MediaItem telegramItem({
    String localId = 'fetcher_item_1',
    String? messageId = '42',
  }) {
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

  StorageChannelService cachedChannel() {
    return StorageChannelService(
      client: TdLibClient.instance,
      requestSender: _ChannelSend().send,
    )..setCachedChannelId(channelId);
  }

  setUp(() => ThumbnailCache.instance.clear());

  group('TelegramThumbnailFetcher', () {
    test('downloads, caches, and returns the thumbnail bytes', () async {
      final downloads = _FakeDownloadService();
      final fetcher = TelegramThumbnailFetcher(
        downloadService: downloads,
        storageChannelService: cachedChannel(),
      );
      final item = telegramItem();

      final bytes = await fetcher.fetch(item);

      expect(bytes, kPngBytes);
      expect(await ThumbnailCache.instance.get(item.localId), kPngBytes);
      expect(downloads.calls.length, 1);
      expect(downloads.calls.single.messageId, 42);
      expect(downloads.calls.single.channelId, channelId);
      expect(downloads.calls.single.mode, DownloadMode.thumbnail);
    });

    test(
      'serves subsequent requests from the cache without re-downloading',
      () async {
        final downloads = _FakeDownloadService();
        final fetcher = TelegramThumbnailFetcher(
          downloadService: downloads,
          storageChannelService: cachedChannel(),
        );
        final item = telegramItem();

        final first = await fetcher.fetch(item);
        final second = await fetcher.fetch(item);

        expect(first, kPngBytes);
        expect(second, kPngBytes);
        expect(downloads.calls.length, 1);
      },
    );

    test('deduplicates concurrent requests for the same item', () async {
      final downloads = _FakeDownloadService()..gateDownloads = true;
      final fetcher = TelegramThumbnailFetcher(
        downloadService: downloads,
        storageChannelService: cachedChannel(),
      );
      final item = telegramItem();

      final first = fetcher.fetch(item);
      final second = fetcher.fetch(item);

      downloads.gateDownloads = false;
      downloads.releaseAll();

      final results = await Future.wait([first, second]);
      expect(results, [kPngBytes, kPngBytes]);
      // One in-flight download shared by both callers.
      expect(downloads.calls.length, 1);
    });

    test('returns null for local (non-Telegram) items', () async {
      final downloads = _FakeDownloadService();
      final fetcher = TelegramThumbnailFetcher(
        downloadService: downloads,
        storageChannelService: cachedChannel(),
      );
      final item = telegramItem(messageId: null).copyWith(
        filePath: '/storage/emulated/0/DCIM/photo.jpg',
        telegramMessageId: null,
      );

      final bytes = await fetcher.fetch(item);

      expect(bytes, isNull);
      expect(downloads.calls, isEmpty);
    });

    test('returns null when the message id is not a number', () async {
      final downloads = _FakeDownloadService();
      final fetcher = TelegramThumbnailFetcher(
        downloadService: downloads,
        storageChannelService: cachedChannel(),
      );
      final item = telegramItem(messageId: 'not-a-number');

      final bytes = await fetcher.fetch(item);

      expect(bytes, isNull);
      expect(downloads.calls, isEmpty);
    });

    test('a failed download returns null and enters the cooldown', () async {
      final downloads = _FakeDownloadService()..throwOnDownload = true;
      final fetcher = TelegramThumbnailFetcher(
        downloadService: downloads,
        storageChannelService: cachedChannel(),
        failureCooldown: const Duration(milliseconds: 50),
      );
      final item = telegramItem();

      final failed = await fetcher.fetch(item);
      // Retry inside the cooldown window — no new attempt, still null.
      final retry = await fetcher.fetch(item);

      expect(failed, isNull);
      expect(retry, isNull);
      expect(downloads.calls.length, 1, reason: 'cooldown suppresses retries');
    });

    test('retries a failed download after the cooldown expires', () async {
      final downloads = _FakeDownloadService()..throwOnDownload = true;
      final fetcher = TelegramThumbnailFetcher(
        downloadService: downloads,
        storageChannelService: cachedChannel(),
        failureCooldown: const Duration(milliseconds: 50),
      );
      final item = telegramItem();

      expect(await fetcher.fetch(item), isNull);

      // Let the cooldown elapse, then make the download succeed.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      downloads.throwOnDownload = false;

      final bytes = await fetcher.fetch(item);

      expect(bytes, kPngBytes);
      expect(downloads.calls.length, 2);
    });

    test('resolves the channel id when none is cached', () async {
      final sender = _ChannelSend();
      final channels = StorageChannelService(
        client: TdLibClient.instance,
        requestSender: sender.send,
      );
      final downloads = _FakeDownloadService();
      final fetcher = TelegramThumbnailFetcher(
        downloadService: downloads,
        storageChannelService: channels,
      );

      final bytes = await fetcher.fetch(telegramItem());

      // The storage channel was found by title search and cached for reuse.
      expect(bytes, kPngBytes);
      expect(channels.cachedChannelId, channelId);
      expect(downloads.calls.single.channelId, channelId);
    });

    test('returns null when no storage channel can be found', () async {
      final sender = _ChannelSend()..emptyChatList = true;
      final channels = StorageChannelService(
        client: TdLibClient.instance,
        requestSender: sender.send,
      );
      final downloads = _FakeDownloadService();
      final fetcher = TelegramThumbnailFetcher(
        downloadService: downloads,
        storageChannelService: channels,
      );

      final bytes = await fetcher.fetch(telegramItem());

      expect(bytes, isNull);
      expect(downloads.calls, isEmpty);
    });
  });
}

/// Serves the handful of TDLib methods the channel lookup path uses.
class _ChannelSend {
  bool emptyChatList = false;

  Future<Map<String, dynamic>> send({
    required String method,
    Map<String, dynamic>? params,
  }) async {
    switch (method) {
      case 'getChat':
        return {
          'id': -10042,
          'title': 'LumoVault Backup',
          'type': {'@type': 'chatTypeSupergroup', 'is_channel': true},
        };
      case 'loadChats':
        return const {'@type': 'ok'};
      case 'getChats':
        return {
          'chat_ids': emptyChatList ? const <int>[] : const [-10042],
        };
      default:
        return const {'@type': 'ok'};
    }
  }
}

class _FakeDownloadService implements DownloadService {
  /// When set, every download fails immediately.
  bool throwOnDownload = false;

  /// When set, downloads wait for [releaseAll] instead of completing — used
  /// to hold two concurrent fetches open and prove they share one download.
  bool gateDownloads = false;

  final _gates = <Completer<void>>[];

  /// Task id, message id, channel id and mode of every download, in order.
  final calls = <_DownloadCall>[];

  @override
  Stream<DownloadProgress> get progressStream => const Stream.empty();

  @override
  Future<DownloadResult> downloadFile({
    required String taskId,
    required int messageId,
    required int channelId,
    DownloadMode mode = DownloadMode.original,
  }) async {
    calls.add(_DownloadCall(taskId, messageId, channelId, mode));
    if (throwOnDownload) throw StateError('download failed');

    if (gateDownloads) {
      final gate = Completer<void>();
      _gates.add(gate);
      await gate.future;
    }

    final file = File(
      '${Directory.systemTemp.path}/lumovault_fetcher_$messageId.bin',
    );
    await file.writeAsBytes(kPngBytes);
    return DownloadResult(taskId: taskId, filePath: file.path);
  }

  void releaseAll() {
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
    _gates.clear();
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
