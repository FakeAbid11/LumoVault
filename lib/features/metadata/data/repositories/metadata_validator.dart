import 'dart:io';

import '../../../gallery/data/models/media_item.dart';

/// Represents a metadata inconsistency found during validation.
class MetadataIssue {
  const MetadataIssue({
    required this.localId,
    required this.type,
    required this.description,
    this.autoFixable = false,
  });
  final String localId;
  final MetadataIssueType type;
  final String description;

  /// True when the issue corrects itself through normal app activity —
  /// [MetadataIssueType.incompleteMetadata] is filled in by the next device
  /// scan, and [MetadataIssueType.thumbnailMissing] by the next thumbnail
  /// rebuild — so no explicit repair step is needed.
  final bool autoFixable;
}

/// The inconsistencies [MetadataValidator] can actually detect.
///
/// This list is deliberately exactly the set of checks [MetadataValidator.validate]
/// performs. Earlier revisions advertised checks (hash mismatch, orphaned
/// files, dangling partition references, stale search index) that were never
/// implemented; those entries are removed so the enum is a truthful contract
/// rather than an aspirational one.
enum MetadataIssueType {
  /// Local file referenced by metadata doesn't exist on device.
  ///
  /// Not reported for Telegram-only items ([MediaItem.isTelegram]) — their
  /// file lives in the storage channel, so absence on device is expected.
  fileMissing,

  /// Required metadata fields are empty.
  incompleteMetadata,

  /// Thumbnail file is missing or corrupted.
  thumbnailMissing,
}

/// Result of a metadata validation scan.
class ValidationResult {
  const ValidationResult({
    required this.issues,
    required this.itemsChecked,
    required this.duration,
  });
  final List<MetadataIssue> issues;
  final int itemsChecked;
  final Duration duration;

  int get fixableCount => issues.where((i) => i.autoFixable).length;
  bool get hasIssues => issues.isNotEmpty;
}

/// Validates metadata integrity across the app.
///
/// Checks for:
/// - Local files referenced by metadata that no longer exist
/// - Incomplete metadata (empty hash or MIME type)
/// - Missing thumbnails
///
/// This class only *reports*. It deliberately offers no auto-fix method: the
/// fixable issues are corrected by existing background work (device scan,
/// thumbnail rebuild), and a repair that "fixes" a count without doing the
/// work would misreport the state of the library. Callers should present
/// [ValidationResult.fixableCount] as "will self-correct on the next scan",
/// not as work already performed.
class MetadataValidator {
  MetadataValidator({required this._mediaItems});

  final List<MediaItem> _mediaItems;

  /// Run a full validation pass.
  Future<ValidationResult> validate() async {
    final stopwatch = Stopwatch()..start();
    final issues = <MetadataIssue>[];

    for (final item in _mediaItems) {
      // Telegram-only items keep their file in the storage channel, so a
      // missing local path is the expected state, not corruption. Without
      // this guard every restored item was reported missing.
      if (!item.isTelegram) {
        final file = File(item.filePath);
        if (!await file.exists()) {
          issues.add(
            MetadataIssue(
              localId: item.localId,
              type: MetadataIssueType.fileMissing,
              description: 'File missing: ${item.filePath}',
              autoFixable: false,
            ),
          );
        }
      }

      if (item.fileHash.isEmpty) {
        issues.add(
          MetadataIssue(
            localId: item.localId,
            type: MetadataIssueType.incompleteMetadata,
            description: 'File hash is empty',
            autoFixable: true,
          ),
        );
      }

      if (item.mimeType.isEmpty) {
        issues.add(
          MetadataIssue(
            localId: item.localId,
            type: MetadataIssueType.incompleteMetadata,
            description: 'MIME type is empty',
            autoFixable: true,
          ),
        );
      }

      // Check thumbnail.
      final thumbPath = item.thumbnailPath;
      if (thumbPath != null) {
        final thumbFile = File(thumbPath);
        if (!await thumbFile.exists()) {
          issues.add(
            MetadataIssue(
              localId: item.localId,
              type: MetadataIssueType.thumbnailMissing,
              description: 'Thumbnail file missing: $thumbPath',
              autoFixable: true,
            ),
          );
        }
      }
    }

    stopwatch.stop();

    return ValidationResult(
      issues: issues,
      itemsChecked: _mediaItems.length,
      duration: stopwatch.elapsed,
    );
  }
}
