import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/storage/storage_channel_service.dart';
import 'package:lumovault/core/tdlib/tdlib_client.dart';
import 'package:lumovault/core/tdlib/tdlib_exception.dart';
import 'package:lumovault/features/gallery/data/repositories/telegram_download_service.dart';
import 'package:lumovault/features/metadata/data/models/manifest.dart';
import 'package:lumovault/features/restore/data/repositories/restore_repository.dart';
import 'package:lumovault/features/restore/data/models/restore_progress.dart';

void main() {
  group('RestoreRepository', () {
    test(
      'ChannelDetectionResult hasBackup returns true for existing channel',
      () {
        const result = ChannelDetectionResult(
          channelId: 123,
          isNewChannel: false,
        );
        expect(result.hasBackup, isTrue);
        expect(result.hasError, isFalse);
        expect(result.isNew, isFalse);
      },
    );

    test('ChannelDetectionResult hasBackup returns false for new channel', () {
      const result = ChannelDetectionResult(channelId: 123, isNewChannel: true);
      expect(result.hasBackup, isFalse);
      expect(result.isNew, isTrue);
    });

    test('ChannelDetectionResult hasError returns true when error is set', () {
      const result = ChannelDetectionResult(error: 'Failed to connect');
      expect(result.hasError, isTrue);
      expect(result.hasBackup, isFalse);
    });

    test('ChannelMessage captionMetadata parses valid JSON', () {
      const message = ChannelMessage(
        messageId: 1,
        fileId: 100,
        fileName: 'photo.jpg',
        caption: '{"mid":"123","h":"abc123","ct":"2026-01-15T00:00:00Z"}',
      );

      final metadata = message.captionMetadata;
      expect(metadata, isNotNull);
      expect(metadata!.mediaItemId, '123');
      expect(metadata.fileHash, 'abc123');
    });

    test('ChannelMessage captionMetadata returns null for null caption', () {
      const message = ChannelMessage(
        messageId: 1,
        fileId: 100,
        fileName: 'photo.jpg',
        caption: null,
      );
      expect(message.captionMetadata, isNull);
    });

    test('ChannelMessage captionMetadata returns null for empty caption', () {
      const message = ChannelMessage(
        messageId: 1,
        fileId: 100,
        fileName: 'photo.jpg',
        caption: '',
      );
      expect(message.captionMetadata, isNull);
    });

    test('DownloadedFile stores metadata correctly', () {
      const file = DownloadedFile(
        filePath: '/path/to/file.jpg',
        fileName: 'file.jpg',
      );
      expect(file.filePath, '/path/to/file.jpg');
      expect(file.fileName, 'file.jpg');
      expect(file.metadata, isNull);
    });

    test('RestoreError.network creates retryable error', () {
      final error = RestoreError.network(message: 'No connection');
      expect(error.category, RestoreErrorCategory.network);
      expect(error.retryable, isTrue);
      expect(error.message, 'No connection');
    });

    test('RestoreError.channelNotFound creates non-retryable error', () {
      final error = RestoreError.channelNotFound();
      expect(error.category, RestoreErrorCategory.channelNotFound);
      expect(error.retryable, isFalse);
    });

    test('RestoreError.manifestCorrupted creates non-retryable error', () {
      final error = RestoreError.manifestCorrupted();
      expect(error.category, RestoreErrorCategory.manifestCorrupted);
      expect(error.retryable, isFalse);
    });

    test('RestoreError.storageFull creates non-retryable error', () {
      final error = RestoreError.storageFull();
      expect(error.category, RestoreErrorCategory.storageFull);
      expect(error.retryable, isFalse);
    });

    test('RestoreError.authExpired creates non-retryable error', () {
      final error = RestoreError.authExpired();
      expect(error.category, RestoreErrorCategory.authExpired);
      expect(error.retryable, isFalse);
    });

    test('RestoreError.cancelled creates non-retryable error', () {
      final error = RestoreError.cancelled();
      expect(error.category, RestoreErrorCategory.cancelled);
      expect(error.retryable, isFalse);
    });
  });

  group('RestoreRepository.fetchManifest', () {
    test('returns null when the channel has no pinned message', () async {
      final client = _FakeTdLibClient(
        onRequest: (method, params) async => {'message_ids': <int>[]},
      );
      final repo = _buildRepo(client, _FakeDownloadService());

      expect(await repo.fetchManifest(42), isNull);
    });

    test('returns the parsed manifest from the pinned message', () async {
      final manifestJson = Manifest.create(
        deviceHash: 'test_device',
      ).toJsonString();
      final client = _FakeTdLibClient(
        onRequest: (method, params) async {
          if (method == 'getChatPinnedMessages') {
            return {
              'message_ids': [7],
            };
          }
          return {
            'content': {
              '@type': 'messageText',
              'text': {'text': manifestJson},
            },
          };
        },
      );
      final repo = _buildRepo(client, _FakeDownloadService());

      final manifest = await repo.fetchManifest(42);
      expect(manifest, isNotNull);
      expect(manifest!.deviceHash, 'test_device');
    });

    test('propagates transport errors instead of returning null', () async {
      final client = _FakeTdLibClient(
        onRequest: (method, params) async {
          throw const TdLibException(message: 'Network down', code: 'NETWORK');
        },
      );
      final repo = _buildRepo(client, _FakeDownloadService());

      await expectLater(repo.fetchManifest(42), throwsA(isA<TdLibException>()));
    });
  });

  group('RestoreRepository.fetchChannelMessages', () {
    List<Map<String, dynamic>> historyPage(int firstId, int count) => [
      for (var i = 0; i < count; i++) ...[
        {
          'id': firstId + i,
          'date': 1768444800,
          'content': {
            '@type': 'messageDocument',
            'document': {
              'file_name': 'photo_${firstId + i}.jpg',
              // TDLib nests the file object: document.document.id.
              'document': {'id': 1000 + firstId + i},
            },
            'caption': {
              'text': '{"mid":"m${firstId + i}","h":"h${firstId + i}"}',
            },
          },
        },
      ],
    ];

    test('paginates until an empty page', () async {
      final client = _FakeTdLibClient(
        onRequest: (method, params) async {
          final from = params?['from_message_id'] as int? ?? 0;
          if (from == 0) {
            // A full page keeps the loop going; the empty page ends it.
            return {'messages': historyPage(1, 100)};
          }
          return {'messages': <dynamic>[]};
        },
      );
      final repo = _buildRepo(client, _FakeDownloadService());

      final messages = await repo.fetchChannelMessages(42);
      expect(messages, hasLength(100));
      expect(messages.first.fileId, 1001);
      expect(messages.first.caption, contains('"h":"h1"'));
      expect(client.getChatHistoryCalls, 2);
    });

    test('retries a failed page once before propagating the error', () async {
      final client = _FakeTdLibClient(
        onRequest: (method, params) async {
          throw const TdLibException(message: 'Flaky', code: 'NETWORK');
        },
      );
      final repo = _buildRepo(client, _FakeDownloadService());

      await expectLater(
        repo.fetchChannelMessages(42),
        throwsA(isA<TdLibException>()),
      );
      expect(client.getChatHistoryCalls, 2);
    });

    test('recovers from a single transient page failure', () async {
      var calls = 0;
      final client = _FakeTdLibClient(
        onRequest: (method, params) async {
          calls++;
          if (calls == 1) {
            throw const TdLibException(message: 'Flaky', code: 'NETWORK');
          }
          if (calls == 2) return {'messages': historyPage(1, 100)};
          return {'messages': <dynamic>[]};
        },
      );
      final repo = _buildRepo(client, _FakeDownloadService());

      final messages = await repo.fetchChannelMessages(42);
      expect(messages, hasLength(100));
      expect(client.getChatHistoryCalls, 3);
    });

    test('propagates errors instead of returning a truncated list', () async {
      var calls = 0;
      final client = _FakeTdLibClient(
        onRequest: (method, params) async {
          calls++;
          if (calls == 1) return {'messages': historyPage(1, 100)};
          throw const TdLibException(message: 'Dead', code: 'NETWORK');
        },
      );
      final repo = _buildRepo(client, _FakeDownloadService());

      await expectLater(
        repo.fetchChannelMessages(42),
        throwsA(isA<TdLibException>()),
      );
      expect(client.getChatHistoryCalls, 3);
    });
  });

  group('RestoreRepository.downloadFile', () {
    test('returns the downloaded file with its metadata', () async {
      final download = _FakeDownloadService(
        result: const DownloadResult(taskId: 'x', filePath: '/tmp/out.bin'),
      );
      final repo = _buildRepo(_FakeTdLibClient(), download);

      final file = await repo.downloadFile(
        messageId: 5,
        channelId: 42,
        fileName: 'photo.jpg',
      );
      expect(file.filePath, '/tmp/out.bin');
      expect(file.fileName, 'photo.jpg');
    });

    test('propagates download failures instead of returning null', () async {
      final download = _FakeDownloadService(
        error: const TdLibException(message: 'Disk full', code: 'IO'),
      );
      final repo = _buildRepo(_FakeTdLibClient(), download);

      await expectLater(
        repo.downloadFile(messageId: 5, channelId: 42, fileName: 'a.jpg'),
        throwsA(isA<TdLibException>()),
      );
    });

    test(
      'forwards progress for the matching task and ignores others',
      () async {
        final download = _FakeDownloadService(
          result: const DownloadResult(taskId: 'x', filePath: '/tmp/out.bin'),
          progressToEmit: const DownloadProgress(
            taskId: 'ignored',
            progress: 0.5,
            bytesDownloaded: 10,
            totalBytes: 20,
          ),
          foreignProgress: const DownloadProgress(
            taskId: 'other-task',
            progress: 0.9,
            bytesDownloaded: 9,
            totalBytes: 10,
          ),
        );
        final repo = _buildRepo(_FakeTdLibClient(), download);
        final progresses = <double>[];

        final file = await repo.downloadFile(
          messageId: 5,
          channelId: 42,
          fileName: 'a.jpg',
          onProgress: progresses.add,
        );
        expect(file.filePath, '/tmp/out.bin');
        expect(progresses, [0.5]);
      },
    );
  });
}

RestoreRepository _buildRepo(
  _FakeTdLibClient client,
  _FakeDownloadService download,
) {
  return RestoreRepository(
    client: client,
    storageChannelService: StorageChannelService(client: client),
    downloadService: download,
    storageBasePath: '/tmp/restore',
  );
}

/// Scripted TDLib client for restore repository tests.
class _FakeTdLibClient implements TdLibClient {
  _FakeTdLibClient({this.onRequest});

  /// Handler invoked for every request; return the response or throw.
  final Future<Map<String, dynamic>> Function(
    String method,
    Map<String, dynamic>? params,
  )?
  onRequest;

  int getChatHistoryCalls = 0;

  @override
  Stream<Map<String, dynamic>> get updates => const Stream.empty();

  @override
  bool get isInitialized => true;

  @override
  int get clientId => 0;

  @override
  Future<void> initialize({required String databaseKey}) async {}

  @override
  Future<Map<String, dynamic>> sendRequest({
    required String method,
    Map<String, dynamic>? params,
  }) async {
    if (method == 'getChatHistory') getChatHistoryCalls++;
    final handler = onRequest;
    if (handler == null) return {'@type': 'ok'};
    return handler(method, params);
  }


  @override
  Future<bool> isAuthenticated() async => true;

  @override
  Future<Map<String, dynamic>> getAuthorizationState() async {
    return {'@type': 'authorizationStateReady'};
  }

  @override
  Future<void> logOut() async {}

  @override
  Future<void> close() async {}
}

/// Scripted download service for restore repository tests.
class _FakeDownloadService implements DownloadService {
  _FakeDownloadService({
    this.result,
    this.error,
    this.progressToEmit,
    this.foreignProgress,
  });

  DownloadResult? result;
  Object? error;

  /// Emitted during [downloadFile] echoed with the repository's task ID, so
  /// the matching-task progress forwarding path can be exercised.
  DownloadProgress? progressToEmit;

  /// Emitted verbatim with an unrelated task ID — must be filtered out.
  DownloadProgress? foreignProgress;

  // Sync delivery makes progress assertions deterministic: events reach the
  // repository's listener before downloadFile returns.
  final _progressController = StreamController<DownloadProgress>.broadcast(
    sync: true,
  );

  @override
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  @override
  Future<DownloadResult> downloadFile({
    required String taskId,
    required int messageId,
    required int channelId,
    DownloadMode mode = DownloadMode.original,
  }) async {
    if (error != null) throw error!;
    final foreign = foreignProgress;
    if (foreign != null) _progressController.add(foreign);
    final echo = progressToEmit;
    if (echo != null) {
      _progressController.add(
        DownloadProgress(
          taskId: taskId,
          progress: echo.progress,
          bytesDownloaded: echo.bytesDownloaded,
          totalBytes: echo.totalBytes,
        ),
      );
    }
    return result ??
        DownloadResult(taskId: taskId, filePath: '/tmp/downloaded.bin');
  }

  @override
  Future<void> cancelDownload(String taskId) async {}
}
