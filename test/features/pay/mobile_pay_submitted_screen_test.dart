@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/mobile_transaction_progress_screen.dart';
import 'package:zcash_wallet/src/features/pay/screens/mobile/mobile_pay_submitted_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_deposit_broadcast_result.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';

Future<void> _setMobileViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

GoRouter _router(AppThemeData theme) {
  return GoRouter(
    initialLocation: '/pay/submitted/intent-1',
    routes: [
      GoRoute(
        path: '/pay/submitted/:intentId',
        builder: (context, state) => AppTheme(
          data: theme,
          child: MobilePaySubmittedScreen(
            intentId: state.pathParameters['intentId']!,
          ),
        ),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home')),
      GoRoute(path: '/activity', builder: (_, _) => const Text('activity')),
      GoRoute(
        path: '/activity/swap/:intentId',
        builder: (_, state) => Text(
          'activity:${state.pathParameters['intentId']}:${state.uri.queryParameters['from']}',
        ),
      ),
    ],
  );
}

void main() {
  test('maps only confirmed or legacy deposit hashes to submitted', () {
    final submitted = mobilePayDepositProgressFor(
      state: _state(
        intent: _intent(
          depositTxHash: 'txid-1',
          broadcastStatus: SwapDepositBroadcastStatus.broadcasted,
        ),
      ),
      intentId: 'intent-1',
    );
    final legacy = mobilePayDepositProgressFor(
      state: _state(intent: _intent(depositTxHash: 'legacy-txid')),
      intentId: 'intent-1',
    );

    expect(submitted.phase, MobileTransactionProgressPhase.succeeded);
    expect(legacy.phase, MobileTransactionProgressPhase.succeeded);
  });

  test('maps provider-observed deposits to submitted after restore', () {
    final providerHash = mobilePayDepositProgressFor(
      state: _state(
        intent: _intent(
          status: SwapIntentStatus.failed,
          originChainTxHash: 'provider-origin-txid',
        ),
      ),
      intentId: 'intent-1',
    );
    final providerAmount = mobilePayDepositProgressFor(
      state: _state(
        intent: _intent(
          status: SwapIntentStatus.failed,
          providerRefundInfo: const SwapProviderRefundInfo(
            depositedAmountText: '0.025 ZEC',
          ),
        ),
      ),
      intentId: 'intent-1',
    );
    final observedStatus = mobilePayDepositProgressFor(
      state: _state(intent: _intent(status: SwapIntentStatus.depositObserved)),
      intentId: 'intent-1',
    );

    expect(providerHash.phase, MobileTransactionProgressPhase.succeeded);
    expect(providerAmount.phase, MobileTransactionProgressPhase.succeeded);
    expect(observedStatus.phase, MobileTransactionProgressPhase.succeeded);
  });

  test('maps uncertain broadcast outcomes without claiming success', () {
    for (final status in [
      SwapDepositBroadcastStatus.pendingBroadcast,
      SwapDepositBroadcastStatus.partialBroadcast,
      SwapDepositBroadcastStatus.broadcastUnknown,
      SwapDepositBroadcastStatus.broadcastedStorageFailed,
    ]) {
      final progress = mobilePayDepositProgressFor(
        state: _state(
          intent: _intent(
            depositTxHash: 'txid-1',
            broadcastStatus: status,
            broadcastNotice: 'Check activity before trying again.',
          ),
        ),
        intentId: 'intent-1',
      );

      expect(
        progress.phase,
        MobileTransactionProgressPhase.pending,
        reason: status,
      );
      expect(progress.notice, 'Check activity before trying again.');
    }
  });

  test('maps relevant submission and pre-broadcast failure states', () {
    final submitting = mobilePayDepositProgressFor(
      state: _state(intent: _intent(), depositSubmitting: true),
      intentId: 'intent-1',
    );
    final failed = mobilePayDepositProgressFor(
      state: _state(intent: _intent(), statusError: 'Deposit failed.'),
      intentId: 'intent-1',
    );
    final unrelatedFailure = mobilePayDepositProgressFor(
      state: _state(
        intent: _intent(),
        selectedIntentId: 'another-intent',
        statusError: 'Another deposit failed.',
      ),
      intentId: 'intent-1',
    );

    expect(submitting.phase, MobileTransactionProgressPhase.inProgress);
    expect(failed.phase, MobileTransactionProgressPhase.failed);
    expect(failed.notice, 'Deposit failed.');
    expect(unrelatedFailure.phase, MobileTransactionProgressPhase.inProgress);
  });

  testWidgets('renders the Figma payment submitted state', (tester) async {
    await _setMobileViewport(tester);
    final state = _state(
      intent: _intent(
        depositTxHash: 'txid-1',
        broadcastStatus: SwapDepositBroadcastStatus.broadcasted,
      ),
    );
    final router = _router(AppThemeData.light);
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router, state));
    await tester.pump();

    expect(find.text('Payment\nSubmitted'), findsOneWidget);
    expect(
      find.text('It will confirm on-chain shortly.\nTrack it in Activity.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('pay_submitted_status')), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Go to activity'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/illustrations/mobile_send_status_background.png',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the payment activity for the started intent', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    final state = _state(
      intent: _intent(
        depositTxHash: 'txid-1',
        broadcastStatus: SwapDepositBroadcastStatus.broadcasted,
      ),
    );
    final router = _router(AppThemeData.dark);
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router, state));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pay_submitted_activity')));
    await tester.pumpAndSettle();

    expect(find.text('activity:intent-1:pay'), findsOneWidget);
  });

  testWidgets('shows progress without exit actions before a deposit hash', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    final state = _state(intent: _intent(), depositSubmitting: true);
    final router = _router(AppThemeData.light);
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router, state));
    await tester.pump();

    expect(find.text('Submitting payment...'), findsOneWidget);
    expect(find.byKey(const ValueKey('pay_submitted_done')), findsNothing);
    expect(find.byKey(const ValueKey('pay_submitted_activity')), findsNothing);
    expect(
      tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
      isFalse,
    );

    await tester.pump(kMobilePayIntentRestoreGrace);
    await tester.pump();

    expect(find.text('Submitting payment...'), findsOneWidget);
    expect(find.byKey(const ValueKey('pay_submitted_done')), findsNothing);
    expect(
      tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
      isFalse,
    );
  });

  testWidgets('missing intent releases the restoring screen after a grace', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    final state = _state();
    final router = _router(AppThemeData.light);
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router, state));
    await tester.pump();

    expect(find.text('Submitting payment...'), findsOneWidget);
    expect(find.byKey(const ValueKey('pay_submitted_done')), findsNothing);

    await tester.pump(kMobilePayIntentRestoreGrace);
    await tester.pump();

    expect(find.text('Payment unavailable'), findsOneWidget);
    expect(find.text('Return home'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pay_submitted_activity')),
      findsOneWidget,
    );
    expect(
      tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('pay_submitted_activity')));
    await tester.pumpAndSettle();
    expect(find.text('activity'), findsOneWidget);
  });

  testWidgets(
    'restored inactive intent becomes uncertain after the restore grace',
    (tester) async {
      await _setMobileViewport(tester);
      final state = _state(intent: _intent());
      final router = _router(AppThemeData.light);
      addTearDown(router.dispose);

      await tester.pumpWidget(_app(router, state));
      await tester.pump();

      expect(find.text('Submitting payment...'), findsOneWidget);
      expect(find.byKey(const ValueKey('pay_submitted_done')), findsNothing);
      expect(
        tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
        isFalse,
      );

      await tester.pump(kMobilePayIntentRestoreGrace);
      await tester.pump();

      expect(find.text('Payment status\nuncertain'), findsOneWidget);
      expect(find.byKey(const ValueKey('pay_submitted_done')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pay_submitted_activity')),
        findsOneWidget,
      );
      expect(
        tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('pay_submitted_activity')));
      await tester.pumpAndSettle();
      expect(find.text('activity:intent-1:pay'), findsOneWidget);
    },
  );

  testWidgets('uncertain broadcast shows its notice and Activity action', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    final state = _state(
      intent: _intent(
        depositTxHash: 'txid-1',
        broadcastStatus: SwapDepositBroadcastStatus.broadcastUnknown,
        broadcastNotice: 'Check Activity before trying again.',
      ),
    );
    final router = _router(AppThemeData.light);
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router, state));
    await tester.pump();

    expect(find.text('Payment status\nuncertain'), findsOneWidget);
    expect(find.text('Check Activity before trying again.'), findsOneWidget);
    expect(find.byKey(const ValueKey('pay_submitted_done')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pay_submitted_activity')),
      findsOneWidget,
    );
  });

  testWidgets(
    'pre-broadcast failure offers Return home without claiming sent',
    (tester) async {
      await _setMobileViewport(tester);
      final state = _state(
        intent: _intent(),
        statusError: 'The deposit could not be sent.',
      );
      final router = _router(AppThemeData.light);
      addTearDown(router.dispose);

      await tester.pumpWidget(_app(router, state));
      await tester.pump();

      expect(find.text('Payment failed'), findsOneWidget);
      expect(find.text('The deposit could not be sent.'), findsOneWidget);
      expect(find.text('Payment\nSubmitted'), findsNothing);
      expect(find.text('Return home'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pay_submitted_activity')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('pay_submitted_done')));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    },
  );
}

Widget _app(GoRouter router, SwapState state) {
  return ProviderScope(
    overrides: [
      swapStateProvider.overrideWith(() => _PayStatusNotifier(state)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

SwapState _state({
  SwapIntent? intent,
  bool depositSubmitting = false,
  String? statusError,
  String? selectedIntentId = 'intent-1',
}) {
  return SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [?intent],
    selectedIntentId: selectedIntentId,
    depositSubmitting: depositSubmitting,
    statusError: statusError,
    payMode: true,
  );
}

SwapIntent _intent({
  String? depositTxHash,
  String? broadcastStatus,
  String? broadcastNotice,
  String? statusError,
  SwapIntentStatus status = SwapIntentStatus.awaitingDeposit,
  String? originChainTxHash,
  SwapProviderRefundInfo? providerRefundInfo,
}) {
  return SwapIntent(
    id: 'intent-1',
    pair: 'ZEC -> USDC',
    sellAmount: '0.025 ZEC',
    receiveEstimate: '10 USDC',
    provider: 'NEAR Intents',
    status: status,
    nextAction: 'Submit deposit',
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositTxHash: depositTxHash,
    originChainTxHash: originChainTxHash,
    providerRefundInfo: providerRefundInfo,
    broadcastStatus: broadcastStatus,
    broadcastNotice: broadcastNotice,
    statusError: statusError,
    payMode: true,
  );
}

class _PayStatusNotifier extends SwapNotifier {
  _PayStatusNotifier(this.initialState);

  final SwapState initialState;

  @override
  SwapState build() => initialState;
}
