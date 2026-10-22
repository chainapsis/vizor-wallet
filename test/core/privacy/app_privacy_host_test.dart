import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/privacy/app_privacy_host.dart';
import 'package:zcash_wallet/src/core/privacy/native_sensitive_content_bridge.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_capture_guard.dart';

void main() {
  const channel = MethodChannel('com.zcash.wallet/app_privacy');
  const captureChannel = MethodChannel('com.zcash.wallet/privacy_shield');
  final modes = <bool>[];
  final captures = <bool>[];
  Future<void> rasterize(WidgetTester tester) async {
    await tester.pump();
    final stamp = tester.binding.currentSystemFrameTimeStamp.inMicroseconds;
    tester.binding.platformDispatcher.onReportTimings?.call([
      FrameTiming(
        vsyncStart: stamp,
        buildStart: stamp,
        buildFinish: stamp + 1,
        rasterStart: stamp + 2,
        rasterFinish: stamp + 3,
        rasterFinishWallTime: stamp + 3,
      ),
    ]);
    await tester.pump();
  }

  void testPolicy(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  setUp(() {
    AppPrivacyPolicy.resetForTesting();
    NativeSensitiveContentBridge.resetForTesting();
    modes.clear();
    captures.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          modes.add((call.arguments as Map)['solid'] as bool);
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(captureChannel, (call) async {
          captures.add((call.arguments as Map)['visible'] as bool);
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    AppPrivacyPolicy.resetForTesting();
    NativeSensitiveContentBridge.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(captureChannel, null);
  });

  testPolicy('ordinary app stays solid until an ordinary frame is rasterized', (
    tester,
  ) async {
    await tester.pumpWidget(const AppPrivacyHost(child: SizedBox()));
    expect(modes, [true]);
    await rasterize(tester);
    expect(modes, [true, false]);
    await tester.pumpWidget(const SizedBox());
    expect(modes, [true, false, true]);
  });

  testPolicy('hidden secrets keep solid without blocking foreground capture', (
    tester,
  ) async {
    await tester.pumpWidget(
      const AppPrivacyHost(
        child: SensitiveCaptureGuard(
          sensitiveContentVisible: false,
          child: SizedBox(),
        ),
      ),
    );
    expect(modes, [true]);
    expect(captures, isEmpty);
  });

  testPolicy('only the final solid scope can restore blur', (tester) async {
    Widget app(bool first, bool second) => AppPrivacyHost(
      child: Column(
        children: [
          if (first)
            const SensitiveCaptureGuard(
              key: ValueKey('first'),
              sensitiveContentVisible: false,
              child: SizedBox(),
            ),
          if (second)
            const SensitiveCaptureGuard(
              key: ValueKey('second'),
              sensitiveContentVisible: false,
              child: SizedBox(),
            ),
        ],
      ),
    );
    await tester.pumpWidget(app(true, true));
    await tester.pumpWidget(app(false, true));
    expect(modes, [true]);
    await tester.pumpWidget(app(false, false));
    expect(modes, [true]);
    await rasterize(tester);
    expect(modes, [true, false]);
  });

  testPolicy(
    'solid survives push and pop until the sensitive route is covered',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        AppPrivacyHost(
          child: MaterialApp(
            navigatorKey: navigator,
            home: const SensitiveCaptureGuard(
              sensitiveContentVisible: false,
              child: Scaffold(body: Text('hidden secret')),
            ),
          ),
        ),
      );
      expect(modes, [true]);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('ordinary')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(modes, [true]);
      await tester.pumpAndSettle();
      expect(modes.last, true);
      await rasterize(tester);
      expect(modes.last, false);
      navigator.currentState!.pop();
      await tester.pump();
      expect(modes.last, true);
      await tester.pumpAndSettle();
      expect(modes.last, true);
    },
  );

  testPolicy('a translucent page cannot release the visible secret scope', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      AppPrivacyHost(
        child: MaterialApp(
          navigatorKey: navigator,
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => const SensitiveCaptureGuard(
              sensitiveContentVisible: false,
              child: Scaffold(body: Text('secret scope')),
            ),
          ),
        ),
      ),
    );
    navigator.currentState!.push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, _, _) => const Center(child: Text('translucent')),
      ),
    );
    await tester.pumpAndSettle();
    await rasterize(tester);
    expect(modes.last, true);
  });

  testPolicy('disposing and replacing a scope in one frame cannot flash blur', (
    tester,
  ) async {
    Widget app(String key) => AppPrivacyHost(
      child: SensitiveCaptureGuard(
        key: ValueKey(key),
        sensitiveContentVisible: false,
        child: const SizedBox(),
      ),
    );
    await tester.pumpWidget(app('outgoing'));
    await tester.pumpWidget(app('incoming'));
    expect(modes, [true]);
  });
}
