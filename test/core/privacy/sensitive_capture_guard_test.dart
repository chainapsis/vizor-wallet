import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/privacy/native_sensitive_content_bridge.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_capture_guard.dart';

void main() {
  const channel = MethodChannel('com.zcash.wallet/privacy_shield');
  final supported = Platform.isMacOS || Platform.isAndroid || Platform.isIOS;
  final calls = <bool>[];

  setUp(() {
    NativeSensitiveContentBridge.resetForTesting();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final visible = (call.arguments as Map)['visible'] as bool;
          calls.add(visible);
          return {
            'visible': visible,
            'state': visible ? 'applied' : 'disabled',
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    NativeSensitiveContentBridge.resetForTesting();
  });

  testWidgets('only the final sensitive guard can release capture exclusion', (
    tester,
  ) async {
    Widget app({required bool first, required bool second}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          if (first)
            const SensitiveCaptureGuard(
              key: ValueKey('first'),
              sensitiveContentVisible: true,
              child: Text('first secret'),
            ),
          if (second)
            const SensitiveCaptureGuard(
              key: ValueKey('second'),
              sensitiveContentVisible: true,
              child: Text('second secret'),
            ),
        ],
      ),
    );
    await tester.pumpWidget(app(first: true, second: true));
    expect(calls, [true]);
    await tester.pumpWidget(app(first: false, second: true));
    expect(calls, [true]);
    await tester.pumpWidget(app(first: false, second: false));
    expect(calls, [true, false]);
  }, skip: !supported);

  testWidgets('background transitions do not release sensitive capture policy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SensitiveCaptureGuard(
          sensitiveContentVisible: true,
          child: Text('secret'),
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(calls, [true]);
    // The native window owns the cover; the guard has no local blur/lifecycle UI.
    expect(find.text('secret'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, [true]);
    await tester.pumpWidget(const SizedBox());
    expect(calls, [true, false]);
  }, skip: !supported);
}
