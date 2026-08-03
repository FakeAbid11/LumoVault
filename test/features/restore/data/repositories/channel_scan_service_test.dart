import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/storage/storage_channel_service.dart';
import 'package:lumovault/core/storage/thumbnail_cache.dart';
import 'package:lumovault/core/tdlib/tdlib_client.dart';
import 'package:lumovault/core/tdlib/tdlib_exception.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';
import 'package:lumovault/features/gallery/data/repositories/telegram_download_service.dart';
import 'package:lumovault/features/restore/data/repositories/channel_scan_service.dart';
import 'package:photo_manager/photo_manager.dart';

/// Behavioural coverage for [ChannelScanService.scanChannel] — chiefly its
/// pagination loop, which had no tests when it contained a truncation bug.
///
/// The bug: `_fetchMessages` terminated on `messagesList.length < limit`.
/// `getChatHistory` may legitimately return a short page while more history
/// remains, so one short page silently ended the scan and the restore
/// under-reported the library with no error anywhere. The fix pages until an
/// empty result, with a stalled-cursor bail-out to bound the loop. Both halves
/// are locked in below — a short page must NOT stop the scan, an empty page
/// must, and a non-advancing cursor must break rather than spin forever.
///
/// [TdLibClient] can't be faked (private constructor, FFI singleton), so the
/// service takes an injectable [TdRequestSender]. The real client instance is
/// still passed for the non-test path; its methods are never reached.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ThumbnailCache.initialize() calls getTemporaryDirectory(), which throws
  // MissingPluginException under flutter_test. scanChannel catches it and
  // returns an error result, so without this stub every test would assert
  // against a failed scan. Stubbing the channel keeps path_provider out of
  // dev_dependencies (it's a transitive dep — importing its platform
  // interface directly would be an undeclared-dependency lint).
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('lumovault_scan_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    // The singleton ThumbnailCache persists across tests in this file —
    // clearing it keeps each test's thumbnail assertions hermetic.
    ThumbnailCache.instance.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('ChannelScanService pagination', () {
    test('a short page does not end the scan', () async {
      // The regression case. Page 1 is deliberately shorter than the 100-item
      // request limit; the old `length < limit` break would have stopped here
      // and reported 3 items instead of 5.
      final client = _FakeTdRequests([
        _page([1, 2, 3]),
        _page([4, 5]),
        _page(const []),
      ]);
      final service = _service(client);

      final result = await service.scanChannel();

      expect(result.error, isNull);
      expect(result.totalItems, 5);
      expect(client.calls.length, 3);
    });

    test('pages until an empty result, following the cursor', () async {
      final client = _FakeTdRequests([
        _page([10, 9]),
        _page([8, 7]),
        _page(const []),
      ]);
      final service = _service(client);

      await service.scanChannel();

      // from_message_id starts at 0, then tracks the last id of each page.
      expect(client.calls.map((c) => c['from_message_id']).toList(), [0, 9, 7]);
      expect(client.calls.every((c) => c['chat_id'] == _channelId), isTrue);
      expect(client.calls.every((c) => c['limit'] == 100), isTrue);
    });

    test('an empty first page reports hasBackup with no items', () async {
      final service = _service(_FakeTdRequests([_page(const [])]));

      final result = await service.scanChannel();

      expect(result.totalItems, 0);
      // The channel exists — it's just empty. Distinct from "no backup".
      expect(result.hasBackup, isTrue);
      expect(result.error, isNull);
    });

    test('a stalled cursor breaks the loop instead of spinning', () async {
      // Same page forever: the cursor never advances. Guarding this is the
      // reason the terminator can safely be "empty page" — without it the
      // loop would issue network requests without bound.
      final client = _FakeTdRequests.repeating(_page([42]));
      final service = _service(client);

      final result = await service.scanChannel();

      // Two calls: the first page, then the repeat that reveals the stall.
      // The loop is bounded — that's the point of the guard.
      expect(client.calls.length, 2);
      // The repeated message is collected twice, but dedup by file hash means
      // only one item reaches the gallery.
      expect(result.totalItems, 2);
      expect(result.newItems, 1);
      expect(result.skippedItems, 1);
    });

    test('messages with no usable content are skipped, not counted', () async {
      final client = _FakeTdRequests([
        {
          'messages': [
            _document(1),
            // A join/leave service message: no document, photo or video.
            {
              'id': 2,
              'date': 1700000000,
              'content': {'@type': 'messageChatAddMembers'},
            },
          ],
        },
        _page(const []),
      ]);
      final service = _service(client);

      final result = await service.scanChannel();

      expect(result.totalItems, 1);
    });
  });

  group('ChannelScanService item building', () {
    test('documents, photos and videos are all recognised', () async {
      final client = _FakeTdRequests([
        {
          'messages': [_document(1), _photo(2), _video(3)],
        },
        _page(const []),
      ]);
      final repo = _repo();
      final service = _service(client, repo: repo);

      final result = await service.scanChannel();

      expect(result.totalItems, 3);
      expect(result.newItems, 3);
      expect(repo.mediaItems.length, 3);
      expect(
        repo.mediaItems.map((i) => i.fileName),
        containsAll(<String>['doc_1.jpg', 'photo_2.jpg', 'video_3.mp4']),
      );
    });

    test('items already in the gallery are skipped as duplicates', () async {
      final client = _FakeTdRequests([
        {
          'messages': [_document(1), _document(1)],
        },
        _page(const []),
      ]);
      final service = _service(client);

      final result = await service.scanChannel();

      // Identical message ids hash to the same fallback fileHash, so the
      // second is a duplicate. Both are still counted in totalItems.
      expect(result.totalItems, 2);
      expect(result.newItems, 1);
      expect(result.skippedItems, 1);
    });

    test('a failed thumbnail download still yields the item', () async {
      final client = _FakeTdRequests([
        {
          'messages': [_document(1)],
        },
        _page(const []),
      ]);
      final downloads = _FakeDownloadService()..throwOnDownload = true;
      final service = _service(client, downloads: downloads);

      final result = await service.scanChannel();

      // A missing thumbnail must not lose the item — it renders with a
      // placeholder instead.
      expect(result.newItems, 1);
      expect(result.failedThumbnails, 1);
    });

    test('progress is reported for every message', () async {
      final client = _FakeTdRequests([
        {
          'messages': [_document(1), _document(2)],
        },
        _page(const []),
      ]);
      final service = _service(client);

      final seen = <int>[];
      await service.scanChannel(
        onProgress: (current, total, _) => seen.add(current),
      );

      expect(seen, [1, 2]);
    });
  });

  group('ChannelScanService scan state', () {
    test(
      'a second scan replays the first result rather than refetching',
      () async {
        final client = _FakeTdRequests([
          {
            'messages': [_document(1)],
          },
          _page(const []),
        ]);
        final service = _service(client);

        final first = await service.scanChannel();
        final callsAfterFirst = client.calls.length;
        final second = await service.scanChannel();

        expect(client.calls.length, callsAfterFirst, reason: 'no refetch');
        expect(second.totalItems, first.totalItems);
        expect(second.hasBackup, isTrue);
        expect(second.alreadyScanned, isTrue);
        // The replay must not look like "this account has no backup".
        expect(first.alreadyScanned, isFalse);
      },
    );

    test('a failed scan stays retryable', () async {
      final client = _FakeTdRequests.throwing(
        const TdLibException(message: 'boom', code: 'CLIENT_NOT_INITIALIZED'),
      );
      final service = _service(client);

      final result = await service.scanChannel();

      expect(result.hasError, isTrue);
      expect(service.hasScanned, isFalse);

      // A retry after the transport recovers must actually re-fetch.
      client.nextPages = [
        {
          'messages': [_document(1)],
        },
        _page(const []),
      ];
      final retry = await service.scanChannel();
      expect(retry.hasError, isFalse);
      expect(retry.totalItems, 1);
    });

    test('resetScanState forces the next scan to refetch', () async {
      final client = _FakeTdRequests([
        {
          'messages': [_document(1)],
        },
        _page(const []),
      ]);
      final service = _service(client);

      await service.scanChannel();
      expect(service.hasScanned, isTrue);

      service.resetScanState();
      expect(service.hasScanned, isFalse);

      client.nextPages = [
        {
          'messages': [_document(1), _document(2)],
        },
        _page(const []),
      ];
      final rescan = await service.scanChannel();
      expect(rescan.totalItems, 2);
    });

    test('a channel lookup failure is an error, not "no backup"', () async {
      // No cached id, and the chat-list search itself fails: we never learn
      // whether a channel exists.
      final client = _FakeTdRequests([_page(const [])])
        ..chatListError = const TdLibException(
          message: 'network down',
          code: 'NETWORK',
        );
      final service = _service(client, cacheChannelId: false);

      final result = await service.scanChannel();

      expect(result.hasError, isTrue);
      expect(result.hasBackup, isFalse);
      // Must stay retryable — recording this as scanned would wedge the
      // session into reporting "no backup" until restart.
      expect(service.hasScanned, isFalse);
    });

    test(
      'a definitive empty chat list reports no backup, and sticks',
      () async {
        // The search ran and genuinely found nothing. Unlike the failure above,
        // this is an answer, so it's recorded.
        final service = _service(
          _FakeTdRequests([_page(const [])]),
          cacheChannelId: false,
        );

        final result = await service.scanChannel();

        expect(result.hasError, isFalse);
        expect(result.hasBackup, isFalse);
        expect(service.hasScanned, isTrue);
      },
    );
  });

  group('ChannelScanService thumbnail self-healing', () {
    test('duplicate-hash items still fetch a missing thumbnail', () async {
      // Seed the gallery with an item whose hash matches the channel message
      // (e.g. a restore that populated the gallery but never cached the
      // thumbnail). The message is a duplicate from the start — but its
      // thumbnail must still be downloaded and cached.
      final repo = _repo();
      final message1Hash = sha256.convert(utf8.encode('msg_1_901')).toString();
      await repo.mergeTelegramItems([
        MediaItem(
          localId: 'msg_1',
          fileHash: message1Hash,
          telegramMessageId: '1',
          filePath: 'telegram://1',
          fileName: 'doc_1.jpg',
          mimeType: 'image/jpeg',
          fileSize: 0,
          width: 0,
          height: 0,
          createdAt: DateTime(2026, 1, 1),
          modifiedAt: DateTime(2026, 1, 1),
          scannedAt: DateTime(2026, 1, 1),
          status: MediaStatus.uploaded,
        ),
      ]);
      final downloads = _FakeDownloadService();
      final client = _FakeTdRequests([
        {
          'messages': [_document(1)],
        },
        _page(const []),
      ]);
      final service = _service(client, repo: repo, downloads: downloads);

      final result = await service.scanChannel();

      expect(result.newItems, 0);
      expect(result.skippedItems, 1);
      expect(
        downloads.calls.length,
        1,
        reason: 'duplicate items must still get their thumbnail',
      );
      expect(downloads.calls.single, DownloadMode.thumbnail);
      expect(
        await ThumbnailCache.instance.contains('msg_1'),
        isTrue,
        reason: 'the thumbnail must heal the existing tile in place',
      );
    });

    test(
      'a rescan refetches thumbnails that failed on the first pass',
      () async {
        final client = _FakeTdRequests([
          {
            'messages': [_document(1)],
          },
          _page(const []),
        ]);
        final downloads = _FakeDownloadService()..throwOnDownload = true;
        final service = _service(client, downloads: downloads);

        final first = await service.scanChannel();
        expect(first.failedThumbnails, 1);
        expect(await ThumbnailCache.instance.contains('msg_1'), isFalse);

        // The item is in the gallery but its thumbnail never made it. A force
        // rescan must refetch it — through the duplicate path.
        downloads.throwOnDownload = false;
        service.resetScanState();
        client.nextPages = [
          {
            'messages': [_document(1)],
          },
          _page(const []),
        ];

        final rescan = await service.scanChannel();

        expect(rescan.skippedItems, 1);
        expect(downloads.calls.length, 2);
        expect(await ThumbnailCache.instance.contains('msg_1'), isTrue);
      },
    );

    test('a rescan does not re-download thumbnails that are cached', () async {
      final client = _FakeTdRequests([
        {
          'messages': [_document(1)],
        },
        _page(const []),
      ]);
      final downloads = _FakeDownloadService();
      final service = _service(client, downloads: downloads);

      final first = await service.scanChannel();
      expect(first.failedThumbnails, 0);
      expect(await ThumbnailCache.instance.contains('msg_1'), isTrue);

      service.resetScanState();
      client.nextPages = [
        {
          'messages': [_document(1)],
        },
        _page(const []),
      ];

      final rescan = await service.scanChannel();

      expect(rescan.skippedItems, 1);
      expect(
        downloads.calls.length,
        1,
        reason: 'cached thumbnails are served, not re-downloaded',
      );
      expect(await ThumbnailCache.instance.contains('msg_1'), isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const int _channelId = -100123;

ChannelScanService _service(
  _FakeTdRequests client, {
  _FakeGalleryRepository? repo,
  _FakeDownloadService? downloads,
  bool cacheChannelId = true,
}) {
  // findExistingChannel re-validates the cached id with a `getChat` before
  // reusing it, so the channel service needs the fake sender as well —
  // otherwise the check hits the real (uninitialized) client, fails, and
  // every scan comes back as a lookup error.
  final channels = StorageChannelService(
    client: TdLibClient.instance,
    requestSender: client.send,
  );
  if (cacheChannelId) channels.setCachedChannelId(_channelId);

  return ChannelScanService(
    // Never used — requestSender takes over every call the scanner makes.
    client: TdLibClient.instance,
    storageChannelService: channels,
    downloadService: downloads ?? _FakeDownloadService(),
    galleryRepository: repo ?? _repo(),
    requestSender: client.send,
  );
}

_FakeGalleryRepository _repo() => _FakeGalleryRepository();

/// A `getChatHistory` response carrying one document message per id.
Map<String, dynamic> _page(List<int> ids) => {
  'messages': ids.map(_document).toList(),
};

Map<String, dynamic> _document(int id) => {
  'id': id,
  'date': 1700000000 + id,
  'content': {
    '@type': 'messageDocument',
    'document': {'id': 900 + id, 'file_name': 'doc_$id.jpg'},
  },
};

Map<String, dynamic> _photo(int id) => {
  'id': id,
  'date': 1700000000 + id,
  'content': {
    '@type': 'messagePhoto',
    'photo': {
      'sizes': [
        {
          'photo': {'id': 800 + id},
        },
      ],
    },
  },
};

Map<String, dynamic> _video(int id) => {
  'id': id,
  'date': 1700000000 + id,
  'content': {
    '@type': 'messageVideo',
    'video': {'id': 700 + id, 'file_name': 'video_$id.mp4'},
  },
};

/// Serves canned TDLib responses and records the `getChatHistory` params.
///
/// Handles the handful of methods the scan path issues: `getChat` (the cached
/// channel-id validation in `findExistingChannel`), `loadChats`/`getChats`
/// (the title search when there's no cached id), and `getChatHistory` (the
/// pagination loop under test).
class _FakeTdRequests {
  _FakeTdRequests(this.nextPages);

  /// Returns [page] on every history call — used to exercise a stalled cursor.
  _FakeTdRequests.repeating(Map<String, dynamic> page)
    : nextPages = [],
      _repeating = page;

  /// Throws [error] on every history call until [nextPages] is reassigned.
  _FakeTdRequests.throwing(Object error)
    : nextPages = [],
      _historyError = error;

  List<Map<String, dynamic>> nextPages;
  Map<String, dynamic>? _repeating;
  Object? _historyError;

  /// When set, `getChats` throws this — the channel lookup can't complete.
  Object? chatListError;

  /// Chat ids returned by `getChats`. Empty means a definitive "no channel".
  List<int> chatIds = const [];

  /// The `params` map of every `getChatHistory` request, in order.
  final calls = <Map<String, dynamic>>[];

  Future<Map<String, dynamic>> send({
    required String method,
    Map<String, dynamic>? params,
  }) async {
    switch (method) {
      case 'getChat':
        final id = params?['chat_id'];
        // The cached id resolves; anything else looks deleted.
        if (id == _channelId) return {'id': _channelId, 'title': 'LumoVault'};
        return {'@type': 'error', 'message': 'chat not found'};

      case 'loadChats':
        return const {'@type': 'ok'};

      case 'getChats':
        final error = chatListError;
        if (error != null) throw error;
        return {'chat_ids': chatIds};

      case 'getChatHistory':
        return _history(params);

      default:
        return const {'@type': 'ok'};
    }
  }

  Map<String, dynamic> _history(Map<String, dynamic>? params) {
    calls.add(Map<String, dynamic>.of(params ?? const {}));

    final error = _historyError;
    if (error != null) {
      // Cleared once nextPages is reassigned, so a retry can succeed.
      if (nextPages.isEmpty) throw error;
      _historyError = null;
    }

    final repeating = _repeating;
    if (repeating != null) return repeating;

    if (nextPages.isEmpty) return {'messages': const <dynamic>[]};
    return nextPages.removeAt(0);
  }
}

/// In-memory [GalleryRepository] with no DAO, so `_persistItem` is a no-op
/// and no drift database is needed.
class _FakeGalleryRepository extends GalleryRepository {
  _FakeGalleryRepository() : super(scannerService: _NoopScanner());
}

class _FakeDownloadService implements DownloadService {
  /// Simulate a thumbnail download that fails outright.
  bool throwOnDownload = false;

  /// The download mode of every attempted call, in order — used to prove
  /// thumbnails are (or aren't) fetched for duplicate items.
  final calls = <DownloadMode>[];

  @override
  Stream<DownloadProgress> get progressStream => const Stream.empty();

  @override
  Future<DownloadResult> downloadFile({
    required String taskId,
    required int messageId,
    required int channelId,
    DownloadMode mode = DownloadMode.original,
  }) async {
    calls.add(mode);
    if (throwOnDownload) throw StateError('download failed');

    // A real thumbnail file: the scanner reads the bytes, caches them, and
    // deletes the temp file, so this must actually exist on disk.
    final file = File(
      '${Directory.systemTemp.path}/lumovault_thumb_$messageId.bin',
    );
    await file.writeAsBytes(utf8.encode('thumb-$messageId'));
    return DownloadResult(taskId: taskId, filePath: file.path);
  }

  @override
  Future<void> cancelDownload(String taskId) async {}
}

class _NoopScanner implements MediaScannerService {
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
