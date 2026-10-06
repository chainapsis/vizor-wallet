import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// video_player exposes its platform interface through a transitive package;
// importing it here lets the widget test detect accidental native startup.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/welcome_video_backdrop.dart';
import 'package:zcash_wallet/src/features/onboarding/welcome.dart';

class _CountingVideoPlayerPlatform extends VideoPlayerPlatform {
  var createCalls = 0;

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    createCalls++;
    return 1;
  }
}

Widget _app({bool animate = true, bool disableAnimations = false}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: Scaffold(
      body: WelcomeVideoBackdrop(
        videoAsset: kDesktopWelcomeVideoAsset,
        posterAsset: kDesktopWelcomePosterAsset,
        animatedImageAsset: kDesktopWelcomeAnimatedImageAsset,
        animate: animate,
      ),
    ),
  );
}

Finder _assetImage(String assetName, {bool skipOffstage = true}) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName == assetName,
    skipOffstage: skipOffstage,
  );
}

TickerMode _animatedImageTicker(WidgetTester tester) {
  return tester.widget<TickerMode>(
    find.byWidgetPredicate(
      (widget) =>
          widget is TickerMode &&
          widget.child is Image &&
          (widget.child as Image).image is AssetImage &&
          ((widget.child as Image).image as AssetImage).assetName ==
              kDesktopWelcomeAnimatedImageAsset,
      skipOffstage: false,
    ),
  );
}

Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoPlayerPlatform originalVideoPlatform;
  late _CountingVideoPlayerPlatform videoPlatform;

  setUp(() {
    originalVideoPlatform = VideoPlayerPlatform.instance;
    videoPlatform = _CountingVideoPlayerPlatform();
    VideoPlayerPlatform.instance = videoPlatform;
  });

  tearDown(() {
    VideoPlayerPlatform.instance = originalVideoPlatform;
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets('$platform uses animated WebP without creating native video', (
      tester,
    ) async {
      await _withPlatform(platform, () async {
        await tester.pumpWidget(_app());
        await tester.pump();

        expect(videoPlatform.createCalls, 0);
        expect(_assetImage(kDesktopWelcomeAnimatedImageAsset), findsOneWidget);
        expect(_animatedImageTicker(tester).enabled, isTrue);
      });
    });
  }

  testWidgets('animated WebP pauses and resumes with app lifecycle', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.windows, () async {
      await tester.pumpWidget(_app());

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(_animatedImageTicker(tester).enabled, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_animatedImageTicker(tester).enabled, isTrue);
    });
  });

  testWidgets('animated WebP retains its paused frame under another route', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.linux, () async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(body: _app()),
        ),
      );

      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(builder: (_) => const SizedBox.expand()),
      );
      await tester.pumpAndSettle();

      expect(
        _assetImage(kDesktopWelcomeAnimatedImageAsset, skipOffstage: false),
        findsOneWidget,
      );
      expect(_animatedImageTicker(tester).enabled, isFalse);
    });
  });

  testWidgets('disabled and reduced motion modes keep the poster', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.windows, () async {
      await tester.pumpWidget(_app(animate: false));
      expect(_assetImage(kDesktopWelcomeAnimatedImageAsset), findsNothing);
      expect(_assetImage(kDesktopWelcomePosterAsset), findsOneWidget);

      await tester.pumpWidget(_app(disableAnimations: true));
      expect(_assetImage(kDesktopWelcomeAnimatedImageAsset), findsNothing);
      expect(_assetImage(kDesktopWelcomePosterAsset), findsOneWidget);
      expect(videoPlatform.createCalls, 0);
    });
  });

  test('animated WebP preserves source frame count and loop timing', () async {
    final data = await rootBundle.load(kDesktopWelcomeAnimatedImageAsset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    addTearDown(codec.dispose);

    expect(codec.frameCount, 85);
    expect(codec.repetitionCount, -1);

    var loopDuration = Duration.zero;
    for (var index = 0; index < codec.frameCount; index++) {
      final frame = await codec.getNextFrame();
      loopDuration += frame.duration;
      frame.image.dispose();
    }
    expect(loopDuration, const Duration(milliseconds: 3542));
  });
}
