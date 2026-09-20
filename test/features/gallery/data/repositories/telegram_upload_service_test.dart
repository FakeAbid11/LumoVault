import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/tdlib/tdlib_client.dart';
import 'package:lumovault/core/tdlib/tdlib_connection_manager.dart';
import 'package:lumovault/core/tdlib/tdlib_exception.dart';
import 'package:lumovault/features/gallery/data/models/caption_metadata.dart';
import 'package:lumovault/features/gallery/data/models/transfer_error.dart';
import 'package:lumovault/features/gallery/data/models/upload_task.dart';
import 'package:lumovault/features/gallery/data/repositories/telegram_upload_service.dart';

/// Behavioural coverage for [TelegramUploadService] — the TDLib upload path.
///
/// `sendMessage` returns a *provisional* message with a temporary id; the real
/// transfer completes asynchronously via `updateMessageSendSucceeded` /
/// `updateMessageSendFailed`, with `updateFile` events carrying progress. That
/// correlation is the whole substance of this class and had no tests: an
/// earlier version awaited a completer nothing ever completed (hanging
/// forever) and listened for a non-existent `updateFileProgress` type (so
/// progress never left 0%). These tests drive the update stream directly.
///
/// Neither [TdLibConnectionManager] nor [TdLibClient] can be constructed in a
/// test, so the service takes an injectable request sender and update stream.
void main() {
  late Directory tempDir;
  late File file;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('lumovault_upload_test');
    // uploadFile stats the path before doing anything else, so the happy-path
    // tests need a file that genuinely exists.
    file = File('${tempDir.path}/photo.jpg')
      ..writeAsBytesSync(List<int>.filled(64, 7));
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('TelegramUploadService success path', () {
    test(
      'resolves with the permanent message id, not the temporary one',
      () async {
        final td = _FakeTd(sendResult: _sendResult(temporaryId: 5, fileId: 42));
        final service = _service(td);
        addTearDown(service.dispose);

        final upload = service.uploadFile(
          task: _task(file.path),
          channelId: -100123,
        );

        // The provisional id (5) must not be what the caller gets back: it is
        // replaced server-side and would not resolve later.
        await td.emitSendSucceeded(oldMessageId: 5, newMessageId: 9001);

        final result = await upload;
        expect(result.messageId, 9001);
        expect(result.fileId, 42);
      },
    );

    test('updateFile events become progress, ending at 1.0', () async {
      final td = _FakeTd(sendResult: _sendResult(temporaryId: 5, fileId: 42));
      final service = _service(td);
      addTearDown(service.dispose);

      final seen = <double>[];
      final sub = service.progressStream.listen((p) => seen.add(p.progress));
      addTearDown(sub.cancel);

      final upload = service.uploadFile(
        task: _task(file.path, fileSize: 100),
        channelId: -100123,
      );

      await td.emitFileProgress(fileId: 42, uploadedSize: 25);
      await td.emitFileProgress(fileId: 42, uploadedSize: 100);
      await td.emitSendSucceeded(oldMessageId: 5, newMessageId: 9001);
      await upload;
      await pumpEventQueue();

      // 0.25, 1.0 from updateFile, then the synthetic 1.0 on success so the
      // UI settles on complete rather than stalling just short of it.
      expect(seen, [0.25, 1.0, 1.0]);
    });

    test('progress for an unrelated file id is ignored', () async {
      final td = _FakeTd(sendResult: _sendResult(temporaryId: 5, fileId: 42));
      final service = _service(td);
      addTearDown(service.dispose);

      final seen = <double>[];
      final sub = service.progressStream.listen((p) => seen.add(p.progress));
      addTearDown(sub.cancel);

      final upload = service.uploadFile(
        task: _task(file.path, fileSize: 100),
        channelId: -100123,
      );

      // A concurrent download or another upload's file.
      await td.emitFileProgress(fileId: 999, uploadedSize: 50);
      await td.emitSendSucceeded(oldMessageId: 5, newMessageId: 9001);
      await upload;
      await pumpEventQueue();

      // Only the terminal 1.0 — nothing from the foreign file.
      expect(seen, [1.0]);
    });

    test('a send result for a different message is ignored', () async {
      final td = _FakeTd(sendResult: _sendResult(temporaryId: 5, fileId: 42));
      final service = _service(td);
      addTearDown(service.dispose);

      final upload = service.uploadFile(
        task: _task(file.path),
        channelId: -100123,
      );

      // Another upload finishing must not complete this one.
      await td.emitSendSucceeded(oldMessageId: 77, newMessageId: 8888);
      var done = false;
      unawaited(upload.then((_) => done = true));
      await pumpEventQueue();
      expect(done, isFalse);

      await td.emitSendSucceeded(oldMessageId: 5, newMessageId: 9001);
      expect((await upload).messageId, 9001);
    });
  });

  group('TelegramUploadService captions', () {
    test('a caption carries the task metadata', () async {
      final td = _FakeTd(sendResult: _sendResult(temporaryId: 5, fileId: 42));
      final service = _service(td);
      addTearDown(service.dispose);

      final task = _task(
        file.path,
        mediaCreatedAt: DateTime.utc(2024, 3, 1),
        mediaModifiedAt: DateTime.utc(2024, 3, 2),
      );
      final upload = service.uploadFile(task: task, channelId: -100123);
      await td.emitSendSucceeded(oldMessageId: 5, newMessageId: 9001);
      await upload;

      final content =
          td.lastParams!['input_message_content'] as Map<String, dynamic>;
      final caption = content['caption'] as Map<String, dynamic>;
      final parsed = CaptionMetadata.fromCaptionString(
        caption['text'] as String,
      );

      expect(parsed.fileHash, task.fileHash);
      expect(parsed.mediaItemId, task.mediaItemId);
      // Capture time comes from the asset, not from upload time.
      expect(parsed.createdAt, DateTime.utc(2024, 3, 1));
      expect(parsed.modifiedAt, DateTime.utc(2024, 3, 2));
    });

    test('includeCaption: false sends no caption at all', () async {
      // Manifest and partition payloads must arrive caption-less, or the
      // restore flow treats them as media and tries to rebuild items from them.
      final td = _FakeTd(sendResult: _sendResult(temporaryId: 5, fileId: 42));
      final service = _service(td);
      addTearDown(service.dispose);

      final upload = service.uploadFile(
        task: _task(file.path),
        channelId: -100123,
        includeCaption: false,
      );
      await td.emitSendSucceeded(oldMessageId: 5, newMessageId: 9001);
      await upload;

      final content =
          td.lastParams!['input_message_content'] as Map<String, dynamic>;
      expect(content.containsKey('caption'), isFalse);
    });

    test('the file is sent as a document, never recompressed', () async {
      // Original quality is the product's entire premise: inputMessagePhoto
      // would let Telegram re-encode.
      final td = _FakeTd(sendResult: _sendResult(temporaryId: 5, fileId: 42));
      final service = _service(td);
      addTearDown(service.dispose);

      final upload = service.uploadFile(
        task: _task(file.path),
        channelId: -100123,
      );
      await td.emitSendSucceeded(oldMessageId: 5, newMessageId: 9001);
      await upload;

      final content =
          td.lastParams!['input_message_content'] as Map<String, dynamic>;
      expect(content['@type'], 'inputMessageDocument');
      expect(td.lastParams!['chat_id'], -100123);
      final document = content['document'] as Map<String, dynamic>;
      expect(document['path'], file.path);
    });
  });

  group('TelegramUploadService failure paths', () {
    test('a missing local file fails fast as fileNotFound', () async {
      final td = _FakeTd(sendResult: _sendResult(temporaryId: 5, fileId: 42));
      final service = _service(td);
      addTearDown(service.dispose);

      await expectLater(
        service.uploadFile(
          task: _task('${tempDir.path}/gone.jpg'),
          channelId: -100123,
        ),
        throwsA(
          isA<TransferError>().having(
            (e) => e.category,
            'category',
            TransferErrorCategory.fileNotFound,
          ),
        ),
      );

      // No request should have been issued for a file that isn't there.
      expect(td.lastParams, isNull);
    });

    test('a TdLibException becomes a TransferError', () async {
      final td = _FakeTd.throwing(
        const TdLibException(message: 'flood', code: 'FLOOD_WAIT_30'),
      );
      final service = _service(td);
      addTearDown(service.dispose);

      await expectLater(
        service.uploadFile(task: _task(file.path), channelId: -100123),
        throwsA(isA<TransferError>()),
      );
    });

    test('updateMessageSendFailed surfaces as a TransferError', () async {
      final td = _FakeTd(sendResult: _sendResult(temporaryId: 5, fileId: 42));
      final service = _service(td);
      addTearDown(service.dispose);

      final upload = service.uploadFile(
        task: _task(file.path),
        channelId: -100123,
      );
      final matcher = expectLater(upload, throwsA(isA<TransferError>()));
      await td.emitSendFailed(oldMessageId: 5, code: '420', message: 'flood');
      await matcher;
    });

    test('cancelUpload unblocks the pending upload', () async {
      final td = _FakeTd(sendResult: _sendResult(temporaryId: 5, fileId: 42));
      final service = _service(td);
      addTearDown(service.dispose);

      final task = _task(file.path);
      final upload = service.uploadFile(task: task, channelId: -100123);
      final matcher = expectLater(
        upload,
        throwsA(
          isA<TransferError>().having(
            (e) => e.message,
            'message',
            contains('cancelled'),
          ),
        ),
      );

      // Let uploadFile register the task before cancelling it.
      await pumpEventQueue();
      await service.cancelUpload(task.id);
      await matcher;
    });

    test('dispose unblocks an in-flight upload instead of hanging', () async {
      // Without this, an upload in flight when the owning provider is torn
      // down sits on its completer for the full 30-minute timeout, holding the
      // updates subscription and the queue slot with it.
      final td = _FakeTd(sendResult: _sendResult(temporaryId: 5, fileId: 42));
      final service = _service(td);

      final upload = service.uploadFile(
        task: _task(file.path),
        channelId: -100123,
      );
      final matcher = expectLater(upload, throwsA(isA<TransferError>()));

      await pumpEventQueue();
      service.dispose();
      await matcher;
    });

    test(
      'progress after dispose does not throw on the closed stream',
      () async {
        final td = _FakeTd(sendResult: _sendResult(temporaryId: 5, fileId: 42));
        final service = _service(td);

        final upload = service.uploadFile(
          task: _task(file.path, fileSize: 100),
          channelId: -100123,
        );
        // dispose() below rejects this; the rejection isn't what's under test,
        // but leaving it unhandled would fail the test as an async error.
        _swallow(upload);

        await pumpEventQueue();
        service.dispose();

        // A TDLib update can land after teardown; adding to a closed controller
        // would throw inside the updates listener where nothing catches it.
        await expectLater(
          td.emitFileProgress(fileId: 42, uploadedSize: 50),
          completes,
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Attach a no-op error handler so an expected rejection doesn't surface as an
/// unhandled async error and fail the test.
void _swallow(Future<Object?> future) {
  unawaited(future.then((_) {}, onError: (Object _) {}));
}

TelegramUploadService _service(_FakeTd td) => TelegramUploadService(
  // Inert: both collaborators the service actually uses are overridden
  // below, so no request ever reaches this manager or its client.
  manager: TdLibConnectionManager(client: TdLibClient.instance),
  requestSender: td.send,
  updates: td.updates,
);

/// `sendMessage`'s provisional response: a temporary message id plus the file
/// id that subsequent `updateFile` events will reference.
Map<String, dynamic> _sendResult({
  required int temporaryId,
  required int fileId,
}) => {
  'id': temporaryId,
  'content': {
    'document': {
      'document': {'id': fileId},
    },
  },
};

UploadTask _task(
  String path, {
  int fileSize = 64,
  DateTime? mediaCreatedAt,
  DateTime? mediaModifiedAt,
}) => UploadTask(
  id: 'task_1',
  mediaItemId: 'media_1',
  localFilePath: path,
  fileName: 'photo.jpg',
  fileSize: fileSize,
  fileHash: 'abc123',
  createdAt: DateTime.utc(2024, 1, 1),
  mediaCreatedAt: mediaCreatedAt,
  mediaModifiedAt: mediaModifiedAt,
);

/// Drives the service's two collaborators: canned `sendMessage` responses and
/// a hand-fed TDLib update stream.
class _FakeTd {
  _FakeTd({required Map<String, dynamic> sendResult})
    : _sendResult = sendResult; // ignore: prefer_initializing_formals

  /// Throws [error] from `sendMessage` instead of responding.
  _FakeTd.throwing(Object error) : _sendResult = const {}, _error = error;

  final Map<String, dynamic> _sendResult;
  Object? _error;

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get updates => _controller.stream;

  /// The `params` of the most recent request, for asserting on the payload.
  Map<String, dynamic>? lastParams;

  Future<Map<String, dynamic>> send({
    required String method,
    Map<String, dynamic>? params,
  }) async {
    lastParams = params;
    final error = _error;
    if (error != null) throw error;
    return _sendResult;
  }

  /// Emit an update and let the service's listener run before returning.
  ///
  /// Waits for a subscriber first. `uploadFile` stats the file and awaits
  /// `sendMessage` before it subscribes, and a broadcast stream drops anything
  /// emitted while nobody is listening — an update sent too early would vanish
  /// and leave the upload waiting out its full 30-minute timeout. Bounded so a
  /// service that never subscribes fails the assertion rather than hanging.
  Future<void> _emit(Map<String, dynamic> update) async {
    for (var i = 0; i < 50 && !_controller.hasListener; i++) {
      await pumpEventQueue();
    }
    _controller.add(update);
    await pumpEventQueue();
  }

  Future<void> emitFileProgress({
    required int fileId,
    required int uploadedSize,
  }) => _emit({
    '@type': 'updateFile',
    'file': {
      'id': fileId,
      'remote': {'uploaded_size': uploadedSize},
    },
  });

  Future<void> emitSendSucceeded({
    required int oldMessageId,
    required int newMessageId,
  }) => _emit({
    '@type': 'updateMessageSendSucceeded',
    'old_message_id': oldMessageId,
    'message': {'id': newMessageId},
  });

  Future<void> emitSendFailed({
    required int oldMessageId,
    required String code,
    required String message,
  }) => _emit({
    '@type': 'updateMessageSendFailed',
    'old_message_id': oldMessageId,
    'error': {'code': code, 'message': message},
  });
}
