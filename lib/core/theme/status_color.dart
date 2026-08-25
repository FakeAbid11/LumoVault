import 'package:flutter/material.dart';

import '../../features/gallery/data/models/media_item.dart';
import 'app_colors.dart';

/// Semantic colours for a [MediaStatus] badge, resolved against the active
/// theme so they read in both light and dark.
///
/// Centralizes what used to be hand-picked `Colors.orange/green/red/grey`
/// literals scattered across the gallery tiles and the media viewer. Only the
/// two states Material has no scheme role for — a "pending" amber and an
/// "uploaded" success green — are literals here; the rest map to scheme roles.
///
/// A null status is treated as [MediaStatus.pending] (an asset that hasn't been
/// scanned yet but is selected for backup).
Color statusColor(BuildContext context, MediaStatus? status) {
  final scheme = Theme.of(context).colorScheme;
  switch (status) {
    case null:
    case MediaStatus.pending:
      return _pending;
    case MediaStatus.uploading:
      return AppColors.syncing;
    case MediaStatus.uploaded:
      return _success;
    case MediaStatus.failed:
      return scheme.error;
    case MediaStatus.excluded:
      return scheme.onSurfaceVariant;
  }
}

/// A neutral "queued / not yet uploaded" amber.
const Color _pending = Color(0xFFFFA726);

/// A "backed up successfully" green. Material 3 has no success role, so this is
/// a fixed accent tuned to read on the gallery's dark scrim.
const Color _success = Color(0xFF4CAF50);

/// The success green, exposed for non-[MediaStatus] success markers
/// (e.g. the backup queue's completed rows).
const Color successColor = _success;
