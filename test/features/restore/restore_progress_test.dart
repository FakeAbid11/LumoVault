import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/restore/data/models/restore_progress.dart';
import 'package:lumovault/features/restore/data/repositories/restore_repository.dart';
import 'package:lumovault/features/gallery/data/models/transfer_error.dart';

void main() {
  group('RestoreProgress', () {
    test('default state is detecting phase', () {
      const progress = RestoreProgress();
      expect(progress.phase, RestorePhase.detecting);
      expect(progress.overallProgress, 0.0);
      expect(progress.totalItems, 0);
      expect(progress.completedItems, 0);
      expect(progress.failedItems, 0);
      expect(progress.skippedItems, 0);
      expect(progress.isPaused, isFalse);
    });

    test('isComplete returns true when phase is completed', () {
      const progress = RestoreProgress(phase: RestorePhase.completed);
      expect(progress.isComplete, isTrue);
      expect(progress.isActive, isFalse);
    });

    test('isFailed returns true when phase is failed', () {
      const progress = RestoreProgress(phase: RestorePhase.failed);
      expect(progress.isFailed, isTrue);
      expect(progress.isActive, isFalse);
    });

    test('isActive returns true for active phases', () {
      expect(
        const RestoreProgress(phase: RestorePhase.detecting).isActive,
        isTrue,
      );
      expect(
        const RestoreProgress(phase: RestorePhase.manifestDownload).isActive,
        isTrue,
      );
      expect(
        const RestoreProgress(phase: RestorePhase.metadataDownload).isActive,
        isTrue,
      );
      expect(
        const RestoreProgress(phase: RestorePhase.databaseRebuild).isActive,
        isTrue,
      );
      expect(
        const RestoreProgress(phase: RestorePhase.thumbnailDownload).isActive,
        isTrue,
      );
      expect(
        const RestoreProgress(phase: RestorePhase.originalDownload).isActive,
        isTrue,
      );
    });

    test('copyWith creates updated copy', () {
      const progress = RestoreProgress();
      final updated = progress.copyWith(
        phase: RestorePhase.manifestDownload,
        overallProgress: 0.5,
        totalItems: 100,
        completedItems: 50,
      );

      expect(updated.phase, RestorePhase.manifestDownload);
      expect(updated.overallProgress, 0.5);
      expect(updated.totalItems, 100);
      expect(updated.completedItems, 50);
      expect(updated.failedItems, 0);
    });

    test('copyWith clearError removes error', () {
      final progress = RestoreProgress(
        error: RestoreError(
          category: RestoreErrorCategory.network,
          message: 'Network error',
          occurredAt: DateTime.now(),
        ),
      );

      final cleared = progress.copyWith(clearError: true);
      expect(cleared.error, isNull);
    });

    test('progressPercent calculates correctly', () {
      const progress = RestoreProgress(overallProgress: 0.75);
      expect(progress.progressPercent, 75.0);
    });

    test('progressDisplay returns correct string', () {
      const progress = RestoreProgress(completedItems: 50, totalItems: 100);
      expect(progress.progressDisplay, '50 of 100');
    });

    test('progressDisplay returns starting when no items', () {
      const progress = RestoreProgress();
      expect(progress.progressDisplay, 'Starting...');
    });

    test('phaseDescription returns correct text for each phase', () {
      expect(
        const RestoreProgress(phase: RestorePhase.detecting).phaseDescription,
        'Checking for existing backup...',
      );
      expect(
        const RestoreProgress(
          phase: RestorePhase.manifestDownload,
        ).phaseDescription,
        'Reading your library structure...',
      );
      expect(
        const RestoreProgress(
          phase: RestorePhase.metadataDownload,
        ).phaseDescription,
        'Downloading metadata...',
      );
      expect(
        const RestoreProgress(
          phase: RestorePhase.databaseRebuild,
        ).phaseDescription,
        'Rebuilding your library...',
      );
      expect(
        const RestoreProgress(
          phase: RestorePhase.thumbnailDownload,
        ).phaseDescription,
        'Loading thumbnails...',
      );
      expect(
        const RestoreProgress(
          phase: RestorePhase.originalDownload,
        ).phaseDescription,
        'Downloading full-resolution files...',
      );
      expect(
        const RestoreProgress(phase: RestorePhase.completed).phaseDescription,
        'Restore complete!',
      );
      expect(
        const RestoreProgress(phase: RestorePhase.cancelled).phaseDescription,
        'Restore cancelled',
      );
      expect(
        const RestoreProgress(phase: RestorePhase.paused).phaseDescription,
        'Restore paused',
      );
    });
  });

  group('ManifestInfo', () {
    test('totalSizeDisplay formats GB correctly', () {
      final info = ManifestInfo(
        totalMedia: 100,
        totalSizeBytes: 2 * 1024 * 1024 * 1024, // 2 GB
        created: DateTime(2026, 1, 1),
        lastSync: DateTime(2026, 1, 15),
        chunkCount: 12,
        deviceHash: 'abc123',
      );
      expect(info.totalSizeDisplay, '2.0 GB');
    });

    test('totalSizeDisplay formats MB correctly', () {
      final info = ManifestInfo(
        totalMedia: 100,
        totalSizeBytes: 500 * 1024 * 1024, // 500 MB
        created: DateTime(2026, 1, 1),
        lastSync: DateTime(2026, 1, 15),
        chunkCount: 12,
        deviceHash: 'abc123',
      );
      expect(info.totalSizeDisplay, '500.0 MB');
    });

    test('dateRangeDisplay shows correct date', () {
      final info = ManifestInfo(
        totalMedia: 100,
        totalSizeBytes: 1024 * 1024,
        created: DateTime(2026, 7, 14),
        lastSync: DateTime(2026, 7, 15),
        chunkCount: 12,
        deviceHash: 'abc123',
      );
      expect(info.dateRangeDisplay, 'Since 7/14/2026');
    });
  });

  group('RestoreError', () {
    test('fromTransferError maps categories correctly', () {
      final transferError = TransferError(
        category: TransferErrorCategory.network,
        message: 'Connection failed',
        retryable: true,
        occurredAt: DateTime.now(),
      );

      final restoreError = RestoreError.fromTransferError(transferError);
      expect(restoreError.category, RestoreErrorCategory.network);
      expect(restoreError.message, isNotEmpty);
      expect(restoreError.retryable, isTrue);
    });

    test('network factory creates correct error', () {
      final error = RestoreError.network(message: 'No connection');
      expect(error.category, RestoreErrorCategory.network);
      expect(error.message, 'No connection');
      expect(error.retryable, isTrue);
    });

    test('channelNotFound factory creates correct error', () {
      final error = RestoreError.channelNotFound();
      expect(error.category, RestoreErrorCategory.channelNotFound);
      expect(error.message, 'No backup found');
      expect(error.retryable, isFalse);
    });

    test('manifestCorrupted factory creates correct error', () {
      final error = RestoreError.manifestCorrupted();
      expect(error.category, RestoreErrorCategory.manifestCorrupted);
      expect(error.message, 'Backup data is corrupted');
      expect(error.retryable, isFalse);
    });

    test('storageFull factory creates correct error', () {
      final error = RestoreError.storageFull();
      expect(error.category, RestoreErrorCategory.storageFull);
      expect(error.message, 'Not enough storage space');
      expect(error.retryable, isFalse);
    });

    test('authExpired factory creates correct error', () {
      final error = RestoreError.authExpired();
      expect(error.category, RestoreErrorCategory.authExpired);
      expect(error.message, 'Session expired');
      expect(error.retryable, isFalse);
    });

    test('cancelled factory creates correct error', () {
      final error = RestoreError.cancelled();
      expect(error.category, RestoreErrorCategory.cancelled);
      expect(error.message, 'Restore cancelled');
      expect(error.retryable, isFalse);
    });

    test('displayMessage returns user-friendly text', () {
      expect(
        RestoreError.network(message: 'test').displayMessage,
        'Waiting for internet connection...',
      );
      expect(RestoreError.channelNotFound().displayMessage, 'No backup found');
      expect(
        RestoreError.manifestCorrupted().displayMessage,
        'Backup data is corrupted',
      );
      expect(
        RestoreError.storageFull().displayMessage,
        'Not enough storage space',
      );
      expect(
        RestoreError.authExpired().displayMessage,
        'Session expired. Please log in again.',
      );
    });
  });

  group('ChannelDetectionResult', () {
    test('hasBackup returns true for existing channel', () {
      const result = ChannelDetectionResult(
        channelId: 123,
        isNewChannel: false,
      );
      expect(result.hasBackup, isTrue);
      expect(result.hasError, isFalse);
      expect(result.isNew, isFalse);
    });

    test('hasBackup returns false for new channel', () {
      const result = ChannelDetectionResult(channelId: 123, isNewChannel: true);
      expect(result.hasBackup, isFalse);
      expect(result.isNew, isTrue);
    });

    test('hasError returns true when error is set', () {
      const result = ChannelDetectionResult(error: 'Failed to connect');
      expect(result.hasError, isTrue);
      expect(result.hasBackup, isFalse);
    });
  });

  group('ChannelMessage', () {
    test('captionMetadata parses caption correctly', () {
      const message = ChannelMessage(
        messageId: 1,
        fileId: 100,
        fileName: 'photo.jpg',
        caption: '{"mid":"123","h":"abc123","ct":"2026-01-15T00:00:00Z"}',
      );

      final metadata = message.captionMetadata;
      expect(metadata, isNotNull);
      expect(metadata!.mediaItemId, '123');
      expect(metadata.fileHash, 'abc123');
    });

    test('captionMetadata returns null for empty caption', () {
      const message = ChannelMessage(
        messageId: 1,
        fileId: 100,
        fileName: 'photo.jpg',
        caption: null,
      );
      expect(message.captionMetadata, isNull);
    });

    test('captionMetadata returns null for empty string', () {
      const message = ChannelMessage(
        messageId: 1,
        fileId: 100,
        fileName: 'photo.jpg',
        caption: '',
      );
      expect(message.captionMetadata, isNull);
    });
  });
}
