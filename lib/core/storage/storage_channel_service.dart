import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../tdlib/tdlib_client.dart';
import '../tdlib/tdlib_config.dart';
import '../tdlib/tdlib_exception.dart';

/// Result of storage channel detection or creation.
sealed class StorageChannelResult {
  const StorageChannelResult();
}

/// An existing storage channel was found.
class StorageChannelFound extends StorageChannelResult {
  const StorageChannelFound({required this.channelId});

  /// The chat ID of the existing storage channel.
  final int channelId;
}

/// A new storage channel was created.
class StorageChannelCreated extends StorageChannelResult {
  const StorageChannelCreated({required this.channelId});

  /// The chat ID of the newly created channel.
  final int channelId;
}

/// Error during channel detection or creation.
class StorageChannelError extends StorageChannelResult {
  const StorageChannelError({required this.message, this.code});

  final String message;
  final String? code;
}

/// Manages the private Telegram storage channel used by LumoVault.
///
/// After authentication, this service:
/// 1. Searches for an existing "LumoVault Backup" private channel
/// 2. If not found, creates one automatically
/// 3. Stores the channel ID for use by the backup engine
///
/// Per PRD Section 7.3, the channel is:
/// - Private (no invite links)
/// - Hidden from Telegram UI
/// - Contains a pinned manifest message
class StorageChannelService {
  StorageChannelService({required TdLibClient client})
    : _client = client; // ignore: prefer_initializing_formals

  final TdLibClient _client;
  int? _cachedChannelId;

  /// Get the cached channel ID (if known).
  int? get cachedChannelId => _cachedChannelId;

  /// Find or create the LumoVault storage channel.
  ///
  /// Returns [StorageChannelFound] if an existing channel is found,
  /// [StorageChannelCreated] if a new channel was created, or
  /// [StorageChannelError] on failure.
  Future<StorageChannelResult> findOrCreateChannel() async {
    try {
      // Step 0: If we already know the channel id (persisted from a previous
      // run and hydrated via setCachedChannelId), just verify it still exists
      // and reuse it. This is the normal path — it avoids scanning every chat,
      // and (unlike the title match below) survives the user renaming the
      // channel, so we never create a duplicate as long as local state lives.
      final cached = _cachedChannelId;
      if (cached != null && await _chatExists(cached)) {
        return StorageChannelFound(channelId: cached);
      }

      // Step 1: Search for existing channel by title.
      final existingChannelId = await _searchExistingChannel();
      if (existingChannelId != null) {
        _cachedChannelId = existingChannelId;
        return StorageChannelFound(channelId: existingChannelId);
      }

      // Step 2: Create new channel.

      final newChannelId = await _createStorageChannel();
      _cachedChannelId = newChannelId;

      // Step 3: Pin manifest message.
      await _pinManifestMessage(newChannelId);

      return StorageChannelCreated(channelId: newChannelId);
    } on TdLibException catch (e) {
      return StorageChannelError(message: e.displayMessage, code: e.code);
    }
  }

  /// Whether a chat with [chatId] still exists and is reachable.
  ///
  /// Used to validate the persisted/cached channel id before reusing it —
  /// guards against the channel having been deleted out from under us.
  Future<bool> _chatExists(int chatId) async {
    try {
      final chatInfo = await _client.sendRequest(
        method: 'getChat',
        params: {'chat_id': chatId},
      );
      return chatInfo['@type'] != 'error' && chatInfo['id'] != null;
    } catch (_) {
      return false;
    }
  }

  /// Search for an existing LumoVault Backup channel.
  ///
  /// Per PRD Section 10.2, search user's channels for "LumoVault Backup".
  /// Returns the channel ID if found, null otherwise.
  Future<int?> _searchExistingChannel() async {
    try {
      // Get list of user's chats/channels.
      final result = await _client.sendRequest(
        method: 'getChats',
        params: {'chat_filter_id': 0, 'limit': 100},
      );

      final chatIds = (result['chat_ids'] as List<dynamic>?) ?? [];

      // Search each chat for the storage channel name.
      for (final chatId in chatIds) {
        final chatInfo = await _client.sendRequest(
          method: 'getChat',
          params: {'chat_id': chatId},
        );

        final title = chatInfo['title'] as String?;
        if (title == TdLibConfig.storageChannelName) {
          // Verify it's a channel (not a group).
          final chatType = chatInfo['type'] as Map<String, dynamic>?;
          final typeStr = chatType?['@type'] as String?;
          if (typeStr == 'chatTypeBasicGroup' ||
              typeStr == 'chatTypeSupergroup') {
            // Check if it's a channel (not a group).
            final isChannel = chatType?['is_channel'] as bool? ?? false;
            if (!isChannel) continue;
          }

          return chatId as int;
        }
      }

      return null;
    } catch (e) {
      // If we can't search, return null to trigger creation.
      return null;
    }
  }

  /// Create a new private storage channel.
  ///
  /// Per PRD Section 7.3:
  /// - Channel name: "LumoVault Backup"
  /// - Channel type: Private (no invite links)
  /// - Description: Contains app manifest JSON
  Future<int> _createStorageChannel() async {
    final result = await _client.sendRequest(
      method: 'createNewChannel',
      params: {
        'title': TdLibConfig.storageChannelName,
        'description': TdLibConfig.storageChannelDescription,
        'is_channel': true,
        'is_broadcast_group': false,
        'is_forbidden': false,
        'is_megagroup': false,
        'can_add_members': false,
        'can_invite_users': false,
        'can_pin_messages': false,
        'can_publish_messages': false,
        'can_update_stories': false,
        'is_statistics_visible': false,
      },
    );

    // Extract channel ID from the response.
    // TDLib returns the new chat in the response.
    final chat = result['chat'] as Map<String, dynamic>?;
    final chatId = chat?['id'] as int?;

    if (chatId == null) {
      throw const TdLibException(
        message: 'Failed to extract channel ID from creation response',
        code: 'CHANNEL_CREATION_FAILED',
      );
    }

    // Hide the channel from Telegram UI by setting it as archived.
    try {
      await _client.sendRequest(
        method: 'setChatPosition',
        params: {
          'chat_id': chatId,
          'position': {
            '@type': 'chatPosition',
            'list': {'@type': 'chatListArchive'},
            'order': 0,
            'is_pinned': false,
            'source': {'@type': 'chatPositionSourceOther'},
          },
        },
      );
    } catch (e) {
      // Non-critical: channel is created even if archiving fails.
    }

    return chatId;
  }

  /// Pin a manifest message in the storage channel.
  ///
  /// Per PRD Section 6.4, the manifest contains schema version,
  /// device info, and initial stats.
  Future<void> _pinManifestMessage(int channelId) async {
    final manifest = {
      'app': 'lumovault',
      'schema_version': 1,
      'created': DateTime.now().toUtc().toIso8601String(),
      'device_hash': await _generateDeviceHash(),
      'total_media': 0,

      'total_size_bytes': 0,
      'last_sync': DateTime.now().toUtc().toIso8601String(),
      'chunks': <dynamic>[],
    };

    final result = await _client.sendRequest(
      method: 'sendMessage',
      params: {
        'chat_id': channelId,
        'input_message_content': {
          '@type': 'inputMessageText',
          'text': {'@type': 'formattedText', 'text': jsonEncode(manifest)},
          'clear_draft': true,
        },
      },
    );

    final messageId = result['id'] as int?;
    if (messageId != null) {
      try {
        await _client.sendRequest(
          method: 'pinChatMessage',
          params: {
            'chat_id': channelId,
            'message_id': messageId,
            'disable_notification': true,
            'only_for_self': false,
          },
        );
      } catch (e) {
        // Non-critical: manifest is sent even if pinning fails.
      }
    }
  }

  /// Generate a stable, privacy-preserving device hash for the manifest.
  ///
  /// Uses a real per-device identifier (Android id / iOS identifierForVendor)
  /// hashed with SHA-256, so the value is stable across app runs — the old
  /// implementation derived it from `DateTime.now()`, producing a different
  /// "device" hash on every launch, which defeated the point of recording it.
  /// The raw id is never stored; only its hash goes into the manifest.
  Future<String> _generateDeviceHash() async {
    final deviceInfo = DeviceInfoPlugin();
    String rawId;
    try {
      if (Platform.isAndroid) {
        rawId = (await deviceInfo.androidInfo).id;
      } else if (Platform.isIOS) {
        rawId =
            (await deviceInfo.iosInfo).identifierForVendor ??
            Platform.operatingSystem;
      } else {
        rawId = Platform.operatingSystemVersion;
      }
    } catch (_) {
      // If the platform lookup fails, fall back to the OS string — still
      // stable within a run, and avoids throwing during channel setup.
      rawId = Platform.operatingSystem;
    }

    final digest = sha256.convert(utf8.encode('lumovault:$rawId'));
    return digest.toString();
  }

  /// Set the cached channel ID (e.g., from local storage).
  void setCachedChannelId(int channelId) {
    _cachedChannelId = channelId;
  }
}
