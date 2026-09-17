import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/presentation/widgets/video_player_controls.dart';
import 'package:video_player/video_player.dart';

/// The controls used to early-return `SizedBox.shrink()` whenever
/// `visible` was false, which made the `AnimatedOpacity`'s `opacity: 0.0`
/// branch unreachable: the controls vanished in a single frame instead of
/// fading, and the fade-out animation never played.
///
/// The controller is left uninitialized on purpose — [VideoPlayerControls]
/// only reads `position`/`duration` from it and never touches the platform
/// unless a control is tapped, so no platform fake is needed to exercise the
/// visibility machinery.
void main() {
  late VideoPlayerController controller;

  setUp(() {
    controller = VideoPlayerController.file(File('test_video.mp4'));
    addTearDown(controller.dispose);
  });

  Future<void> pumpControls(
    WidgetTester tester, {
    required bool visible,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoPlayerControls(controller: controller, visible: visible),
        ),
      ),
    );
    // One frame is enough for the assertions, which read build-time widget
    // properties. pumpAndSettle never returns here: the controller keeps the
    // binding busy, and nothing in these tests needs the animation to finish.
    await tester.pump();
  }

  testWidgets('visible controls render at full opacity', (tester) async {
    await pumpControls(tester, visible: true);

    // Scope to the widget under test: MaterialApp/Scaffold contribute their
    // own IgnorePointer/AnimatedOpacity instances to the tree.
    final scope = find.byType(VideoPlayerControls);
    final opacity = tester.widget<AnimatedOpacity>(
      find.descendant(of: scope, matching: find.byType(AnimatedOpacity)),
    );
    expect(opacity.opacity, 1.0);
    final ignore = tester.widget<IgnorePointer>(
      find.descendant(of: scope, matching: find.byType(IgnorePointer)),
    );
    expect(
      ignore.ignoring,
      isFalse,
      reason: 'visible controls must stay tappable',
    );
  });

  testWidgets('invisible controls stay in the tree and fade to opacity 0', (
    tester,
  ) async {
    await pumpControls(tester, visible: true);

    // Flip visible false: the widget must REMAIN in the tree with opacity 0
    // so the 250ms fade plays. The old early return replaced it with a
    // zero-size box in one frame, and this find would then find nothing.
    await pumpControls(tester, visible: false);
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.byType(VideoPlayerControls), findsOneWidget);
    final scope = find.byType(VideoPlayerControls);
    final faded = tester.widget<AnimatedOpacity>(
      find.descendant(of: scope, matching: find.byType(AnimatedOpacity)),
    );
    expect(faded.opacity, 0.0);

    // Faded-out controls must not swallow taps meant for the video.
    final ignore = tester.widget<IgnorePointer>(
      find.descendant(of: scope, matching: find.byType(IgnorePointer)),
    );
    expect(ignore.ignoring, isTrue);
  });
}
