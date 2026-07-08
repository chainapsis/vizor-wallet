@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_status_screen.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';

const _address =
    'u1l8xunezsvhq8fgzfl7404m450nwnd76zshe7f5dxv5z3w4gthawuwukdn5aalh6g'
    '5wfshmrjmd5gh';

final _args = SendReviewArgs(
  proposalId: BigInt.from(1),
  sendFlowId: 'flow-1',
  proposalAccountUuid: 'account-1',
  address: _address,
  addressType: 'unified',
  amountZatoshi: BigInt.from(12312000000),
  feeZatoshi: BigInt.from(15000),
  needsSaplingParams: false,
  memo: 'thanks!',
);

MobileSendBroadcastRunner _runner(Future<SendBroadcastOutcome> outcome) {
  return ({
    required ref,
    required args,
    keystone,
    required confirmSaplingParamsDownload,
    shouldAbort,
  }) => outcome;
}

Widget _app({required MobileSendBroadcastRunner broadcastRunner}) {
  return ProviderScope(
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: MobileSendStatusScreen(
          args: _args,
          broadcastRunner: broadcastRunner,
        ),
      ),
    ),
  );
}

bool _statusRouteCanPop(WidgetTester tester) {
  final popScope = tester.widget<PopScope<void>>(find.byType(PopScope<void>));
  return popScope.canPop;
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('sending phase shows the spinner state with no exit button', (
    tester,
  ) async {
    final broadcast = Completer<SendBroadcastOutcome>();
    await tester.pumpWidget(_app(broadcastRunner: _runner(broadcast.future)));
    await tester.pump();

    expect(find.byKey(const ValueKey('mobile_send_status_sending')), findsOne);
    expect(find.text('Sending...'), findsOneWidget);
    expect(
      find.text('Submitting your transaction to the network...'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_send_status_icon_loader')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_send_status_button')),
      findsNothing,
    );
    expect(_statusRouteCanPop(tester), isFalse);
  });

  testWidgets('broadcast success shows the complete state with custom haptic', (
    tester,
  ) async {
    final platformHaptics = <Object?>[];
    final nativeHaptics = <String>[];
    const hapticsChannel = MethodChannel('com.zcash.wallet/haptics');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      hapticsChannel,
      (call) async {
        nativeHaptics.add(call.method);
        return true;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          platformHaptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        hapticsChannel,
        null,
      );
    });

    final broadcast = Completer<SendBroadcastOutcome>();
    await tester.pumpWidget(_app(broadcastRunner: _runner(broadcast.future)));
    await tester.pump();

    broadcast.complete(
      const SendBroadcastOutcome(
        phase: SendBroadcastPhase.succeeded,
        proposalConsumed: true,
        txid: 'txid-1',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mobile_send_status_succeeded')),
      findsOne,
    );
    expect(find.text('Sent!'), findsOneWidget);
    expect(
      find.text('It will confirm on-chain shortly. Track it in Activity.'),
      findsOneWidget,
    );
    expect(find.text('Done'), findsOneWidget);
    expect(_statusRouteCanPop(tester), isTrue);
    expect(nativeHaptics, ['sendSuccess']);
    expect(platformHaptics, isEmpty);

    // Ripple + icon crossfade are finite; the succeeded state settles.
    await tester.pumpAndSettle();
    expect(platformHaptics, isEmpty);
    expect(
      find.byKey(const ValueKey('mobile_send_status_icon_success')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_send_status_success_ripple')),
      findsNothing,
    );
  });

  testWidgets('pending broadcast keeps the spinner and shows the retry copy', (
    tester,
  ) async {
    final broadcast = Completer<SendBroadcastOutcome>();
    await tester.pumpWidget(_app(broadcastRunner: _runner(broadcast.future)));
    await tester.pump();

    broadcast.complete(
      const SendBroadcastOutcome(
        phase: SendBroadcastPhase.pendingBroadcast,
        proposalConsumed: true,
        txid: 'txid-1',
        statusMessage: 'It will retry automatically.',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mobile_send_status_pendingBroadcast')),
      findsOne,
    );
    expect(find.text('Queued to send'), findsOneWidget);
    expect(find.text('It will retry automatically.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_send_status_icon_loader')),
      findsOneWidget,
    );
    expect(find.text('Done'), findsOneWidget);
    expect(_statusRouteCanPop(tester), isTrue);
  });

  testWidgets('pending broadcast falls back to the generic retry copy', (
    tester,
  ) async {
    final broadcast = Completer<SendBroadcastOutcome>();
    await tester.pumpWidget(_app(broadcastRunner: _runner(broadcast.future)));
    await tester.pump();

    broadcast.complete(
      const SendBroadcastOutcome(
        phase: SendBroadcastPhase.pendingBroadcast,
        proposalConsumed: true,
        txid: 'txid-1',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Queued to send'), findsOneWidget);
    final subtitleFinder = find.textContaining(
      'will be submitted automatically',
    );
    expect(subtitleFinder, findsOneWidget);
    expect(tester.getSize(subtitleFinder).width, greaterThan(300));
  });

  testWidgets('broadcast failure shows the failed state with custom haptic', (
    tester,
  ) async {
    final platformHaptics = <Object?>[];
    final nativeHaptics = <String>[];
    const hapticsChannel = MethodChannel('com.zcash.wallet/haptics');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      hapticsChannel,
      (call) async {
        nativeHaptics.add(call.method);
        return true;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          platformHaptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        hapticsChannel,
        null,
      );
    });

    final broadcast = Completer<SendBroadcastOutcome>();
    await tester.pumpWidget(_app(broadcastRunner: _runner(broadcast.future)));
    await tester.pump();

    expect(_statusRouteCanPop(tester), isFalse);

    broadcast.complete(
      const SendBroadcastOutcome(
        phase: SendBroadcastPhase.failed,
        proposalConsumed: true,
        error: 'failed',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('mobile_send_status_failed')), findsOne);
    expect(find.text('Send failed'), findsOneWidget);
    expect(
      find.text("Nothing was sent, your funds haven't moved. Try again."),
      findsOneWidget,
    );
    expect(find.text('Return home'), findsOneWidget);
    expect(_statusRouteCanPop(tester), isTrue);
    expect(nativeHaptics, ['sendFailure']);
    expect(platformHaptics, isEmpty);

    // Shake + icon crossfade are finite; the failed state settles.
    await tester.pumpAndSettle();
    expect(platformHaptics, isEmpty);
    expect(
      find.byKey(const ValueKey('mobile_send_status_icon_failed')),
      findsOneWidget,
    );
  });

  testWidgets('send success falls back to Flutter haptics on Android', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    final platformHaptics = <Object?>[];
    const hapticsChannel = MethodChannel('com.zcash.wallet/haptics');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      hapticsChannel,
      (_) async => false,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          platformHaptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        hapticsChannel,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final broadcast = Completer<SendBroadcastOutcome>();
    await tester.pumpWidget(_app(broadcastRunner: _runner(broadcast.future)));
    await tester.pump();

    broadcast.complete(
      const SendBroadcastOutcome(
        phase: SendBroadcastPhase.succeeded,
        proposalConsumed: true,
        txid: 'txid-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      platformHaptics,
      containsAllInOrder([
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.selectionClick',
      ]),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('send failure falls back to Flutter haptics on Android', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    final platformHaptics = <Object?>[];
    const hapticsChannel = MethodChannel('com.zcash.wallet/haptics');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      hapticsChannel,
      (_) async => false,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          platformHaptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        hapticsChannel,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final broadcast = Completer<SendBroadcastOutcome>();
    await tester.pumpWidget(_app(broadcastRunner: _runner(broadcast.future)));
    await tester.pump();

    broadcast.complete(
      const SendBroadcastOutcome(
        phase: SendBroadcastPhase.failed,
        proposalConsumed: true,
        error: 'failed',
      ),
    );
    await tester.pumpAndSettle();

    expect(platformHaptics, contains('HapticFeedbackType.lightImpact'));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Done pops the status route back to home', (tester) async {
    final broadcast = Completer<SendBroadcastOutcome>();
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => const Text('home-screen'),
        ),
        GoRoute(
          path: '/send/status',
          builder: (context, state) => MobileSendStatusScreen(
            args: _args,
            broadcastRunner: _runner(broadcast.future),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Mirror production: `/send/status` is pushed on top of `/home`.
    unawaited(router.push<void>('/send/status'));
    await tester.pump();
    await tester.pump();

    broadcast.complete(
      const SendBroadcastOutcome(
        phase: SendBroadcastPhase.succeeded,
        proposalConsumed: true,
        txid: 'txid-1',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('home-screen'), findsOneWidget);
  });
}
