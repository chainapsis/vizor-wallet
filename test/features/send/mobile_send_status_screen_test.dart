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
import 'package:zcash_wallet/src/rust/frb_generated.dart';

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

/// The "safe to leave this receipt" flag the payment-URI drain reads.
bool _sendStatusTerminal(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
    listen: false,
  ).read(sendStatusTerminalProvider);
}

bool _statusRouteCanPop(WidgetTester tester) {
  final popScope = tester.widget<PopScope<void>>(find.byType(PopScope<void>));
  return popScope.canPop;
}

/// Rust stand-in for the one call the receipt makes on its own: releasing a
/// proposal the broadcast did not consume.
class _RustApiFake implements RustLibApi {
  final discardCalls = <(BigInt, String)>[];

  /// Holds `discardProposal` open so a test can read the terminal flag while
  /// the release is still in flight.
  Completer<void>? discardGate;

  /// How many more `discardProposal` calls fail before one succeeds.
  int discardFailuresRemaining = 0;

  @override
  Future<void> crateApiSyncDiscardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {
    discardCalls.add((proposalId, sendFlowId));
    final gate = discardGate;
    if (gate != null) await gate.future;
    if (discardFailuresRemaining > 0) {
      discardFailuresRemaining--;
      throw Exception('transient wallet DB unlock failure');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _RustApiFake rustApi;

  setUpAll(() {
    rustApi = _RustApiFake();
    RustLib.initMock(api: rustApi);
  });
  tearDownAll(RustLib.dispose);

  setUp(() {
    rustApi.discardCalls.clear();
    rustApi.discardGate = null;
    rustApi.discardFailuresRemaining = 0;
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
    expect(_sendStatusTerminal(tester), isFalse);
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
    expect(_sendStatusTerminal(tester), isTrue);
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
    // A pending broadcast still renders as in progress, so it is not terminal.
    expect(_sendStatusTerminal(tester), isFalse);
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
    expect(_sendStatusTerminal(tester), isTrue);
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

  testWidgets(
    'failed outcome releases an unconsumed proposal before going terminal',
    (tester) async {
      // The software send's missing-mnemonic branch: the broadcast fails and
      // Rust still owns the proposal. It is `!Platform.isMacOS`-only in
      // `runSendBroadcast`, so the outcome is injected rather than provoked.
      final discardGate = Completer<void>();
      rustApi.discardGate = discardGate;

      final broadcast = Completer<SendBroadcastOutcome>();
      await tester.pumpWidget(_app(broadcastRunner: _runner(broadcast.future)));
      await tester.pump();

      broadcast.complete(
        const SendBroadcastOutcome(
          phase: SendBroadcastPhase.failed,
          proposalConsumed: false,
          error: 'Mnemonic not found for the proposal account.',
        ),
      );
      await tester.pump();
      await tester.pump();

      // The receipt already reads as failed, but the proposal — and with it
      // the input lock a parked `zcash:` request would propose against — is
      // still held, so the drain must not be told the send is safe to leave.
      expect(find.text('Send failed'), findsOneWidget);
      expect(rustApi.discardCalls, [(BigInt.one, 'flow-1')]);
      expect(_sendStatusTerminal(tester), isFalse);

      discardGate.complete();
      await tester.pump();
      await tester.pump();

      expect(_sendStatusTerminal(tester), isTrue);

      // Leaving the receipt must not release the proposal a second time.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(rustApi.discardCalls, hasLength(1));
    },
  );

  testWidgets('leaving a failed receipt mid-release delays the drain until the '
      'proposal is free', (tester) async {
    final discardGate = Completer<void>();
    rustApi.discardGate = discardGate;

    // The test owns the container so the flag outlives the receipt; a
    // `ProviderScope` widget would dispose it together with the screen.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final broadcast = Completer<SendBroadcastOutcome>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: MobileSendStatusScreen(
              args: _args,
              broadcastRunner: _runner(broadcast.future),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    broadcast.complete(
      const SendBroadcastOutcome(
        phase: SendBroadcastPhase.failed,
        proposalConsumed: false,
        error: 'Mnemonic not found for the proposal account.',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Send failed'), findsOneWidget);
    expect(container.read(sendStatusTerminalProvider), isFalse);

    final published = <bool>[];
    container.listen<bool>(
      sendStatusTerminalProvider,
      (_, next) => published.add(next),
    );

    // Back is allowed on a failed receipt; the user leaves while Rust is
    // still releasing the proposal.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    await tester.pump();
    expect(
      published,
      isEmpty,
      reason:
          'publishing terminal here would drain a parked request against '
          'inputs the dead send still locks',
    );

    discardGate.complete();
    await tester.pump();
    await tester.pump();

    expect(published, [true, false]);
    expect(rustApi.discardCalls, hasLength(1));
  });

  testWidgets('a release Rust never confirms keeps the failed receipt '
      'non-terminal', (tester) async {
    rustApi.discardFailuresRemaining = 3;

    final broadcast = Completer<SendBroadcastOutcome>();
    await tester.pumpWidget(_app(broadcastRunner: _runner(broadcast.future)));
    await tester.pump();
    broadcast.complete(
      const SendBroadcastOutcome(
        phase: SendBroadcastPhase.failed,
        proposalConsumed: false,
        error: 'Mnemonic not found for the proposal account.',
      ),
    );
    await tester.pump();
    // The retries back off 100 ms, then 200 ms.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Send failed'), findsOneWidget);
    expect(rustApi.discardCalls, hasLength(3));
    expect(_sendStatusTerminal(tester), isFalse);
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
