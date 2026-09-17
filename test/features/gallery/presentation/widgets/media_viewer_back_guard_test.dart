import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/presentation/widgets/inline_video_player.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// The viewers' `_isVideoFullscreen` field exists only to feed `PopScope.canPop`
/// from the player's own toggle. Before [InlineVideoPlayer.onFullscreenChanged]
/// existed the flag was declared and read but never assigned, so the guard was
/// dead code and a back press left the app instead of leaving fullscreen.
///
/// These tests drive the real player widget through a faked platform decoder,
/// so they cover the whole path: toggle -> callback -> host guard -> back.

/// Minimal platform fake: reports one 320x240 initialized video and answers
/// the controller's control-channel calls with no-ops.
///
/// The initialized event is emitted synchronously at listen-time (via
/// [Stream.multi]) rather than from a timer: a [Future.delayed] would leave an
/// armed timer behind, failing the binding's end-of-test "no timers pending"
/// invariant.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 0;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    return Stream.multi((controller) {
      controller.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: const Size(320, 240),
        ),
      );
    });
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool enabled,
  ) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox();
}

/// Mirrors how both viewer screens consume the callback: the flag feeds a
/// PopScope, and the pop handler resets it instead of popping.
class _BackGuardHost extends StatefulWidget {
  const _BackGuardHost({this.onFullscreenChanged});

  final ValueChanged<bool>? onFullscreenChanged;

  @override
  State<_BackGuardHost> createState() => _BackGuardHostState();
}

class _BackGuardHostState extends State<_BackGuardHost> {
  bool _isVideoFullscreen = false;

  @override
  Widget build(BuildContext context) {
    // PopScope must live INSIDE the Navigator's route: it registers with
    // ModalRoute.of(context), and outside one a back press never reaches the
    // callback. The viewers are pushed routes, so this mirrors them.
    return MaterialApp(
      home: PopScope(
        canPop: !_isVideoFullscreen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _isVideoFullscreen) {
            setState(() => _isVideoFullscreen = false);
          }
        },
        child: Scaffold(
          body: InlineVideoPlayer(
            file: File('test_video.mp4'),
            onFullscreenChanged: (isFullscreen) {
              setState(() => _isVideoFullscreen = isFullscreen);
              widget.onFullscreenChanged?.call(isFullscreen);
            },
          ),
        ),
      ),
    );
  }
}

void main() {
  setUp(() {
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
  });

  Future<void> pumpPlayer(
    WidgetTester tester,
    ValueChanged<bool>? onFullscreenChanged,
  ) async {
    await tester.pumpWidget(
      _BackGuardHost(onFullscreenChanged: onFullscreenChanged),
    );
    // The initialized event is emitted synchronously on listen, so a single
    // pump rebuilds the player past its loading spinner.
    await tester.pump();
    await tester.pump();
  }

  Future<void> disposePlayer(WidgetTester tester) async {
    // The player's thumbnail scrubber arms frame-extraction timers; tearing
    // the tree down and settling lets them observe `!mounted` and finish.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }

  testWidgets('the fullscreen toggle reports state to the host', (tester) async {
    final reported = <bool>[];
    await pumpPlayer(tester, reported.add);

    // Controls are visible on first frame, so the fullscreen button is there.
    expect(find.byIcon(Symbols.fullscreen), findsOneWidget);

    await tester.tap(find.byIcon(Symbols.fullscreen));
    await tester.pump();

    expect(reported, [true]);
    // The icon flips so the same button now exits fullscreen.
    expect(find.byIcon(Symbols.fullscreen_exit), findsOneWidget);

    await tester.tap(find.byIcon(Symbols.fullscreen_exit));
    await tester.pump();

    expect(reported, [true, false]);

    await disposePlayer(tester);
  });

  testWidgets('back exits fullscreen instead of the screen', (tester) async {
    await pumpPlayer(tester, null);

    // PopScope is generic (PopScope<T>), so an exact-type finder misses it;
    // match on the runtime type instead.
    PopScope guard() => tester.widget<PopScope>(
      find.byWidgetPredicate((widget) => widget is PopScope),
    );

    // Not fullscreen: the route pops normally.
    expect(guard().canPop, isTrue);

    await tester.tap(find.byIcon(Symbols.fullscreen));
    await tester.pump();

    // Fullscreen: the guard is now armed.
    expect(guard().canPop, isFalse);

    // The system back button routes through the Navigator; maybePop is what
    // the binding's handlePopRoute calls, and it consults the route's
    // popDisposition — which is what the PopScope's canPop feeds. Note it
    // returns true for a *vetoed* pop too ("handled, don't bubble"), so the
    // assertions below are what actually prove the screen survived.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pump();

    // The screen survived and the flag reset — a second back now pops.
    expect(find.byType(InlineVideoPlayer), findsOneWidget);
    expect(guard().canPop, isTrue);

    await disposePlayer(tester);
  });
}
