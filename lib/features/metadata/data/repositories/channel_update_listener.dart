import 'dart:async';

import '../../../../core/storage/storage_channel_service.dart';
import 'metadata_sync_coordinator.dart';
import 'telegram_metadata_uploader.dart';

/// Listens to the live TDLib update stream and triggers a debounced pull when
/// the storage channel changes — the "react without a manual scan" half of
/// two-way sync (PRD Section 6).
///
/// A change made on another device (or via another Telegram client) surfaces
/// as an `updateNewMessage` / `updateMessageContent` / `updateDeleteMessages`
/// on our own client. This filters those to the storage channel's chat id and
/// fires [MetadataSyncCoordinator.pullNow] after a short debounce, so a burst
/// of edits collapses into one reconcile.
///
/// Echo avoidance: our own metadata uploads also come back as updates. The
/// uploader records the message ids it just sent ([TelegramMetadataUploader.
/// wasRecentlySent]); updates for those ids are ignored. As a backstop,
/// reconcile is idempotent, so a self-echo that slips through is a no-op.
class ChannelUpdateListener {
  ChannelUpdateListener({
    required this.updates,
    required this.coordinator,
    required this.uploader,
    this.storageChannelService,
    this.chatIdProvider,
    this.debounce = const Duration(seconds: 5),
  });

  final Stream<Map<String, dynamic>> updates;
  final MetadataSyncCoordinator coordinator;
  final TelegramMetadataUploader uploader;

  /// Resolves the storage channel chat id. Defaults to
  /// [StorageChannelService.findExistingChannel]. One of this or
  /// [chatIdProvider] must be supplied.
  final StorageChannelService? storageChannelService;
  final Future<int?> Function()? chatIdProvider;

  /// Coalescing window: multiple channel updates in quick succession trigger a
  /// single pull. Reuses the 5s idiom the push debounce uses.
  final Duration debounce;

  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _debounceTimer;

  /// The resolved storage channel chat id, cached once known so we don't
  /// re-validate the channel on every incoming update.
  int? _chatId;

  static const Set<String> _relevantTypes = {
    'updateNewMessage',
    'updateMessageContent',
    'updateDeleteMessages',
  };

  /// Begin listening. Idempotent — a second call is ignored.
  void start() {
    _subscription ??= updates.listen(_onUpdate);
  }

  void _onUpdate(Map<String, dynamic> update) {
    final type = update['@type'] as String?;
    if (type == null || !_relevantTypes.contains(type)) return;
    // Resolve + filter asynchronously; the stream callback itself stays sync.
    unawaited(_handle(type, update));
  }

  Future<void> _handle(String type, Map<String, dynamic> update) async {
    final chatId = await _resolveChatId();
    if (chatId == null) return;

    switch (type) {
      case 'updateNewMessage':
        final message = update['message'] as Map<String, dynamic>?;
        if (message == null) return;
        if (message['chat_id'] != chatId) return;
        // Ignore the echo of a document we just uploaded.
        final messageId = message['id'] as int?;
        if (messageId != null && uploader.wasRecentlySent(messageId)) return;
        break;
      case 'updateMessageContent':
        if (update['chat_id'] != chatId) return;
        final messageId = update['message_id'] as int?;
        if (messageId != null && uploader.wasRecentlySent(messageId)) return;
        break;
      case 'updateDeleteMessages':
        if (update['chat_id'] != chatId) return;
        // Deletions on the channel are never our own metadata echo (we only
        // ever add metadata documents), so no echo check here.
        break;
      default:
        return;
    }

    _schedulePull();
  }

  void _schedulePull() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(coordinator.pullNow());
    });
  }

  Future<int?> _resolveChatId() async {
    final cached = _chatId;
    if (cached != null) return cached;

    final override = chatIdProvider;
    if (override != null) {
      final id = await override();
      _chatId = id;
      return id;
    }

    final service = storageChannelService;
    if (service == null) return null;
    final result = await service.findExistingChannel();
    switch (result) {
      case StorageChannelFound(:final channelId):
      case StorageChannelCreated(:final channelId):
        _chatId = channelId;
        return channelId;
      case StorageChannelNotFound():
      case StorageChannelError():
        return null;
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _subscription?.cancel();
    _subscription = null;
  }
}
