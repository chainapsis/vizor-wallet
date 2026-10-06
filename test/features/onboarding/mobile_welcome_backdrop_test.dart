@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
// video_player exposes its platform interface through a transitive package;
// importing it here lets the widget test replace the native decoder.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_welcome_backdrop.dart';

class _PendingPlaybackCommand {
  _PendingPlaybackCommand(this.name, this.completer);

  final String name;
  final Completer<void> completer;
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final calls = <String>[];
  final createdSources = <DataSource>[];
  final createdOptions = <VideoPlayerOptions?>[];
  final volumes = <double>[];
  final loopingValues = <bool>[];
  final _events = <int, StreamController<VideoEvent>>{};
  final pendingPlaybackCommands = <_PendingPlaybackCommand>[];
  bool delayPlaybackCommands = false;
  bool nativeIsPlaying = false;
  int activePlaybackCommands = 0;
  int maxConcurrentPlaybackCommands = 0;
  var _nextPlayerId = 1;

  @override
  Future<void> init() async {
    calls.add('init');
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    calls.add('create');
    createdSources.add(options.dataSource);
    createdOptions.add(options.videoPlayerOptions);
    final playerId = _nextPlayerId++;
    final events = StreamController<VideoEvent>();
    _events[playerId] = events;
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: Duration(seconds: 8),
        size: Size(720, 1280),
      ),
    );
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    calls.add('mix:$mixWithOthers');
  }

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) async {
    calls.add('prevent-sleep:$preventsDisplaySleepDuringVideoPlayback');
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {
    calls.add('volume:$volume');
    volumes.add(volume);
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    calls.add('loop:$looping');
    loopingValues.add(looping);
  }

  @override
  Future<void> play(int playerId) => _playbackCommand('play', playing: true);

  @override
  Future<void> pause(int playerId) => _playbackCommand('pause', playing: false);

  Future<void> _playbackCommand(String name, {required bool playing}) async {
    calls.add(name);
    if (!delayPlaybackCommands) {
      nativeIsPlaying = playing;
      return;
    }

    final command = _PendingPlaybackCommand(name, Completer<void>());
    pendingPlaybackCommands.add(command);
    activePlaybackCommands++;
    if (activePlaybackCommands > maxConcurrentPlaybackCommands) {
      maxConcurrentPlaybackCommands = activePlaybackCommands;
    }
    await command.completer.future;
    nativeIsPlaying = playing;
    activePlaybackCommands--;
  }

  void completePendingPlaybackCommandsNewestFirst() {
    final newestFirst = pendingPlaybackCommands.reversed.toList();
    pendingPlaybackCommands.clear();
    for (final command in newestFirst) {
      command.completer.complete();
    }
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    calls.add('speed:$speed');
  }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
    await _events.remove(playerId)?.close();
  }

  @override
  Widget buildView(int playerId) => Texture(textureId: playerId);
}

Widget _app({
  bool animate = true,
  bool disableAnimations = false,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  return MaterialApp(
    navigatorKey: navigatorKey,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: Scaffold(body: MobileWelcomeBackdrop(animate: animate)),
  );
}

Future<void> _pumpInitialized(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.pump();
}

Future<void> _disposeBackdrop(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // MobileWelcomeBackdrop deliberately starts controller disposal without
  // awaiting it, so flush the controller's subscription-cancellation steps.
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoPlayerPlatform originalPlatform;
  late _FakeVideoPlayerPlatform platform;

  setUp(() {
    originalPlatform = VideoPlayerPlatform.instance;
    platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
  });

  tearDown(() {
    VideoPlayerPlatform.instance = originalPlatform;
  });

  testWidgets('does not initialize when animation is explicitly disabled', (
    tester,
  ) async {
    await tester.pumpWidget(_app(animate: false));
    await tester.pump();

    expect(platform.createdSources, isEmpty);
    expect(find.byType(VideoPlayer), findsNothing);
  });

  testWidgets('does not initialize when reduced motion is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(_app(disableAnimations: true));
    await tester.pump();

    expect(platform.createdSources, isEmpty);
    expect(find.byType(VideoPlayer), findsNothing);
  });

  testWidgets('initializes the bundled asset muted and looping', (
    tester,
  ) async {
    await _pumpInitialized(tester, _app());

    expect(platform.createdSources, hasLength(1));
    expect(platform.createdSources.single.asset, kMobileWelcomeVideoAsset);
    expect(platform.calls, contains('mix:true'));
    expect(platform.calls, contains('prevent-sleep:false'));
    expect(platform.volumes, contains(0));
    expect(platform.loopingValues, contains(true));
    expect(platform.calls, contains('play'));
    expect(find.byType(VideoPlayer), findsOneWidget);

    await _disposeBackdrop(tester);
  });

  testWidgets('pauses in the background and resumes in the foreground', (
    tester,
  ) async {
    await _pumpInitialized(tester, _app());
    platform.calls.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(platform.calls, contains('pause'));

    platform.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.calls, contains('play'));

    await _disposeBackdrop(tester);
  });

  testWidgets('serializes rapid lifecycle playback changes', (tester) async {
    await _pumpInitialized(tester, _app());
    expect(
      platform.createdOptions.single?.allowBackgroundPlayback,
      isTrue,
      reason: 'The backdrop owns lifecycle reconciliation.',
    );
    platform
      ..calls.clear()
      ..delayPlaybackCommands = true;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    // If pause/play were allowed to overlap, a native player could complete
    // play first and the older pause last, leaving the visible route paused.
    expect(platform.pendingPlaybackCommands.map((command) => command.name), [
      'pause',
    ]);
    expect(platform.maxConcurrentPlaybackCommands, 1);

    // Deliberately release newer commands first. Without serialization this
    // makes a stale pause complete after play and leaves native playback off.
    platform.completePendingPlaybackCommandsNewestFirst();
    await tester.pump();
    await tester.pump();
    expect(platform.pendingPlaybackCommands.map((command) => command.name), [
      'play',
    ]);

    platform.completePendingPlaybackCommandsNewestFirst();
    await tester.pump();
    await tester.pump();
    expect(platform.nativeIsPlaying, isTrue);
    expect(platform.maxConcurrentPlaybackCommands, 1);

    platform.delayPlaybackCommands = false;
    await _disposeBackdrop(tester);
  });

  testWidgets('pauses while another route covers it and resumes on return', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await _pumpInitialized(tester, _app(navigatorKey: navigatorKey));
    platform.calls.clear();

    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(builder: (_) => const SizedBox.expand()),
      ),
    );
    await tester.pump();
    expect(platform.calls, contains('pause'));
    expect(
      find.byType(VideoPlayer),
      findsOneWidget,
      reason: 'The outgoing route retains the paused video frame.',
    );
    await tester.pumpAndSettle();
    expect(platform.calls, contains('pause'));
    expect(find.byType(VideoPlayer), findsNothing);

    platform.calls.clear();
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(platform.calls, contains('play'));
    expect(find.byType(VideoPlayer), findsOneWidget);

    await _disposeBackdrop(tester);
  });

  testWidgets('disposes the native player with the widget', (tester) async {
    await _pumpInitialized(tester, _app());
    platform.calls.clear();

    await _disposeBackdrop(tester);

    expect(platform.calls, contains('dispose'));
  });
}
