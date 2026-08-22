import 'package:flutter/foundation.dart';

import '../../../../core/tdlib/tdlib_client.dart';
import '../../../../core/tdlib/tdlib_connection_manager.dart';

/// Deletes messages from the storage channel — the destructive half of
/// two-way sync (PRD Section 6).
///
/// Split out from [UploadService]/[DownloadService] because it is the one
/// irreversible channel operation: `deleteMessages(revoke: true)` removes the
/// media message for every member of the channel, so it is wired ONLY to the
/// permanent-delete path (empty-trash / delete-forever), never to a recoverable
/// trash move.
abstract class DeletionService {
  /// Delete [messageIds] from [channelId]. With [revoke] true (the default and
  /// only production use), the messages are removed for all channel members,
  /// not just this client — that is what makes the deletion propagate.
  ///
  /// A no-op for an empty [messageIds]. Best-effort: TDLib may reject ids it
  /// no longer knows (already deleted), which is fine — the local tombstone
  /// still converges other devices on the next pull.
  Future<void> deleteMessages({
    required int channelId,
    required List<int> messageIds,
    bool revoke = true,
  });
}

/// TDLib-backed [DeletionService]. Mirrors [TelegramUploadService]'s wiring:
/// requests go through the connection manager so a dropped connection reuses
/// the app-wide backoff/reconnect logic, and the sender is injectable because
/// [TdLibClient] is a private-constructor FFI singleton that cannot be built in
/// a test.
class TelegramDeletionService implements DeletionService {
  TelegramDeletionService({
    required TdLibConnectionManager manager,
    @visibleForTesting TdRequestSender? requestSender,
  }) : _sendRequest = requestSender ?? manager.sendRequest;

  final TdRequestSender _sendRequest;

  @override
  Future<void> deleteMessages({
    required int channelId,
    required List<int> messageIds,
    bool revoke = true,
  }) async {
    if (messageIds.isEmpty) return;
    await _sendRequest(
      method: 'deleteMessages',
      params: {
        'chat_id': channelId,
        'message_ids': messageIds,
        'revoke': revoke,
      },
    );
  }
}
