import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/transfer_error.dart';

void main() {
  group('TransferError', () {
    test('displayMessage returns correct message for each category', () {
      final networkError = TransferError(
        category: TransferErrorCategory.network,
        message: 'Network error',
        occurredAt: DateTime(2026, 7, 14),
      );

      final fileTooLargeError = TransferError(
        category: TransferErrorCategory.fileTooLarge,
        message: 'File too large',
        occurredAt: DateTime(2026, 7, 14),
      );

      final floodWaitError = TransferError(
        category: TransferErrorCategory.floodWait,
        message: 'Flood wait',
        retryAfterSeconds: 300,
        occurredAt: DateTime(2026, 7, 14),
      );

      final authExpiredError = TransferError(
        category: TransferErrorCategory.authExpired,
        message: 'Auth expired',
        occurredAt: DateTime(2026, 7, 14),
      );

      final storageFullError = TransferError(
        category: TransferErrorCategory.storageFull,
        message: 'Storage full',
        occurredAt: DateTime(2026, 7, 14),
      );

      final fileNotFoundError = TransferError(
        category: TransferErrorCategory.fileNotFound,
        message: 'File not found',
        occurredAt: DateTime(2026, 7, 14),
      );

      final permissionDeniedError = TransferError(
        category: TransferErrorCategory.permissionDenied,
        message: 'Permission denied',
        occurredAt: DateTime(2026, 7, 14),
      );

      final unknownError = TransferError(
        category: TransferErrorCategory.unknown,
        message: 'Unknown error',
        occurredAt: DateTime(2026, 7, 14),
      );

      expect(networkError.displayMessage, contains('Network'));
      expect(fileTooLargeError.displayMessage, contains('large'));
      expect(floodWaitError.displayMessage, contains('300'));
      expect(authExpiredError.displayMessage, contains('Session'));
      expect(storageFullError.displayMessage, contains('full'));
      expect(fileNotFoundError.displayMessage, contains('File no longer'));
      expect(permissionDeniedError.displayMessage, contains('permission'));
      expect(unknownError.displayMessage, contains('failed'));
    });

    test('fromTdLibError creates correct error categories', () {
      final networkError = TransferError.fromTdLibError(
        'NETWORK_ERROR',
        'Connection failed',
      );

      final floodWaitError = TransferError.fromTdLibError(
        'FLOOD_WAIT',
        'Too many requests',
      );

      final authError = TransferError.fromTdLibError(
        'AUTH_KEY_UNREGISTERED',
        'Session expired',
      );

      expect(networkError.category, TransferErrorCategory.network);
      expect(networkError.retryable, true);

      expect(floodWaitError.category, TransferErrorCategory.floodWait);
      expect(floodWaitError.retryable, true);

      expect(authError.category, TransferErrorCategory.authExpired);
      expect(authError.retryable, false);
    });

    test('retryable is true for network and flood wait errors', () {
      final networkError = TransferError.fromTdLibError(
        'NETWORK_ERROR',
        'Connection failed',
      );

      final floodWaitError = TransferError.fromTdLibError(
        'FLOOD_WAIT',
        'Too many requests',
      );

      final authError = TransferError.fromTdLibError(
        'AUTH_KEY_UNREGISTERED',
        'Session expired',
      );

      expect(networkError.retryable, true);
      expect(floodWaitError.retryable, true);
      expect(authError.retryable, false);
    });

    test('copyWith creates new instance with updated fields', () {
      final error = TransferError(
        category: TransferErrorCategory.network,
        message: 'Network error',
        occurredAt: DateTime(2026, 7, 14),
      );

      final updated = error.copyWith(retryAfterSeconds: 60);

      expect(updated.retryAfterSeconds, 60);
      expect(error.retryAfterSeconds, isNull);
    });

    test('equality based on category and message', () {
      final error1 = TransferError(
        category: TransferErrorCategory.network,
        message: 'Network error',
        occurredAt: DateTime(2026, 7, 14),
      );

      final error2 = TransferError(
        category: TransferErrorCategory.network,
        message: 'Network error',
        occurredAt: DateTime(2026, 7, 15),
      );

      final error3 = TransferError(
        category: TransferErrorCategory.authExpired,
        message: 'Auth expired',
        occurredAt: DateTime(2026, 7, 14),
      );

      expect(error1, equals(error2));
      expect(error1, isNot(equals(error3)));
    });
  });
}
