import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/upload_task.dart';
import 'package:lumovault/features/gallery/data/repositories/telegram_upload_service.dart';
import 'package:lumovault/features/metadata/data/repositories/telegram_metadata_uploader.dart';

class _RecordedUpload {
  _RecordedUpload(
    this.task,
    this.channelId,
    this.includeCaption,
    this.fileContent,
  );
  final UploadTask task;
  final int channelId;
  final bool includeCaption;
  final String fileContent;
}

class _FakeUploadService implements UploadService {
  final List<_RecordedUpload> uploaded = [];

  @override
  Stream<UploadProgress> get progressStream =>
      const Stream<UploadProgress>.empty();

  @override
  Future<UploadResult> uploadFile({
    required UploadTask task,
    required int channelId,
    bool includeCaption = true,
  }) async {
    // Read the payload while it still exists (the uploader deletes the temp
    // file as soon as this returns).
    final content = await File(task.localFilePath).readAsString();
    uploaded.add(_RecordedUpload(task, channelId, includeCaption, content));
    return UploadResult(taskId: task.id, messageId: 42, fileId: 7);
  }

  @override
  Future<void> cancelUpload(String taskId) async {}

  @override
  void dispose() {}
}

void main() {
  late Directory tempDir;
  late _FakeUploadService uploadService;
  late TelegramMetadataUploader uploader;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('lumovault_meta_test');
    uploadService = _FakeUploadService();
    uploader = TelegramMetadataUploader(
      uploadService: uploadService,
      channelIdProvider: () async => 123,
      tempDirProvider: () async => tempDir,
      deviceHashProvider: () async => 'device-hash-1',
    );
  });

  tearDown(() {
    uploadService.dispose();
    tempDir.deleteSync(recursive: true);
  });

  test('uploadPartition uploads the JSON as a caption-less document', () async {
    const data = '{"id":"2026/01","items":[]}';

    await uploader.uploadPartition('2026/01', data);

    expect(uploadService.uploaded, hasLength(1));
    final record = uploadService.uploaded.single;
    expect(record.channelId, 123);
    // Metadata payloads must arrive caption-less so the restore flow keeps
    // skipping them when it rebuilds the library from media captions.
    expect(record.includeCaption, isFalse);
    expect(record.task.fileName, 'metadata/2026-01.json');
    final bytes = utf8.encode(data);
    expect(record.task.fileSize, bytes.length);
    expect(record.task.fileHash, sha256.convert(bytes).toString());
    expect(record.fileContent, data);
  });

  test('uploadManifest uploads under the manifest file name', () async {
    await uploader.uploadManifest('{"app":"lumovault"}');

    expect(uploadService.uploaded, hasLength(1));
    expect(
      uploadService.uploaded.single.task.fileName,
      'metadata/manifest.json',
    );
    expect(uploadService.uploaded.single.includeCaption, isFalse);
  });

  test('temp files are cleaned up after upload', () async {
    await uploader.uploadPartition('2026/01', '{}');
    await uploader.uploadManifest('{}');

    final leftovers = tempDir.listSync(recursive: true);
    expect(leftovers, isEmpty);
  });

  test('deviceHash delegates to the injected provider', () async {
    expect(await uploader.deviceHash(), 'device-hash-1');
  });

  test('a failed upload still cleans up the temp file', () async {
    final failing = _FailingUploadService();
    final failingUploader = TelegramMetadataUploader(
      uploadService: failing,
      channelIdProvider: () async => 123,
      tempDirProvider: () async => tempDir,
    );

    await expectLater(
      failingUploader.uploadPartition('2026/01', '{}'),
      throwsA(isA<StateError>()),
    );
    expect(tempDir.listSync(recursive: true), isEmpty);
    failing.dispose();
  });
}

class _FailingUploadService implements UploadService {
  @override
  Stream<UploadProgress> get progressStream =>
      const Stream<UploadProgress>.empty();

  @override
  Future<UploadResult> uploadFile({
    required UploadTask task,
    required int channelId,
    bool includeCaption = true,
  }) async {
    throw StateError('upload failed');
  }

  @override
  Future<void> cancelUpload(String taskId) async {}

  @override
  void dispose() {}
}
