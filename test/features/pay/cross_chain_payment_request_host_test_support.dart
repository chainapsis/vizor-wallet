import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/payments/cross_chain_payment_request.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/pay/providers/cross_chain_payment_request_provider.dart';
import 'package:zcash_wallet/src/features/pay/screens/mobile/mobile_pay_screen.dart';
import 'package:zcash_wallet/src/features/pay/screens/pay_screen.dart';
import 'package:zcash_wallet/src/features/pay/widgets/cross_chain_payment_request_host.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_navigation.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/pay_selected_asset_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_composer_preferences_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_zec_staging_address_service.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_review_screen.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_asset_icon.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_slippage_stepper_modal.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_slippage_modal.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../figma_compare/figma_compare_font_loader.dart';

const _recipient = '0x52908400098527886E0F7030069857D2E4169EE7';
const _contract = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const _continueKey = ValueKey('cross_chain_payment_request_continue');
const _cancelKey = ValueKey('cross_chain_payment_request_cancel');
const _editKey = ValueKey('cross_chain_payment_request_edit');
const _slippageKey = ValueKey('cross_chain_payment_request_slippage');
const _account = AccountState(
  accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
  activeAccountUuid: 'account-1',
);
final _usdc = SwapAsset.live(
  assetId: 'live-base-usdc',
  symbol: 'USDC',
  blockchain: 'base',
  decimals: 6,
  contractAddress: _contract,
);
final _btc = SwapAsset.live(
  assetId: 'live-btc',
  symbol: 'BTC',
  blockchain: 'btc',
  decimals: 8,
);

void runCrossChainPaymentRequestHostTests({required bool isMobile}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFigmaCompareFonts);
  testWidgets('request slippage is staged and applied to the review quote', (
    tester,
  ) async {
    final harness = await _readyHarness(
      tester,
      isMobile: isMobile,
      holdQuotes: true,
    );
    final original = _composerValues(harness.state);
    final originalSlippage = harness.state.slippageBps;
    await tester.tap(find.byKey(_slippageKey));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Allows this much extra ZEC for quote movement before execution fails. Network fees are separate.',
      ),
      findsOneWidget,
    );
    await _captureHost(tester, isMobile: isMobile, state: 'slippage');
    await _enterSlippage(tester, isMobile: isMobile, value: '1.25');
    await tester.tap(find.byKey(const ValueKey('swap_slippage_update_button')));
    await tester.pumpAndSettle();
    expect(find.text('1.25%'), findsOneWidget);
    expect(
      harness.container.read(crossChainPaymentFlowProvider)?.slippageBps,
      125,
    );
    expect(harness.state.slippageBps, originalSlippage);
    expect(_composerValues(harness.state), original);
    expect(harness.provider.quoteCalls, 0);
    await _captureHost(tester, isMobile: isMobile, state: 'slippage-selected');

    await tester.tap(find.byKey(_continueKey));
    await tester.pump();
    await tester.pump();
    expect(harness.provider.requests.single.slippageBps, 125);
    expect(
      tester.widget<AppButton>(find.byKey(_slippageKey)).onPressed,
      isNull,
    );
    harness.container
        .read(crossChainPaymentFlowProvider.notifier)
        .chooseSlippage(250);
    expect(
      harness.container.read(crossChainPaymentFlowProvider)?.slippageBps,
      125,
    );
    harness.provider.completeQuote(0);
    await tester.pumpAndSettle();
    expect(harness.state.slippageBps, 125);
    expect(harness.state.reviewVisible, isTrue);
    expect(harness.location, isMobile ? '/pay/review' : '/pay');
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets(
    'cancelling settings or the request preserves existing slippage',
    (tester) async {
      final harness = await _readyHarness(tester, isMobile: isMobile);
      final originalSlippage = harness.state.slippageBps;
      await tester.tap(find.byKey(_slippageKey));
      await tester.pumpAndSettle();
      await _enterSlippage(tester, isMobile: isMobile, value: '2');
      await tester.tap(
        find.byKey(const ValueKey('swap_slippage_cancel_button')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_slippageKey), findsOneWidget);
      expect(
        harness.container.read(crossChainPaymentFlowProvider)?.slippageBps,
        isNull,
      );

      await tester.tap(find.byKey(_slippageKey));
      await tester.pumpAndSettle();
      await _enterSlippage(tester, isMobile: isMobile, value: '1.5');
      if (isMobile) {
        final back = tester.getRect(
          find.byKey(const ValueKey('mobile_modal_back_button')),
        );
        final sheet = tester.getRect(
          find.byType(MobileSwapSlippageStepperModal),
        );
        expect(back.bottom, lessThan(sheet.top));
        expect(back.width, 44);
        expect(back.height, 44);
      }
      await tester.tap(
        find.byKey(
          ValueKey(
            isMobile ? 'mobile_modal_back_button' : 'swap_slippage_back_button',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Payment request'), findsOneWidget);
      expect(
        harness.container.read(crossChainPaymentFlowProvider)?.slippageBps,
        isNull,
      );
      expect(harness.provider.quoteCalls, 0);

      await tester.tap(find.byKey(_slippageKey));
      await tester.pumpAndSettle();
      await _enterSlippage(tester, isMobile: isMobile, value: '2');
      final slippageTop = tester.getTopLeft(find.text('Slippage')).dy;
      await tester.tapAt(const Offset(4, 40));
      if (isMobile) {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.text('Slippage'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Slippage')).dy,
          greaterThan(slippageTop),
        );
        await _captureHost(
          tester,
          isMobile: true,
          state: 'outside-closing',
          settle: false,
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('Slippage'), findsNothing);
      expect(find.text('Payment request'), findsNothing);
      expect(harness.container.read(crossChainPaymentFlowProvider), isNull);
      expect(harness.state.slippageBps, originalSlippage);
      expect(harness.provider.quoteCalls, 0);
      await _captureHost(
        tester,
        isMobile: isMobile,
        state: 'outside-dismissed',
      );

      harness.present(id: 'request-after-outside-dismissal');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_slippageKey));
      await tester.pumpAndSettle();
      await _enterSlippage(tester, isMobile: isMobile, value: '1');
      await tester.tap(
        find.byKey(const ValueKey('swap_slippage_update_button')),
      );
      await tester.pumpAndSettle();
      expect(
        harness.container.read(crossChainPaymentFlowProvider)?.slippageBps,
        100,
      );
      await tester.tap(find.byKey(_cancelKey));
      await tester.pumpAndSettle();
      expect(harness.container.read(crossChainPaymentFlowProvider), isNull);
      expect(harness.state.slippageBps, originalSlippage);
      expect(harness.provider.quoteCalls, 0);
      harness.present(id: 'next-request');
      await tester.pumpAndSettle();
      expect(
        harness.container.read(crossChainPaymentFlowProvider)?.slippageBps,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await harness.dispose(tester);
    },
  );

  testWidgets('a slippage editor cannot update a replacement request', (
    tester,
  ) async {
    final harness = await _readyHarness(tester, isMobile: isMobile);
    await tester.tap(find.byKey(_slippageKey));
    await tester.pumpAndSettle();
    final submit = isMobile
        ? tester
              .widget<MobileSwapSlippageStepperModal>(
                find.byType(MobileSwapSlippageStepperModal),
              )
              .onSubmitted
        : tester
              .widget<SwapSlippageModal>(find.byType(SwapSlippageModal))
              .onSubmitted;
    harness.present(id: 'replacement');
    await tester.pumpAndSettle();
    submit(200);
    await tester.pumpAndSettle();
    final flow = harness.container.read(crossChainPaymentFlowProvider)!;
    expect(flow.request.id, 'replacement');
    expect(flow.slippageBps, isNull);
    expect(find.byKey(_slippageKey), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_slippage_update_button')),
      findsNothing,
    );
    expect(harness.provider.quoteCalls, 0);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  if (isMobile) {
    testWidgets('outside dismissal respects reduced motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final harness = await _readyHarness(tester, isMobile: true);
      await tester.tapAt(const Offset(4, 40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Payment request'), findsNothing);
      expect(harness.container.read(crossChainPaymentFlowProvider), isNull);
      expect(tester.takeException(), isNull);
      await harness.dispose(tester);
    });

    testWidgets(
      'dragging slippage settings closes the entire payment request',
      (tester) async {
        final harness = await _readyHarness(tester, isMobile: true);
        final original = _composerValues(harness.state);
        await tester.tap(find.byKey(_slippageKey));
        await tester.pumpAndSettle();
        await _enterSlippage(tester, isMobile: true, value: '1.5');
        await tester.fling(find.text('Slippage'), const Offset(0, 500), 1200);
        await tester.pumpAndSettle();
        expect(find.byType(MobileSwapSlippageStepperModal), findsNothing);
        expect(find.text('Payment request'), findsNothing);
        expect(find.byKey(_continueKey), findsNothing);
        expect(harness.container.read(crossChainPaymentFlowProvider), isNull);
        expect(_composerValues(harness.state), original);
        expect(harness.location, '/swap');
        expect(harness.provider.quoteCalls, 0);
        await _captureHost(tester, isMobile: true, state: 'slippage-dismissed');

        harness.present(id: 'request-after-slippage-dismissal');
        await tester.pumpAndSettle();
        expect(find.text('Payment request'), findsOneWidget);
        expect(
          harness.container.read(crossChainPaymentFlowProvider)?.slippageBps,
          isNull,
        );
        expect(
          tester.widget<AppButton>(find.byKey(_continueKey)).onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
        await harness.dispose(tester);
      },
    );
    testWidgets('a short drag restores the payment request sheet', (
      tester,
    ) async {
      final harness = await _readyHarness(tester, isMobile: true);
      final title = find.text('Payment request');
      final start = tester.getCenter(title);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();

      expect(tester.getCenter(title).dy, greaterThan(start.dy));
      await _captureHost(tester, isMobile: true, state: 'dragging');
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.getCenter(title), start);
      expect(harness.container.read(crossChainPaymentFlowProvider), isNotNull);
      expect(harness.location, '/swap');
      expect(harness.provider.quoteCalls, 0);
      expect(tester.takeException(), isNull);
      await harness.dispose(tester);
    });

    testWidgets('drag dismissal cancels a pending payment review', (
      tester,
    ) async {
      final harness = await _readyHarness(
        tester,
        isMobile: true,
        holdQuotes: true,
      );
      await tester.tap(find.byKey(_continueKey));
      await tester.pump();
      await tester.pump();
      expect(harness.provider.quoteCalls, 1);

      await tester.fling(
        find.text('Payment request'),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.text('Payment request'), findsNothing);
      expect(harness.container.read(crossChainPaymentFlowProvider), isNull);

      harness.provider.completeQuote(0);
      await tester.pumpAndSettle();
      expect(harness.location, '/swap');
      expect(harness.state.reviewQuote, isNull);
      expect(harness.state.quoteLoading, isFalse);
      expect(harness.payExtra, isNull);

      harness.present();
      await tester.pumpAndSettle();
      expect(find.text('Payment request'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await harness.dispose(tester);
    });

    testWidgets('a closing sheet cannot dismiss a replacement request', (
      tester,
    ) async {
      final harness = await _readyHarness(tester, isMobile: true);
      final title = find.text('Payment request');
      final originalTop = tester.getTopLeft(title).dy;
      await tester.fling(title, const Offset(0, 100), 1000);
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.getTopLeft(title).dy, greaterThan(originalTop));

      harness.present(id: 'replacement');
      // Finish the old animation in the same frame that mounts the new request.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Payment request'), findsOneWidget);
      expect(
        harness.container.read(crossChainPaymentFlowProvider)!.request.id,
        'replacement',
      );
      expect(tester.getTopLeft(title).dy, originalTop);
      expect(harness.provider.quoteCalls, 0);
      expect(tester.takeException(), isNull);
      await harness.dispose(tester);
    });
  }

  for (final newerParked in [false, true]) {
    testWidgets(
      'locking during a quote preserves ${newerParked ? 'the newer parked request' : 'the visible request'} for unlock',
      (tester) async {
        final harness = await _readyHarness(
          tester,
          isMobile: isMobile,
          holdQuotes: true,
          controlledSecurity: true,
        );
        final flow = harness.container.read(crossChainPaymentFlowProvider)!;
        final pending = newerParked
            ? const CrossChainPaymentRequest(
                id: 'newer-during-lock',
                rawUri: 'bitcoin:bc1newer?amount=0.1',
                address: 'bc1newer',
                isEvm: false,
                chain: 'btc',
              )
            : flow.request;
        await tester.tap(find.byKey(_continueKey));
        await tester.pump();
        await tester.pump();
        expect(harness.provider.quoteCalls, 1);
        if (newerParked) {
          harness.container
              .read(paymentUriPrefillProvider.notifier)
              .set(pending);
        }
        final security =
            harness.container.read(appSecurityProvider.notifier)
                as _ControlledSecurityNotifier;
        security.setUnlocked(false);
        await tester.pumpAndSettle();
        expect(harness.container.read(crossChainPaymentFlowProvider), isNull);
        expect(
          harness.container.read(paymentUriPrefillProvider),
          same(pending),
        );
        expect(find.byKey(_continueKey), findsNothing);

        harness.provider.completeQuote(0);
        await tester.pumpAndSettle();
        expect(harness.location, '/swap');
        expect(harness.payExtra, isNull);
        expect(harness.state.reviewVisible, isFalse);
        expect(harness.state.reviewQuote, isNull);
        expect(
          harness.container.read(paymentUriPrefillProvider),
          same(pending),
        );

        security.setUnlocked(true);
        final claimed = harness.container
            .read(paymentUriPrefillProvider.notifier)
            .takeIfFresh();
        harness.container
            .read(crossChainPaymentFlowProvider.notifier)
            .present(claimed.prefill! as CrossChainPaymentRequest);
        await tester.pumpAndSettle();
        expect(
          harness.container.read(crossChainPaymentFlowProvider)?.request,
          same(pending),
        );
        expect(find.byKey(_continueKey), findsOneWidget);
        expect(harness.provider.quoteCalls, 1);
        expect(tester.takeException(), isNull);
        await harness.dispose(tester);
      },
    );
  }

  testWidgets('switching accounts during a quote removes the old request', (
    tester,
  ) async {
    final harness = await _readyHarness(
      tester,
      isMobile: isMobile,
      holdQuotes: true,
    );
    await tester.tap(find.byKey(_continueKey));
    await tester.pump();
    await tester.pump();
    expect(harness.provider.quoteCalls, 1);
    (harness.container.read(accountProvider.notifier) as _AccountNotifier)
        .switchToSecondAccount();
    await tester.pumpAndSettle();
    expect(harness.container.read(crossChainPaymentFlowProvider), isNull);
    expect(harness.container.read(paymentUriPrefillProvider), isNull);
    expect(find.byKey(_continueKey), findsNothing);
    harness.provider.completeQuote(0);
    await tester.pumpAndSettle();
    expect(harness.location, '/swap');
    expect(harness.payExtra, isNull);
    expect(harness.state.reviewVisible, isFalse);
    expect(harness.state.reviewQuote, isNull);
    expect(
      harness.container.read(accountProvider).value?.activeAccountUuid,
      'account-2',
    );
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets('Tor startup waits for connected pricing before review', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      isMobile: isMobile,
      privacy: const NetworkPrivacyState(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.connecting,
      ),
    );
    harness.present();
    await tester.pumpAndSettle();
    expect(find.text('Connecting to Tor…'), findsOneWidget);
    expect(find.text('Loading amount…'), findsOneWidget);
    expect(_primary(tester).onPressed, isNull);
    expect(find.textContaining('not available in Vizor'), findsNothing);
    await _captureHost(tester, isMobile: isMobile, state: 'tor-connecting');

    // Even cached metadata does not enable review before the route is ready.
    harness.provider.initial.complete(_pricing([_btc, _usdc]));
    await tester.pumpAndSettle();
    expect(find.text('Connecting to Tor…'), findsOneWidget);
    expect(_primary(tester).onPressed, isNull);
    final privacy =
        harness.container.read(networkPrivacyProvider.notifier)
            as _NetworkPrivacyNotifier;
    privacy.setStatus(NetworkPrivacyConnectionStatus.connected);
    await tester.pumpAndSettle();
    expect(find.text('Checking payment options…'), findsOneWidget);
    expect(harness.provider.pricingCalls, 2);
    harness.provider.refresh.complete(_pricing([_btc, _usdc]));
    await tester.pumpAndSettle();
    expect(find.text('25.000001'), findsOneWidget);
    expect(_primary(tester).onPressed, isNotNull);
    expect(harness.provider.quoteCalls, 0);
    await harness.dispose(tester);
  });

  testWidgets('Tor failure retries the connection and keeps the request', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      isMobile: isMobile,
      privacy: const NetworkPrivacyState(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.connecting,
      ),
    );
    harness.present();
    await tester.pumpAndSettle();
    harness.provider.initial.completeError(StateError('Tor bootstrap failed'));
    final privacy =
        harness.container.read(networkPrivacyProvider.notifier)
            as _NetworkPrivacyNotifier;
    privacy.setStatus(NetworkPrivacyConnectionStatus.failed);
    await tester.pumpAndSettle();
    expect(
      find.text('Could not connect to Tor. Try again to load payment options.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Amount unavailable'), findsOneWidget);
    await _captureHost(tester, isMobile: isMobile, state: 'tor-failed');
    await tester.tap(find.byKey(_continueKey));
    await tester.pumpAndSettle();
    expect(privacy.retryCalls, 1);
    expect(find.text('Connecting to Tor…'), findsOneWidget);
    expect(harness.location, '/swap');
    privacy.setStatus(NetworkPrivacyConnectionStatus.connected);
    await tester.pumpAndSettle();
    harness.provider.refresh.complete(_pricing([_btc, _usdc]));
    await tester.pumpAndSettle();
    expect(find.text('25.000001'), findsOneWidget);
    expect(_primary(tester).onPressed, isNotNull);
    expect(
      harness.container.read(crossChainPaymentFlowProvider)?.request.address,
      _recipient,
    );
    await harness.dispose(tester);
  });

  testWidgets('token query failure retries without replacing the request', (
    tester,
  ) async {
    final harness = await _pump(tester, isMobile: isMobile);
    harness.present();
    await tester.pumpAndSettle();
    harness.provider.initial.completeError(const SocketException('Offline'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Payment options could not be loaded. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('not available in Vizor'), findsNothing);
    await tester.tap(find.byKey(_continueKey));
    await tester.pumpAndSettle();
    expect(find.text('Checking payment options…'), findsOneWidget);
    harness.provider.refresh.complete(_pricing([_btc, _usdc]));
    await tester.pumpAndSettle();
    expect(find.text('25.000001'), findsOneWidget);
    expect(_primary(tester).onPressed, isNotNull);
    expect(harness.provider.quoteCalls, 0);
    await harness.dispose(tester);
  });

  testWidgets('loading and cancellation preserve the existing composer', (
    tester,
  ) async {
    final harness = await _pump(tester, isMobile: isMobile);
    final notifier = harness.container.read(swapStateProvider.notifier);
    harness.provider.initial.complete(_pricing([_btc, _usdc]));
    await tester.pumpAndSettle();
    notifier.selectExternalAsset(_btc);
    notifier.updateAmount('1.25');
    notifier.updateDestination('existing draft recipient');
    final original = _composerValues(harness.state);

    final refresh = notifier.refreshPaymentRequestAssets();
    harness.present();
    await tester.pumpAndSettle();
    expect(find.text('Checking payment options…'), findsOneWidget);
    expect(find.text('Estimated spend'), findsNothing);
    expect(_primary(tester).onPressed, isNull);
    expect(_composerValues(harness.state), original);
    expect(harness.location, '/swap');

    harness.provider.refresh.complete(
      SwapPricingSnapshot(usdPrices: {SwapAsset.zec: 200, _btc: 1, _usdc: 1}),
    );
    await refresh;
    await tester.pumpAndSettle();
    expect(find.text('25.000001'), findsOneWidget);
    expect(find.text('USDC'), findsOneWidget);
    expect(find.text('≈ 0.1250 ZEC'), findsOneWidget);
    expect(_composerValues(harness.state), original);
    expect(harness.provider.quoteCalls, 0);

    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();
    expect(harness.container.read(crossChainPaymentFlowProvider), isNull);
    expect(_composerValues(harness.state), original);
    expect(harness.location, '/swap');
    expect(harness.payExtra, isNull);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets(
    'Review prepares one exact-output quote before routing to payment review',
    (tester) async {
      final harness = await _pump(tester, isMobile: isMobile, holdQuotes: true);
      harness.present();
      await tester.pumpAndSettle();
      harness.provider.initial.complete(_pricing([_btc, _usdc]));
      await tester.pumpAndSettle();
      expect(harness.state.payMode, isFalse);
      expect(harness.state.destinationText, isEmpty);
      expect(harness.state.receiveAmountText, isEmpty);
      expect(find.text('≈ 0.2500 ZEC'), findsOneWidget);
      expect(find.text('Token details'), findsNothing);
      expect(harness.provider.quoteCalls, 0);

      await _captureHost(tester, isMobile: isMobile);

      final originalReviewCallback = _primary(tester).onPressed!;
      await tester.tap(find.byKey(_continueKey));
      originalReviewCallback();
      await tester.pump();
      await tester.pump();

      expect(harness.provider.quoteCalls, 1);
      expect(harness.location, '/swap');
      expect(_primary(tester).onPressed, isNull);
      expect(tester.widget<AppButton>(find.byKey(_editKey)).onPressed, isNull);
      expect(find.text('Preparing payment review…'), findsOneWidget);
      expect(
        harness.container
            .read(crossChainPaymentFlowProvider)
            ?.isPreparingReview,
        isTrue,
      );
      final request = harness.provider.requests.single;
      expect(request.mode, SwapQuoteMode.exactOutput);
      expect(request.amountText, '25.000001');
      expect(request.amountAsset, _usdc);
      expect(request.destination, _recipient);
      expect(request.refundAddress, 'u1test-orchard-staging-account-1');
      await _captureHost(tester, isMobile: isMobile, state: 'preparing');
      harness.provider.completeQuote(0);
      await tester.pumpAndSettle();

      expect(harness.location, isMobile ? '/pay/review' : '/pay');
      expect(harness.payExtra, isA<PayComposerNavigationArgs>());
      final extra = harness.payExtra! as PayComposerNavigationArgs;
      expect(extra.preservePreparedComposer, isTrue);
      expect(extra.paymentRequestId, 'request-25-usdc');
      expect(extra.showPreparedReview, isTrue);
      expect(extra.reviewAfterAmount, isFalse);
      expect(harness.container.read(crossChainPaymentFlowProvider), isNull);
      expect(harness.state.direction, SwapDirection.zecToExternal);
      expect(harness.state.payMode, isTrue);
      expect(harness.state.quoteMode, SwapQuoteMode.exactOutput);
      expect(harness.state.receiveAmountText, '25.000001');
      expect(harness.state.receiveAmountInputMode, SwapAmountInputMode.token);
      expect(harness.state.destinationText, _recipient);
      expect(harness.state.externalAsset.assetId, _usdc.assetId);
      expect(harness.state.externalAsset.contractAddress, _contract);
      expect(harness.state.paymentRequestAssetId, _usdc.assetId);
      expect(harness.state.externalAssetIsSupported, isTrue);
      expect(harness.state.reviewVisible, isTrue);
      expect(harness.state.reviewQuote, isNotNull);
      expect(harness.provider.quoteCalls, 1);
      expect(tester.takeException(), isNull);
      await harness.dispose(tester);
    },
  );

  testWidgets('a refreshed lookalike asset cannot replace the reviewed asset', (
    tester,
  ) async {
    final harness = await _pump(tester, isMobile: isMobile);
    harness.present();
    await tester.pumpAndSettle();
    harness.provider.initial.complete(_pricing([_usdc]));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_continueKey));
    await tester.pumpAndSettle();
    final original = _composerValues(harness.state);
    final lookalike = SwapAsset.live(
      assetId: 'another-base-usdc',
      symbol: 'USDC',
      blockchain: 'base',
      decimals: 6,
      contractAddress: '0x1111111111111111111111111111111111111111',
    );

    final refresh = harness.container
        .read(swapStateProvider.notifier)
        .refreshPaymentRequestAssets();
    await tester.pump();
    expect(harness.state.pricingLoading, isTrue);
    harness.provider.refresh.complete(_pricing([lookalike]));
    await refresh;
    await tester.pumpAndSettle();

    expect(harness.state.paymentRequestAssetId, _usdc.assetId);
    expect(harness.state.externalAsset, _usdc);
    expect(_composerValues(harness.state), original);
    expect(harness.state.supportedExternalAssets, [lookalike]);
    expect(harness.state.externalAssetIsSupported, isFalse);
    expect(
      harness.state.externalAssetSupportError,
      contains('not currently supported'),
    );
    expect(harness.state.canReviewQuote, isFalse);
    expect(harness.provider.quoteCalls, 1);
    await harness.dispose(tester);
  });

  testWidgets(
    'an asset removed during a pending quote cannot open an actionable review',
    (tester) async {
      final harness = await _readyHarness(
        tester,
        isMobile: isMobile,
        holdQuotes: true,
      );
      await tester.tap(find.byKey(_continueKey));
      await tester.pump();
      await tester.pump();
      expect(harness.provider.quoteCalls, 1);
      final impostor = SwapAsset.live(
        assetId: 'impostor-base-usdc',
        symbol: 'USDC',
        blockchain: 'base',
        decimals: 6,
        contractAddress: '0x1111111111111111111111111111111111111111',
      );
      final refresh = harness.container
          .read(swapStateProvider.notifier)
          .refreshPaymentRequestAssets();
      await tester.pump();
      harness.provider.refresh.complete(_pricing([impostor]));
      await refresh;
      await tester.pumpAndSettle();
      expect(harness.state.externalAsset, _usdc);
      expect(harness.state.externalAssetIsAvailable, isFalse);

      harness.provider.completeQuote(0);
      await tester.pumpAndSettle();

      expect(harness.location, '/swap');
      expect(harness.payExtra, isNull);
      expect(harness.state.paymentRequestAssetId, _usdc.assetId);
      expect(harness.state.reviewVisible, isFalse);
      expect(harness.state.reviewQuote, isNull);
      expect(harness.state.reviewAddressPlan, isNull);
      expect(harness.state.quoteLoading, isFalse);
      expect(harness.state.canReviewQuote, isFalse);
      final flow = harness.container.read(crossChainPaymentFlowProvider);
      expect(flow?.isPreparingReview, isFalse);
      expect(flow?.reviewError, contains('not currently supported'));
      expect(find.textContaining('not currently supported'), findsOneWidget);
      expect(find.byKey(_editKey), findsNothing);
      expect(harness.provider.quoteCalls, 1);
      await harness.dispose(tester);
    },
  );

  testWidgets('missing network and amount go from selection to amount entry', (
    tester,
  ) async {
    final harness = await _pump(tester, isMobile: isMobile);
    final eth = SwapAsset.live(
      assetId: 'live-base-eth',
      symbol: 'ETH',
      blockchain: 'base',
      decimals: 18,
    );
    harness.provider.initial.complete(_pricing([_btc, _usdc, eth]));
    harness.container
        .read(crossChainPaymentFlowProvider.notifier)
        .present(
          const CrossChainPaymentRequest(
            id: 'no-network-or-amount',
            rawUri: 'ethereum:$_recipient',
            address: _recipient,
            isEvm: true,
          ),
        );
    await tester.pumpAndSettle();
    expect(
      find.text('Select the receiving network, then enter an amount.'),
      findsOneWidget,
    );
    expect(_primary(tester).onPressed, isNull);
    await _captureHost(
      tester,
      isMobile: isMobile,
      state: 'no-network-or-amount',
    );
    await tester.tap(find.text('Select network'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ETH · Base'));
    await tester.pumpAndSettle();
    expect(find.text('Amount not specified'), findsOneWidget);
    expect(find.text('Enter amount'), findsOneWidget);
    await tester.tap(find.byKey(_continueKey));
    await tester.pumpAndSettle();
    expect(harness.location, '/pay');
    expect(harness.state.receiveAmountText, isEmpty);
    expect(harness.state.destinationText, _recipient);
    expect(harness.state.externalAsset, eth);
    expect(harness.provider.quoteCalls, 0);
    await harness.dispose(tester);
  });

  testWidgets('amountless requests enter Pay without preparing a quote', (
    tester,
  ) async {
    final harness = await _readyHarness(
      tester,
      isMobile: isMobile,
      includeAmount: false,
    );
    expect(find.text('Enter amount'), findsOneWidget);
    harness.container
        .read(crossChainPaymentFlowProvider.notifier)
        .chooseSlippage(125);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_continueKey));
    await tester.pumpAndSettle();

    expect(harness.location, '/pay');
    expect(harness.provider.quoteCalls, 0);
    expect(harness.state.reviewQuote, isNull);
    expect(harness.state.receiveAmountText, isEmpty);
    expect(harness.state.destinationText, _recipient);
    expect(harness.state.externalAsset, _usdc);
    expect(harness.state.slippageBps, 125);
    expect(
      (harness.payExtra! as PayComposerNavigationArgs).showPreparedReview,
      isFalse,
    );
    await harness.dispose(tester);
  });

  testWidgets('Edit opens the prepared composer with editable payment fields', (
    tester,
  ) async {
    final harness = await _readyHarness(
      tester,
      isMobile: isMobile,
      useRealPayScreens: true,
    );
    await tester.tap(find.byKey(_editKey));
    await tester.pumpAndSettle();

    expect(harness.location, '/pay');
    expect(harness.provider.quoteCalls, 0);
    expect(harness.state.reviewQuote, isNull);
    expect(harness.state.receiveAmountText, '25.000001');
    expect(harness.state.destinationText, _recipient);
    expect(harness.state.paymentRequestAssetId, _usdc.assetId);
    final extra = harness.payExtra! as PayComposerNavigationArgs;
    expect(extra.preservePreparedComposer, isTrue);
    expect(extra.showPreparedReview, isFalse);
    expect(extra.reviewAfterAmount, isFalse);
    final prefix = isMobile ? 'mobile_pay' : 'pay';
    await tester.enterText(
      find.byKey(ValueKey('${prefix}_amount_input')),
      '12',
    );
    await tester.tap(find.byKey(ValueKey('${prefix}_amount_continue_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('${prefix}_recipient_step')), findsOneWidget);
    expect(harness.provider.quoteCalls, 0);
    await tester.enterText(
      find.byKey(
        ValueKey(
          isMobile
              ? 'mobile_pay_recipient_input'
              : 'pay_recipient_search_field',
        ),
      ),
      '0x1111111111111111111111111111111111111111',
    );
    await tester.pump();
    expect(harness.state.receiveAmountText, '12');
    expect(
      harness.state.destinationText,
      '0x1111111111111111111111111111111111111111',
    );
    await tester.tap(
      find.byKey(
        ValueKey(
          isMobile
              ? 'mobile_pay_recipient_continue_button'
              : 'pay_select_recipient_button',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Review Payment'), findsOneWidget);
    expect(harness.provider.requests.single.amountText, '12');
    expect(
      harness.provider.requests.single.destination,
      '0x1111111111111111111111111111111111111111',
    );
    expect(
      find.byKey(
        ValueKey(
          isMobile ? 'mobile_pay_review_confirm_button' : 'pay_confirm_button',
        ),
      ),
      findsOneWidget,
    );
    await _captureHost(tester, isMobile: isMobile, state: 'edited-review');
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets(
    'cancelling a pending quote prevents late review and permits reopening',
    (tester) async {
      final harness = await _readyHarness(
        tester,
        isMobile: isMobile,
        holdQuotes: true,
      );
      await tester.tap(find.byKey(_continueKey));
      await tester.pump();
      await tester.pump();
      expect(harness.provider.quoteCalls, 1);
      await tester.tapAt(const Offset(4, 40));
      await tester.pump();
      if (isMobile) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.text('Payment request'), findsOneWidget);
      }
      harness.provider.completeQuote(0);
      await tester.pump();
      expect(harness.location, '/swap');
      expect(harness.payExtra, isNull);
      await tester.pumpAndSettle();

      expect(harness.location, '/swap');
      expect(harness.container.read(crossChainPaymentFlowProvider), isNull);
      expect(harness.state.reviewQuote, isNull);
      expect(harness.state.quoteLoading, isFalse);
      expect(harness.payExtra, isNull);

      harness.present();
      await tester.pumpAndSettle();
      expect(find.text('Review payment'), findsOneWidget);
      await tester.tap(find.byKey(_continueKey));
      await tester.pump();
      await tester.pump();
      expect(harness.provider.quoteCalls, 2);
      harness.provider.completeQuote(1);
      await tester.pumpAndSettle();
      expect(harness.location, isMobile ? '/pay/review' : '/pay');
      await harness.dispose(tester);
    },
  );

  testWidgets(
    'replacement during quote preparation cannot navigate the earlier request',
    (tester) async {
      final harness = await _readyHarness(
        tester,
        isMobile: isMobile,
        holdQuotes: true,
      );
      await tester.tap(find.byKey(_continueKey));
      await tester.pump();
      await tester.pump();
      const replacementRecipient = '0x1111111111111111111111111111111111111111';
      harness.present(id: 'replacement', address: replacementRecipient);
      await tester.pumpAndSettle();
      harness.provider.completeQuote(0);
      await tester.pumpAndSettle();

      expect(harness.location, '/swap');
      expect(harness.payExtra, isNull);
      expect(harness.state.reviewQuote, isNull);
      expect(
        harness.container.read(crossChainPaymentFlowProvider)?.request.id,
        'replacement',
      );
      await tester.tap(find.byKey(_continueKey));
      await tester.pump();
      await tester.pump();
      expect(harness.provider.requests.last.destination, replacementRecipient);
      harness.provider.completeQuote(1);
      await tester.pumpAndSettle();
      expect(
        (harness.payExtra! as PayComposerNavigationArgs).paymentRequestId,
        'replacement',
      );
      expect(harness.state.destinationText, replacementRecipient);
      await harness.dispose(tester);
    },
  );

  testWidgets('quote failures stay on the card with Retry and Edit', (
    tester,
  ) async {
    final harness = await _readyHarness(
      tester,
      isMobile: isMobile,
      holdQuotes: true,
    );
    await tester.tap(find.byKey(_continueKey));
    await tester.pump();
    await tester.pump();
    harness.provider.pendingQuotes[0].completeError(
      StateError('Quote unavailable'),
    );
    await tester.pumpAndSettle();

    expect(harness.location, '/swap');
    expect(
      harness.container.read(crossChainPaymentFlowProvider)?.reviewError,
      isNotNull,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.widget<AppButton>(find.byKey(_editKey)).onPressed, isNotNull);
    await tester.tap(find.byKey(_continueKey));
    await tester.pump();
    await tester.pump();
    expect(harness.provider.quoteCalls, 2);
    expect(harness.provider.requests.last.amountText, '25.000001');
    expect(harness.provider.requests.last.destination, _recipient);
    harness.provider.pendingQuotes[1].completeError(
      StateError('Quote still unavailable'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_editKey));
    await tester.pumpAndSettle();
    expect(harness.location, '/pay');
    expect(
      (harness.payExtra! as PayComposerNavigationArgs).showPreparedReview,
      isFalse,
    );
    expect(harness.provider.quoteCalls, 2);
    expect(harness.state.receiveAmountText, '25.000001');
    expect(harness.state.destinationText, _recipient);
    await harness.dispose(tester);
  });

  testWidgets(
    'the same request may be reviewed again after completing a review',
    (tester) async {
      final harness = await _readyHarness(tester, isMobile: isMobile);
      await tester.tap(find.byKey(_continueKey));
      await tester.pumpAndSettle();
      expect(harness.provider.quoteCalls, 1);
      final firstQuote = harness.state.reviewQuote;

      harness.present();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_continueKey));
      await tester.pumpAndSettle();
      expect(harness.provider.quoteCalls, 2);
      expect(harness.state.reviewQuote, isNot(same(firstQuote)));
      expect(harness.container.read(crossChainPaymentFlowProvider), isNull);
      expect(harness.location, isMobile ? '/pay/review' : '/pay');
      await harness.dispose(tester);
    },
  );

  testWidgets(
    'disabled Pay never starts pricing or navigates to the composer',
    (tester) async {
      final harness = await _pump(tester, isMobile: isMobile, enabled: false);
      harness.present();
      await tester.pumpAndSettle();

      expect(
        find.text('Pay is not available for this wallet.'),
        findsOneWidget,
      );
      expect(harness.provider.pricingCalls, 0);
      expect(harness.container.exists(swapStateProvider), isFalse);
      expect(_primary(tester).onPressed, isNull);
      await tester.tap(find.byKey(_continueKey));
      await tester.pumpAndSettle();
      expect(harness.location, '/swap');
      expect(harness.payExtra, isNull);
      expect(harness.provider.pricingCalls, 0);
      expect(harness.container.exists(swapStateProvider), isFalse);
      expect(tester.takeException(), isNull);
      await harness.dispose(tester);
    },
  );
}

AppButton _primary(WidgetTester tester) =>
    tester.widget<AppButton>(find.byKey(_continueKey));

Object _composerValues(SwapState state) => (
  state.direction,
  state.quoteMode == SwapQuoteMode.exactOutput
      ? state.receiveAmountText
      : state.amountText,
  state.destinationText,
  state.externalAsset,
  state.quoteMode,
  state.payMode,
  state.paymentRequestAssetId,
);

Future<_Harness> _pump(
  WidgetTester tester, {
  required bool isMobile,
  bool enabled = true,
  bool holdQuotes = false,
  bool useRealPayScreens = false,
  bool controlledSecurity = false,
  NetworkPrivacyState privacy = const NetworkPrivacyState.off(),
}) async {
  tester.view.physicalSize = isMobile
      ? const Size(390, 844)
      : const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final provider = _ControlledPricingProvider(holdQuotes: holdQuotes);
  final storage = _NoOpSwapStore();
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        AppBootstrapState(
          initialLocation: '/swap',
          initialAccountState: _account,
          initialSyncSnapshot: AppSyncSnapshot.empty,
          network: 'main',
          rpcEndpointConfig: defaultRpcEndpointConfig('main'),
          themeMode: ThemeMode.dark,
          privacyModeEnabled: false,
          isPasswordConfigured: true,
          isUnlocked: true,
          passwordRotationRecoveryFailed: false,
        ),
      ),
      accountProvider.overrideWith(_AccountNotifier.new),
      if (controlledSecurity)
        appSecurityProvider.overrideWith(_ControlledSecurityNotifier.new),
      if (useRealPayScreens) ...[
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            SyncState(
              accountUuid: 'account-1',
              hasAccountScopedData: true,
              spendableBalance: BigInt.from(10000000000),
              totalBalance: BigInt.from(10000000000),
            ),
          ),
        ),
        addressBookRepositoryProvider.overrideWithValue(
          _EmptyAddressBookRepository(),
        ),
      ],
      networkPrivacyProvider.overrideWith(
        () => _NetworkPrivacyNotifier(privacy),
      ),
      swapFeatureEnabledProvider.overrideWithValue(enabled),
      swapIntentProvider.overrideWithValue(provider),
      swapActivityStoreProvider.overrideWithValue(storage),
      swapComposerPreferencesStoreProvider.overrideWithValue(storage),
      paySelectedAssetStoreProvider.overrideWithValue(storage),
      swapZecStagingAddressServiceProvider.overrideWithValue(
        SwapZecStagingAddressService(
          reserveFreshOrchardAddress: ({required accountUuid}) async =>
              'u1test-orchard-staging-$accountUuid',
        ),
      ),
      swapPriceRefreshIntervalProvider.overrideWithValue(
        const Duration(days: 1),
      ),
      swapStatusPollIntervalProvider.overrideWithValue(const Duration(days: 1)),
    ],
  );
  late _Harness harness;
  final router = GoRouter(
    initialLocation: '/swap',
    routes: [
      GoRoute(
        path: '/swap',
        builder: (_, _) => const Scaffold(body: Text('Swap composer')),
      ),
      GoRoute(
        path: '/pay',
        builder: (_, state) {
          harness.payExtra = state.extra;
          if (useRealPayScreens) {
            final args = state.extra! as PayComposerNavigationArgs;
            return isMobile
                ? MobilePayScreen(
                    key: ValueKey(args.paymentRequestId),
                    preservePreparedComposer: args.preservePreparedComposer,
                    paymentRequestId: args.paymentRequestId,
                    reviewAfterAmount: args.reviewAfterAmount,
                  )
                : PayScreen(
                    key: ValueKey(args.paymentRequestId),
                    preservePreparedComposer: args.preservePreparedComposer,
                    paymentRequestId: args.paymentRequestId,
                    showPreparedReview: args.showPreparedReview,
                    reviewAfterAmount: args.reviewAfterAmount,
                  );
          }
          return const Scaffold(body: Text('Pay composer'));
        },
      ),
      GoRoute(
        path: '/pay/review',
        builder: (_, state) {
          harness.payExtra = state.extra;
          if (useRealPayScreens) {
            return MobileSwapReviewScreen(
              payMode: true,
              paymentRequestId: state.extra is PayComposerNavigationArgs
                  ? (state.extra! as PayComposerNavigationArgs).paymentRequestId
                  : null,
            );
          }
          return const Scaffold(body: Text('Pay review'));
        },
      ),
    ],
  );
  harness = _Harness(container, router, provider);
  addTearDown(() => harness.dispose(tester));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => AppTheme(
          data: AppThemeData.dark,
          child: RepaintBoundary(
            key: const ValueKey('payment_request_host_capture'),
            child: CrossChainPaymentRequestHost(router: router, child: child!),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _captureHost(
  WidgetTester tester, {
  required bool isMobile,
  String state = 'ready',
  bool settle = true,
}) async {
  const directory = String.fromEnvironment('VIZOR_CAPTURE_DIR');
  if (directory.isEmpty) return;
  final context = tester.element(
    find.byKey(const ValueKey('payment_request_host_capture')),
  );
  final imagePaths = <String>{
    for (final icon in tester.widgetList<SwapAssetIcon>(
      find.byType(SwapAssetIcon),
    )) ...[
      icon.asset.tokenIconAsset,
      if (icon.showChainBadge) icon.asset.chainIconAsset,
    ],
  };
  await tester.runAsync(() async {
    await Future.wait([
      for (final path in imagePaths) precacheImage(AssetImage(path), context),
    ]);
  });
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('payment_request_host_capture')),
    );
    final image = await boundary.toImage(pixelRatio: isMobile ? 1 : 0.6);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      '$directory/payment-request-host-${isMobile ? 'mobile' : 'desktop'}${state == 'ready' ? '' : '-$state'}.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _enterSlippage(
  WidgetTester tester, {
  required bool isMobile,
  required String value,
}) async {
  if (!isMobile) {
    await tester.tap(find.byKey(const ValueKey('swap_slippage_custom_card')));
    await tester.pumpAndSettle();
  }
  await tester.enterText(
    find.byKey(
      ValueKey(
        isMobile ? 'mobile_swap_slippage_value' : 'swap_slippage_custom_input',
      ),
    ),
    value,
  );
  await tester.pumpAndSettle();
}

Future<_Harness> _readyHarness(
  WidgetTester tester, {
  required bool isMobile,
  bool holdQuotes = false,
  bool includeAmount = true,
  bool useRealPayScreens = false,
  bool controlledSecurity = false,
}) async {
  final harness = await _pump(
    tester,
    isMobile: isMobile,
    holdQuotes: holdQuotes,
    useRealPayScreens: useRealPayScreens,
    controlledSecurity: controlledSecurity,
  );
  harness.present(includeAmount: includeAmount);
  await tester.pumpAndSettle();
  harness.provider.initial.complete(_pricing([_btc, _usdc]));
  await tester.pumpAndSettle();
  return harness;
}

class _Harness {
  _Harness(this.container, this.router, this.provider);
  final ProviderContainer container;
  final GoRouter router;
  final _ControlledPricingProvider provider;
  Object? payExtra;
  bool _disposed = false;

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    router.dispose();
    await tester.pump();
  }

  String get location => router.routeInformationProvider.value.uri.path;
  SwapState get state => container.read(swapStateProvider);

  void present({
    String id = 'request-25-usdc',
    String address = _recipient,
    bool includeAmount = true,
  }) => container
      .read(crossChainPaymentFlowProvider.notifier)
      .present(
        CrossChainPaymentRequest(
          id: id,
          rawUri:
              'ethereum:$_contract@8453/transfer?address=$address${includeAmount ? '&uint256=25000001' : ''}',
          address: address,
          isEvm: true,
          chainId: '8453',
          contractAddress: _contract,
          amount: includeAmount
              ? PaymentRequestAmount.atomicHex('0x17d7841')
              : null,
        ),
      );
}

class _AccountNotifier extends AccountNotifier {
  @override
  AccountState build() => _account;

  void switchToSecondAccount() {
    state = AsyncData(
      state.value!.copyWith(
        accounts: [
          ...state.value!.accounts,
          const AccountInfo(uuid: 'account-2', name: 'Account 2', order: 1),
        ],
        activeAccountUuid: 'account-2',
      ),
    );
  }
}

class _ControlledSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  void setUnlocked(bool value) => state = state.copyWith(isUnlocked: value);
}

class _NetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  _NetworkPrivacyNotifier(this.initialState);
  final NetworkPrivacyState initialState;
  int retryCalls = 0;
  @override
  NetworkPrivacyState build() => initialState;

  void setStatus(NetworkPrivacyConnectionStatus status) {
    state = NetworkPrivacyState(torEnabled: true, status: status);
  }

  @override
  Future<void> retry() async {
    retryCalls++;
    setStatus(NetworkPrivacyConnectionStatus.connecting);
  }
}

class _EmptyAddressBookRepository implements AddressBookRepository {
  @override
  Future<List<AddressBookContact>> loadContacts() async => [];
  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}

SwapPricingSnapshot _pricing(List<SwapAsset> assets) => SwapPricingSnapshot(
  usdPrices: {SwapAsset.zec: 100, for (final asset in assets) asset: 1},
);

class _ControlledPricingProvider implements SwapProvider, SwapPricingProvider {
  _ControlledPricingProvider({this.holdQuotes = false});
  final bool holdQuotes;
  final initial = Completer<SwapPricingSnapshot>();
  final refresh = Completer<SwapPricingSnapshot>();
  var pricingCalls = 0;
  final requests = <SwapQuoteRequest>[];
  final pendingQuotes = <Completer<SwapQuote>>[];
  int get quoteCalls => requests.length;

  @override
  String get providerLabel => 'Test pricing';

  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({bool forceRefresh = false}) {
    pricingCalls++;
    return pricingCalls == 1 ? initial.future : refresh.future;
  }

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() =>
      throw StateError('Expected the pricing snapshot to supply live assets');

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) {
    requests.add(request);
    if (!holdQuotes) return Future.value(_quote(request));
    final completer = Completer<SwapQuote>();
    pendingQuotes.add(completer);
    return completer.future;
  }

  void completeQuote(int index) =>
      pendingQuotes[index].complete(_quote(requests[index]));

  SwapQuote _quote(SwapQuoteRequest request) => SwapQuote.estimate(
    direction: request.direction,
    externalAsset: request.externalAsset,
    mode: request.mode,
    amount: request.amount,
    providerLabel: providerLabel,
    externalPerZec: 100,
  );

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) => throw UnimplementedError();

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) =>
      throw UnimplementedError();

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) => throw UnimplementedError();
}

class _NoOpSwapStore
    implements
        SwapActivityStore,
        SwapComposerPreferencesStore,
        PaySelectedAssetStore {
  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async => [];
  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {}
  @override
  Future<void> deleteForAccount({required String accountUuid}) async {}
  @override
  Future<SwapComposerPreferences?> loadPreferences({
    required String accountUuid,
  }) async => null;
  @override
  Future<void> savePreferences({
    required String accountUuid,
    required SwapComposerPreferences preferences,
  }) async {}
  @override
  Future<SwapAsset?> loadSelectedAsset({required String accountUuid}) async =>
      null;
  @override
  Future<void> saveSelectedAsset({
    required String accountUuid,
    required SwapAsset asset,
  }) async {}
}
