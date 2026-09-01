import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/presentation/screens/media_viewer_screen.dart';

/// The Back-Up button surfaces the scheduler's raw skip reason in a
/// snackbar. Those reasons historically leaked internal identifiers (the
/// OS bucket id "-1313584517") and jargon ("included list"), so they are
/// translated into actionable guidance before display.
void main() {
  group('friendlySkipMessage', () {
    test('translates the current folder-gate refusal', () {
      const raw =
          'Folder "-1313584517" is not in your backup folders. '
          'Enable it under Backup settings > Folders.';

      final message = friendlySkipMessage(raw);

      expect(
        message,
        "This folder isn't in your backup folders — enable it under "
        'Backup settings > Folders',
      );
      // The raw bucket id must not reach the user.
      expect(message, isNot(contains('-1313584517')));
    });

    test('translates the legacy folder-gate refusal', () {
      const raw = 'Folder "-1313584517" is not in included list.';

      final message = friendlySkipMessage(raw);

      expect(message, contains("isn't in your backup folders"));
      expect(message, isNot(contains('-1313584517')));
    });

    test('translates the folder-exclusion refusal', () {
      final message = friendlySkipMessage('Folder "Screenshots" is excluded.');

      expect(message, 'This folder is on your backup exclusion list');
    });

    test('passes unrelated reasons through unchanged', () {
      expect(friendlySkipMessage('File is in trash.'), 'File is in trash.');
    });

    test('handles a missing reason', () {
      expect(friendlySkipMessage(null), 'Skipped by your backup settings');
    });
  });
}
