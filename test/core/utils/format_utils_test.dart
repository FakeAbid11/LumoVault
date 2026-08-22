import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/utils/format_utils.dart';

void main() {
  group('formatBytes', () {
    test('formats bytes', () {
      expect(formatBytes(512), '512 B');
    });

    test('formats kilobytes', () {
      expect(formatBytes(1536), '1.5 KB');
    });

    test('formats megabytes', () {
      expect(formatBytes(1024 * 1024 * 2), '2.0 MB');
    });

    test('formats gigabytes', () {
      expect(formatBytes(1024 * 1024 * 1024 * 3), '3.0 GB');
    });
  });

  group('formatDateKey', () {
    test('returns Today for today', () {
      expect(formatDateKey(DateTime.now()), 'Today');
    });

    test('returns Yesterday for yesterday', () {
      expect(
        formatDateKey(DateTime.now().subtract(const Duration(days: 1))),
        'Yesterday',
      );
    });

    test('returns formatted date for older dates', () {
      final date = DateTime(2025, 3, 15);
      expect(formatDateKey(date), '3/15/2025');
    });

    test('returns formatted date for future dates', () {
      final date = DateTime(2030, 12, 25);
      expect(formatDateKey(date), '12/25/2030');
    });
  });
}
