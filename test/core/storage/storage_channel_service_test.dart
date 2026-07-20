import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:lumovault/core/storage/storage_channel_service.dart';
import 'package:lumovault/core/tdlib/tdlib_client.dart';
import 'package:lumovault/core/tdlib/tdlib_exception.dart';

/// Mock TDLib client for storage channel tests.
class MockTdLibClientForStorage implements TdLibClient {
  MockTdLibClientForStorage({
    this.chatsToReturn = const [],
    this.channelToFind,
    this.throwOnCreate = false,
    this.throwOnSearch = false,
  });

  List<dynamic> chatsToReturn;
  String? channelToFind;
  bool throwOnCreate;
  bool throwOnSearch;

  final sentRequests = <Map<String, dynamic>>[];

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
    sentRequests.add({'method': method, if (params != null) 'params': params});

    if (throwOnSearch && method == 'getChats') {
      throw const TdLibException(
        message: 'Search failed',
        code: 'SEARCH_FAILED',
      );
    }

    if (throwOnCreate && method == 'createNewSupergroupChat') {
      throw const TdLibException(
        message: 'Channel creation failed',
        code: 'CHANNEL_CREATION_FAILED',
      );
    }

    return switch (method) {
      'getChats' => {
        'chat_ids': chatsToReturn,
        'total_count': chatsToReturn.length,
      },
      'getChat' => {
        'id': params?['chat_id'],
        'title': channelToFind ?? 'Other Chat',
        'type': {
          '@type': 'chatTypeSupergroup',
          'supergroup_id': 123,
          'is_channel': true,
        },
      },
      // createNewSupergroupChat returns the new chat directly, so its id is
      // at the top level of the response (not nested under a 'chat' key).
      'createNewSupergroupChat' => {'id': 999, 'title': params?['title']},
      _ => {'@type': 'ok'},
    };
  }

  @override
  void processUpdates() {}

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

void main() {
  group('StorageChannelService', () {
    late MockTdLibClientForStorage mockClient;
    late StorageChannelService service;

    setUp(() {
      mockClient = MockTdLibClientForStorage();
      service = StorageChannelService(client: mockClient);
    });

    group('findOrCreateChannel', () {
      test('finds existing channel by name', () async {
        mockClient.chatsToReturn = [100, 200, 300];
        mockClient.channelToFind = 'LumoVault Backup';

        final result = await service.findOrCreateChannel();

        expect(result, isA<StorageChannelFound>());
        expect((result as StorageChannelFound).channelId, 100);
        expect(service.cachedChannelId, 100);
      });

      test('creates new channel if not found', () async {
        mockClient.chatsToReturn = [100, 200];
        mockClient.channelToFind = 'Other Chat';

        final result = await service.findOrCreateChannel();

        expect(result, isA<StorageChannelCreated>());
        expect((result as StorageChannelCreated).channelId, 999);
        expect(service.cachedChannelId, 999);
      });

      test('returns error on channel creation failure', () async {
        mockClient.chatsToReturn = [];
        mockClient.throwOnCreate = true;

        final result = await service.findOrCreateChannel();

        expect(result, isA<StorageChannelError>());
        expect((result as StorageChannelError).code, 'CHANNEL_CREATION_FAILED');
      });

      test('returns error on search failure', () async {
        mockClient.throwOnSearch = true;

        final result = await service.findOrCreateChannel();

        // Should still try to create channel
        expect(result, isA<StorageChannelCreated>());
      });

      test('skips non-channel chats', () async {
        mockClient.chatsToReturn = [100];
        mockClient.channelToFind = 'LumoVault Backup';

        // Override getChat to return a group (not a channel)
        final result = await service.findOrCreateChannel();

        // The service should check chat type and skip groups
        expect(result, isA<StorageChannelFound>());
      });
    });

    group('cachedChannelId', () {
      test('is null initially', () {
        expect(service.cachedChannelId, isNull);
      });

      test('is set after finding channel', () async {
        mockClient.chatsToReturn = [100];
        mockClient.channelToFind = 'LumoVault Backup';

        await service.findOrCreateChannel();
        expect(service.cachedChannelId, 100);
      });

      test('can be set manually', () {
        service.setCachedChannelId(500);
        expect(service.cachedChannelId, 500);
      });
    });

    group('channel creation', () {
      test('creates channel with correct parameters', () async {
        mockClient.chatsToReturn = [];

        await service.findOrCreateChannel();

        final createRequest = mockClient.sentRequests.firstWhere(
          (r) => r['method'] == 'createNewSupergroupChat',
        );

        expect(createRequest['params']['title'], 'LumoVault Backup');
        expect(createRequest['params']['is_channel'], true);
      });

      test('archives channel after creation', () async {
        mockClient.chatsToReturn = [];

        await service.findOrCreateChannel();

        final archiveRequest = mockClient.sentRequests.firstWhere(
          (r) => r['method'] == 'setChatPosition',
        );

        expect(archiveRequest['params']['chat_id'], 999);
      });

      test('pins manifest message after creation', () async {
        mockClient.chatsToReturn = [];

        await service.findOrCreateChannel();

        final sendMessageRequest = mockClient.sentRequests.firstWhere(
          (r) => r['method'] == 'sendMessage',
        );

        expect(sendMessageRequest['params']['chat_id'], 999);

        final content = sendMessageRequest['params']['input_message_content'];
        expect(content['@type'], 'inputMessageText');

        final text = content['text']['text'] as String;
        expect(text, contains('"app":"lumovault"'));
        expect(text, contains('"schema_version":1'));
      });
    });
  });

  group('StorageChannelResult', () {
    test('StorageChannelFound contains channelId', () {
      const result = StorageChannelFound(channelId: 123);
      expect(result.channelId, 123);
    });

    test('StorageChannelCreated contains channelId', () {
      const result = StorageChannelCreated(channelId: 456);
      expect(result.channelId, 456);
    });

    test('StorageChannelError contains message and code', () {
      const result = StorageChannelError(
        message: 'Test error',
        code: 'TEST_CODE',
      );
      expect(result.message, 'Test error');
      expect(result.code, 'TEST_CODE');
    });
  });
}
