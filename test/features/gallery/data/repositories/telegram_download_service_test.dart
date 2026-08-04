import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/tdlib/tdlib_client.dart';
import 'package:lumovault/core/tdlib/tdlib_connection_manager.dart';
import 'package:lumovault/features/gallery/data/models/transfer_error.dart';
import 'package:lumovault/features/gallery/data/repositories/telegram_download_service.dart';

void main() {
  group('TelegramDownloadService file extraction', () {
    test('document original mode uses the nested document.file id', () async {
      final td = _FakeTd(_documentMessage(fileId: 42));
      final service = _service(td);

      final download = service.downloadFile(
        taskId: 't1',
        messageId: 100,
        channelId: -100123,
      );
      await pumpEventQueue();
      td.emitDownloaded(fileId: 42, path: '/tmp/photo.jpg');
      final result = await download;

      expect(result.filePath, '/tmp/photo.jpg');
      final call = td.calls.last;
      expect(call.method, 'downloadFile');
      expect(call.params!['file_id'], 42);
      expect(call.params!['priority'], 16);
    });

    test('document thumbnail mode prefers the thumbnail file id', () async {
      final td = _FakeTd(_documentMessage(fileId: 42, thumbnailId: 7));
      final service = _service(td);

      final download = service.downloadFile(
        taskId: 't1',
        messageId: 100,
        channelId: -100123,
        mode: DownloadMode.thumbnail,
      );
      await pumpEventQueue();
      td.emitDownloaded(fileId: 7, path: '/tmp/thumb.jpg');
      final result = await download;

      expect(result.filePath, '/tmp/thumb.jpg');
      final call = td.calls.last;
      expect(call.method, 'downloadFile');
      expect(call.params!['file_id'], 7);
      expect(call.params!['priority'], 1);
    });

    test(
      'document thumbnail mode falls back to the full file without a thumbnail',
      () async {
        final td = _FakeTd(_documentMessage(fileId: 42));
        final service = _service(td);

        final download = service.downloadFile(
          taskId: 't1',
          messageId: 100,
          channelId: -100123,
          mode: DownloadMode.thumbnail,
        );
        await pumpEventQueue();
        td.emitDownloaded(fileId: 42, path: '/tmp/photo.jpg');
        await download;

        expect(td.calls.last.params!['file_id'], 42);
      },
    );

    test('video original mode uses the nested video.file id', () async {
      final td = _FakeTd(_videoMessage(fileId: 99));
      final service = _service(td);

      final download = service.downloadFile(
        taskId: 't1',
        messageId: 100,
        channelId: -100123,
      );
      await pumpEventQueue();
      td.emitDownloaded(fileId: 99, path: '/tmp/video.mp4');
      await download;

      expect(td.calls.last.params!['file_id'], 99);
    });

    test('video thumbnail mode prefers the thumbnail file id', () async {
      final td = _FakeTd(_videoMessage(fileId: 99, thumbnailId: 11));
      final service = _service(td);

      final download = service.downloadFile(
        taskId: 't1',
        messageId: 100,
        channelId: -100123,
        mode: DownloadMode.thumbnail,
      );
      await pumpEventQueue();
      td.emitDownloaded(fileId: 11, path: '/tmp/thumb.jpg');
      await download;

      expect(td.calls.last.params!['file_id'], 11);
    });

    test('photo original mode uses the largest size', () async {
      final td = _FakeTd(_photoMessage(smallId: 1, largeId: 2));
      final service = _service(td);

      final download = service.downloadFile(
        taskId: 't1',
        messageId: 100,
        channelId: -100123,
      );
      await pumpEventQueue();
      td.emitDownloaded(fileId: 2, path: '/tmp/original.jpg');
      await download;

      expect(td.calls.last.params!['file_id'], 2);
    });

    test('photo thumbnail mode uses the smallest size', () async {
      final td = _FakeTd(_photoMessage(smallId: 1, largeId: 2));
      final service = _service(td);

      final download = service.downloadFile(
        taskId: 't1',
        messageId: 100,
        channelId: -100123,
        mode: DownloadMode.thumbnail,
      );
      await pumpEventQueue();
      td.emitDownloaded(fileId: 1, path: '/tmp/thumb.jpg');
      await download;

      expect(td.calls.last.params!['file_id'], 1);
    });

    test(
      'an already-downloaded file is returned without a new request',
      () async {
        final dir = await Directory.systemTemp.createTemp('tg_dl_test');
        addTearDown(() => dir.delete(recursive: true));
        final existing = File('${dir.path}/photo.jpg');
        await existing.writeAsBytes([1, 2, 3]);

        final td = _FakeTd(
          _documentMessage(fileId: 42, localPath: existing.path),
        );
        final service = _service(td);

        final result = await service.downloadFile(
          taskId: 't1',
          messageId: 100,
          channelId: -100123,
        );

        expect(result.filePath, existing.path);
        expect(td.calls.where((c) => c.method == 'downloadFile'), isEmpty);
      },
    );

    test('a message with no usable file throws fileNotFound', () async {
      final td = _FakeTd(_textMessage());
      final service = _service(td);

      final download = service.downloadFile(
        taskId: 't1',
        messageId: 100,
        channelId: -100123,
      );

      await expectLater(
        download,
        throwsA(
          isA<TransferError>().having(
            (e) => e.category,
            'category',
            TransferErrorCategory.fileNotFound,
          ),
        ),
      );
    });
  });

  group('TelegramDownloadService progress', () {
    test('emits progress updates as the file downloads', () async {
      final td = _FakeTd(_documentMessage(fileId: 42));
      final service = _service(td);
      final progress = <double>[];
      final sub = service.progressStream.listen((p) {
        progress.add(p.progress);
      });
      addTearDown(sub.cancel);

      final download = service.downloadFile(
        taskId: 't1',
        messageId: 100,
        channelId: -100123,
      );
      await pumpEventQueue();

      td.emitPartial(fileId: 42, downloaded: 50, expected: 100);
      td.emitDownloaded(fileId: 42, path: '/tmp/photo.jpg');
      await download;

      expect(progress, containsAllInOrder([0.5, 1.0]));
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

TelegramDownloadService _service(_FakeTd td) => TelegramDownloadService(
  // Inert: both collaborators the service actually uses are overridden
  // below, so no request ever reaches this manager or its client.
  manager: TdLibConnectionManager(client: TdLibClient.instance),
  requestSender: td.send,
  updates: td.updates,
);

/// `getMessage` response with a document content, shaped like real TDLib:
/// the `file` object is nested at `document.document`, with the thumbnail
/// (also a `file`) at `document.thumbnail.file`.
Map<String, dynamic> _documentMessage({
  required int fileId,
  int? thumbnailId,
  String? localPath,
}) => {
  'id': 100,
  'content': {
    '@type': 'messageDocument',
    'document': {
      'file_name': 'photo.jpg',
      if (thumbnailId != null)
        'thumbnail': {
          'file': {
            'id': thumbnailId,
            'local': {'path': ''},
          },
        },
      'document': {
        'id': fileId,
        'local': {'path': localPath ?? ''},
      },
    },
  },
};

Map<String, dynamic> _videoMessage({required int fileId, int? thumbnailId}) => {
  'id': 100,
  'content': {
    '@type': 'messageVideo',
    'video': {
      'file_name': 'video.mp4',
      if (thumbnailId != null)
        'thumbnail': {
          'file': {
            'id': thumbnailId,
            'local': {'path': ''},
          },
        },
      'video': {
        'id': fileId,
        'local': {'path': ''},
      },
    },
  },
};

Map<String, dynamic> _photoMessage({
  required int smallId,
  required int largeId,
}) => {
  'id': 100,
  'content': {
    '@type': 'messagePhoto',
    'photo': {
      'sizes': [
        {
          'photo': {
            'id': smallId,
            'local': {'path': ''},
          },
        },
        {
          'photo': {
            'id': largeId,
            'local': {'path': ''},
          },
        },
      ],
    },
  },
};

Map<String, dynamic> _textMessage() => {
  'id': 100,
  'content': {
    '@type': 'messageText',
    'text': {'text': 'hello'},
  },
};

/// Drives the service's two collaborators: canned `getMessage` responses and
/// a hand-fed TDLib update stream.
class _FakeTd {
  _FakeTd(this.messageResponse);

  final Map<String, dynamic> messageResponse;

  final calls = <_TdCall>[];
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get updates => _controller.stream;

  Future<Map<String, dynamic>> send({
    required String method,
    Map<String, dynamic>? params,
  }) async {
    calls.add(_TdCall(method, params));
    if (method == 'getMessage') return messageResponse;
    return const {};
  }

  void emitPartial({
    required int fileId,
    required int downloaded,
    required int expected,
  }) {
    _controller.add({
      '@type': 'updateFile',
      'file': {
        'id': fileId,
        'expected_size': expected,
        'local': {
          'path': '',
          'downloaded_size': downloaded,
          'is_downloading_completed': false,
        },
      },
    });
  }

  void emitDownloaded({required int fileId, required String path}) {
    _controller.add({
      '@type': 'updateFile',
      'file': {
        'id': fileId,
        'expected_size': 100,
        'local': {
          'path': path,
          'downloaded_size': 100,
          'is_downloading_completed': true,
        },
      },
    });
  }
}

class _TdCall {
  _TdCall(this.method, this.params);
  final String method;
  final Map<String, dynamic>? params;
}
