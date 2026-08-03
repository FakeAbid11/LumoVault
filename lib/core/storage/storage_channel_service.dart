import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

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

/// The search completed successfully and no storage channel exists.
///
/// This is a *positive* answer, not the absence of one — it is the only
/// result that justifies creating a channel. Anything that merely failed to
/// answer the question comes back as [StorageChannelError].
class StorageChannelNotFound extends StorageChannelResult {
  const StorageChannelNotFound();
}

/// Error during channel detection or creation.
///
/// Critically, this also covers "the lookup itself failed" — a network
/// blip, a TDLib error, a chat list that wouldn't load. Callers must never
/// read this as "no channel exists": creating a channel on a failed lookup
/// is exactly how a user ends up with two backup channels and an archive
/// split across both.
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
  StorageChannelService({
    required TdLibClient client,
    @visibleForTesting TdRequestSender? requestSender,
  }) : _sendRequest = requestSender ?? client.sendRequest;

  /// Issues TDLib requests. Defaults to the real client; overridable in tests
  /// because [TdLibClient] can't be constructed or subclassed (see
  /// [TdRequestSender]).
  final TdRequestSender _sendRequest;
  int? _cachedChannelId;

  /// Get the cached channel ID (if known).
  int? get cachedChannelId => _cachedChannelId;

  /// Look for the LumoVault storage channel without creating one if it's
  /// not found.
  ///
  /// Returns [StorageChannelFound], [StorageChannelNotFound] when the search
  /// ran to completion and genuinely turned up nothing, or
  /// [StorageChannelError] when the search couldn't be carried out. The three
  /// cases are deliberately distinct: an earlier version returned a bare
  /// `int?` and so had no way to say "I don't know", which meant a transient
  /// error looked identical to "no backup exists".
  ///
  /// [findOrCreateChannel] isn't safe to use for "does a backup already
  /// exist?" checks: if the search comes up empty, it creates a brand new
  /// channel as a side effect — so a caller just checking would silently
  /// spawn an empty duplicate channel and (via the create path setting
  /// isNewChannel: true) incorrectly conclude no backup exists, even when
  /// a real one does but just wasn't found by the search. Detection needs
  /// a path with no create-power at all.
  Future<StorageChannelResult> findExistingChannel() async {
    final cached = _cachedChannelId;
    if (cached != null && await _chatExists(cached)) {
      return StorageChannelFound(channelId: cached);
    }

    final result = await _searchExistingChannel();
    if (result is StorageChannelFound) {
      _cachedChannelId = result.channelId;
    }
    return result;
  }

  /// Find or create the LumoVault storage channel.
  ///
  /// Returns [StorageChannelFound] if an existing channel is found,
  /// [StorageChannelCreated] if a new channel was created, or
  /// [StorageChannelError] on failure — including when the *search* failed.
  /// A failed search never falls through to creation.
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
      final search = await _searchExistingChannel();
      switch (search) {
        case StorageChannelFound(:final channelId):
          _cachedChannelId = channelId;
          return StorageChannelFound(channelId: channelId);
        case StorageChannelError():
          // We don't know whether a channel exists. Creating one here is how
          // a user's backup gets split across two channels — bail out and let
          // the caller retry instead.
          return search;
        case StorageChannelCreated():
          // Unreachable: the search path has no create-power.
          return search;
        case StorageChannelNotFound():
          break;
      }

      // Step 2: Create new channel. Only reached on a definitive not-found.

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
      final chatInfo = await _sendRequest(
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
  /// Returns [StorageChannelFound], [StorageChannelNotFound] if both lists
  /// were searched successfully and nothing matched, or
  /// [StorageChannelError] if either search failed.
  ///
  /// Checks both chatListMain and chatListArchive: [_createStorageChannel]
  /// moves the channel to the archive list right after creating it (so it
  /// stays out of the user's normal chat list), so a search that only
  /// checked chatListMain would never find a channel from a previous
  /// session — and would create a fresh duplicate channel every time
  /// [cachedChannelId]/the persisted channel id isn't available yet.
  Future<StorageChannelResult> _searchExistingChannel() async {
    for (final chatList in const [
      {'@type': 'chatListMain'},
      {'@type': 'chatListArchive'},
    ]) {
      final result = await _searchChannelInList(chatList);
      // A failure in either list means we can't rule the channel out. Stop
      // and report it rather than letting the remaining list's empty result
      // masquerade as a definitive "no channel exists".
      if (result is! StorageChannelNotFound) return result;
    }
    return const StorageChannelNotFound();
  }

  Future<StorageChannelResult> _searchChannelInList(
    Map<String, dynamic> chatList,
  ) async {
    try {
      // TDLib only returns chats that are already loaded into memory, so ask
      // it to load the list first. Without this, a freshly-started client
      // reports an empty chat list and we'd wrongly conclude no storage
      // channel exists and create a duplicate.
      try {
        await _sendRequest(
          method: 'loadChats',
          params: {'chat_list': chatList, 'limit': 100},
        );
      } catch (_) {
        // 404 here just means "all chats already loaded" — safe to ignore.
      }

      // Get list of user's chats/channels. `getChats` takes a chat_list and a
      // limit (the old 'chat_filter_id' param isn't valid and made TDLib
      // reject the request, so the search silently found nothing).
      final result = await _sendRequest(
        method: 'getChats',
        params: {'chat_list': chatList, 'limit': 100},
      );

      final chatIds = (result['chat_ids'] as List<dynamic>?) ?? [];

      // Search each chat for the storage channel name.
      for (final chatId in chatIds) {
        final chatInfo = await _sendRequest(
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

          return StorageChannelFound(channelId: chatId as int);
        }
      }

      return const StorageChannelNotFound();
    } on TdLibException catch (e) {
      // Previously this returned null, which the caller read as "no channel
      // exists" and acted on by creating one. Report the failure instead.
      debugPrint('[StorageChannelService] Chat list search failed: $e');
      return StorageChannelError(message: e.displayMessage, code: e.code);
    } catch (e) {
      debugPrint('[StorageChannelService] Chat list search failed: $e');
      return StorageChannelError(message: 'Channel lookup failed: $e');
    }
  }

  /// Create a new private storage channel.
  ///
  /// Per PRD Section 7.3:
  /// - Channel name: "LumoVault Backup"
  /// - Channel type: Private (no invite links)
  /// - Description: Contains app manifest JSON
  Future<int> _createStorageChannel() async {
    // The correct TDLib method is `createNewSupergroupChat` with
    // `is_channel: true` — there is NO `createNewChannel` method, so the old
    // call errored out on every attempt and no channel was ever created.
    // TDLib also rejects requests carrying unknown params, so only the
    // documented fields are sent here.
    final result = await _sendRequest(
      method: 'createNewSupergroupChat',
      params: {
        'title': TdLibConfig.storageChannelName,
        'is_channel': true,
        'description': TdLibConfig.storageChannelDescription,
        'message_auto_delete_time': 0,
        'for_import': false,
      },
    );

    // `createNewSupergroupChat` returns a `chat` object directly, so the id
    // is on the top-level response — not nested under a 'chat' key as the
    // old code assumed (which would have thrown even on success).
    final chatId = result['id'] as int?;

    if (chatId == null) {
      debugPrint(
        '[StorageChannelService] createNewSupergroupChat returned no chat '
        'id. Response @type=${result['@type']}',
      );
      throw const TdLibException(
        message: 'Failed to extract channel ID from creation response',
        code: 'CHANNEL_CREATION_FAILED',
      );
    }

    // Hide the channel from Telegram UI by setting it as archived.
    try {
      await _sendRequest(
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
      'device_hash': await generateDeviceHash(),
      'total_media': 0,

      'total_size_bytes': 0,
      'last_sync': DateTime.now().toUtc().toIso8601String(),
      'chunks': <dynamic>[],
    };

    final result = await _sendRequest(
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
        await _sendRequest(
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
  /// Uses a real per-device identifier (Android id)
  /// hashed with SHA-256, so the value is stable across app runs — the old
  /// implementation derived it from `DateTime.now()`, producing a different
  /// "device" hash on every launch, which defeated the point of recording it.
  /// The raw id is never stored; only its hash goes into the manifest.
  ///
  /// Public so the metadata sync layer can stamp the same device hash into
  /// the manifest files it uploads — both manifests must agree on which
  /// device produced the backup.
  Future<String> generateDeviceHash() async {
    final deviceInfo = DeviceInfoPlugin();
    String rawId;
    try {
      if (Platform.isAndroid) {
        rawId = (await deviceInfo.androidInfo).id;
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
