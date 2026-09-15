import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/upload_task.dart';
import 'package:lumovault/features/gallery/data/repositories/telegram_upload_service.dart';
import 'package:lumovault/features/metadata/data/repositories/channel_update_listener.dart';
import 'package:lumovault/features/metadata/data/repositories/conflict_resolver.dart';
import 'package:lumovault/features/metadata/data/repositories/manifest_service.dart';
import 'package:lumovault/features/metadata/data/repositories/metadata_repository.dart';
import 'package:lumovault/features/metadata/data/repositories/metadata_sync_coordinator.dart';
import 'package:lumovault/features/metadata/data/repositories/partition_service.dart';
import 'package:lumovault/features/metadata/data/repositories/search_index_service.dart';
import 'package:lumovault/features/metadata/data/repositories/sync_service.dart';
import 'package:lumovault/features/metadata/data/repositories/telegram_metadata_uploader.dart';

/// A coordinator that records how many times [pullNow] fired, so the listener's
/// "fire a debounced pull on a relevant channel update" contract can be
/// asserted without any TDLib download stack behind it.
class _SpyCoordinator extends MetadataSyncCoordinator {
  _SpyCoordinator({required super.metadataRepository, required super.uploader});

  int pullCount = 0;

  @override
  Future<int> pullNow() async {
    pullCount++;
    return 0;
  }
}

class _FakeUploadService implements UploadService {
  @override
  Stream<UploadProgress> get progressStream =>
      const Stream<UploadProgress>.empty();

  @override
  Future<UploadResult> uploadFile({
    required UploadTask task,
    required int channelId,
    bool includeCaption = true,
  }) async => UploadResult(taskId: task.id, messageId: 42, fileId: 7);

  @override
  Future<void> cancelUpload(String taskId) async {}

  @override
  void dispose() {}
}

void main() {
  group('ChannelUpdateListener', () {
    const chatId = 1000;
    const debounce = Duration(milliseconds: 40);
    // A little longer than the debounce so the timer has certainly fired.
    const afterDebounce = Duration(milliseconds: 120);

    late StreamController<Map<String, dynamic>> updates;
    late MetadataRepository repository;
    late ManifestService manifestService;
    late PartitionService partitionService;
    late SearchIndexService searchIndexService;
    late SyncService syncService;
    late _FakeUploadService uploadService;
    late TelegramMetadataUploader uploader;
    late _SpyCoordinator coordinator;
    late ChannelUpdateListener listener;
    late Directory tempDir;

    setUp(() {
      updates = StreamController<Map<String, dynamic>>.broadcast();
      tempDir = Directory.systemTemp.createTempSync('lumovault_listener_test');
      manifestService = ManifestService();
      partitionService = PartitionService();
      searchIndexService = SearchIndexService();
      syncService = SyncService();
      repository = MetadataRepository(
        manifestService: manifestService,
        partitionService: partitionService,
        searchIndexService: searchIndexService,
        syncService: syncService,
        conflictResolver: ConflictResolver(),
      );
      uploadService = _FakeUploadService();
      uploader = TelegramMetadataUploader(
        uploadService: uploadService,
        channelIdProvider: () async => chatId,
        tempDirProvider: () async => tempDir,
        deviceHashProvider: () async => 'device',
      );
      coordinator = _SpyCoordinator(
        metadataRepository: repository,
        uploader: uploader,
      );
      listener = ChannelUpdateListener(
        updates: updates.stream,
        coordinator: coordinator,
        uploader: uploader,
        chatIdProvider: () async => chatId,
        debounce: debounce,
      );
      listener.start();
    });

    tearDown(() async {
      listener.dispose();
      await updates.close();
      coordinator.dispose();
      repository.dispose();
      manifestService.dispose();
      partitionService.dispose();
      searchIndexService.dispose();
      syncService.dispose();
      uploadService.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('a delete on the storage channel triggers a debounced pull', () async {
      updates.add({
        '@type': 'updateDeleteMessages',
        'chat_id': chatId,
        'message_ids': [5],
      });

      await Future<void>.delayed(afterDebounce);
      expect(coordinator.pullCount, 1);
    });

    test('a burst of updates coalesces into a single pull', () async {
      for (var i = 0; i < 5; i++) {
        updates.add({
          '@type': 'updateNewMessage',
          'message': {'chat_id': chatId, 'id': 100 + i},
        });
      }

      await Future<void>.delayed(afterDebounce);
      expect(coordinator.pullCount, 1);
    });

    test('an update for a different chat is ignored', () async {
      updates.add({
        '@type': 'updateDeleteMessages',
        'chat_id': 9999,
        'message_ids': [5],
      });

      await Future<void>.delayed(afterDebounce);
      expect(coordinator.pullCount, 0);
    });

    test('an irrelevant update type is ignored', () async {
      updates.add({'@type': 'updateChatTitle', 'chat_id': chatId});

      await Future<void>.delayed(afterDebounce);
      expect(coordinator.pullCount, 0);
    });

    test('the echo of our own upload is ignored', () async {
      // Perform an upload so the uploader records message id 42 as recently
      // sent; the fake upload service returns that id.
      await uploader.uploadManifest('{}');

      updates.add({
        '@type': 'updateNewMessage',
        'message': {'chat_id': chatId, 'id': 42},
      });

      await Future<void>.delayed(afterDebounce);
      expect(coordinator.pullCount, 0);
    });
  });
}
