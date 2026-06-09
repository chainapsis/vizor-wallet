import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/address_book/widgets/address_book_network_icon.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_navigation.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_detail_tooltips.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_deposit_broadcast_result.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_intent_presentation_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_deposit_sender.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_max_amount_estimator.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_composer_preferences_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_zec_staging_address_service.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_screen.dart';
import 'package:zcash_wallet/src/features/activity/screens/swap_activity_detail_screen.dart';
import 'package:zcash_wallet/src/features/swap/screens/swap_review_screen.dart';
import 'package:zcash_wallet/src/features/swap/screens/swap_screen.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_amount_text.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/address_qr_scan_modal.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_asset_icon.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_deposit_tokens_page_content.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_review_page_content.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_status_page_content.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_summary_amount_text.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/receive_address_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/swap_activity_fixture_intents.dart';

part 'support/swap_screen_test_fakes.dart';

void main() {
  test('swapIntentProvider uses the Vizor proxy and referral', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final provider = container.read(swapIntentProvider);

    expect(provider, isA<NearIntentsOneClickSwapAdapter>());
    final oneClickProvider = provider as NearIntentsOneClickSwapAdapter;
    expect(
      oneClickProvider.baseUri.toString(),
      'https://functions.vizor.cash/api/near-intents/1click',
    );
    expect(oneClickProvider.referral, 'vizor');
  });

  test('compactSwapAmountText truncates visible decimals without ellipsis', () {
    expect(compactSwapAmountText('~0.123456789 BTC'), '0.123456 BTC');
    expect(compactSwapAmountText('12345.678901 USDC'), '12345.678901 USDC');
    expect(compactSwapAmountText('2 ZEC'), '2 ZEC');
    expect(
      compactSwapAmountText('1.1234567 ZEC -> ~2.7654321 USDC'),
      '1.123456 ZEC -> 2.765432 USDC',
    );
    expect(compactSwapAmountText('~0.9 BTC', maxFractionDigits: 0), '0 BTC');
  });

  test('compactSwapSummaryAmountText follows review large amount notation', () {
    expect(
      compactSwapSummaryAmountText(r'999123000.00 $SHIT'),
      r'999.123M $SHIT',
    );
    expect(compactSwapSummaryAmountText(r'999.123M $SHIT'), r'999.123M $SHIT');
    expect(compactSwapSummaryAmountText('999,999.99 USDC'), '999,999.99 USDC');
    expect(
      compactSwapSummaryAmountText(
        '999,999.99 USDC',
        forceCompactThousands: true,
      ),
      '999.999K USDC',
    );
    expect(
      compactSwapSummaryAmountText(
        r'999,999.99 $SHIT',
        forceCompactThousands: true,
        maxCharacters: 13,
      ),
      r'999.99K $SHIT',
    );
  });

  test('splitSwapSummaryAmountText keeps token symbol separate', () {
    final parts = splitSwapSummaryAmountText(r'999K $SHIT', _testShitAsset);
    expect(parts.amount, '999K');
    expect(parts.symbol, r'$SHIT');
  });

  testWidgets('review summary compacts long pay amount only', (tester) async {
    await tester.pumpWidget(
      _themeHarness(
        _reviewTestPage(
          direction: SwapDirection.externalToZec,
          sellAsset: _testShitAsset,
          receiveAsset: SwapAsset.zec,
          sellAmountText: r'999,999.99 $SHIT',
          receiveAmountText: '0.251 ZEC',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_review_trade_summary')),
        matching: find.text(r'999,999.99 $SHIT'),
      ),
      findsNothing,
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_review_pay_summary_amount',
      numberText: '999.99K',
      symbolText: r'$SHIT',
      cardKey: const ValueKey('swap_review_trade_summary'),
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_review_receive_summary_amount',
      numberText: '0.251',
      symbolText: 'ZEC',
      cardKey: const ValueKey('swap_review_trade_summary'),
    );
  });

  testWidgets('review summary compacts long receive amount only', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themeHarness(
        _reviewTestPage(
          direction: SwapDirection.zecToExternal,
          sellAsset: SwapAsset.zec,
          receiveAsset: _testShitAsset,
          sellAmountText: '0.251 ZEC',
          receiveAmountText: r'999,999.99 $SHIT',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_review_trade_summary')),
        matching: find.text(r'999,999.99 $SHIT'),
      ),
      findsNothing,
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_review_pay_summary_amount',
      numberText: '0.251',
      symbolText: 'ZEC',
      cardKey: const ValueKey('swap_review_trade_summary'),
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_review_receive_summary_amount',
      numberText: '999.99K',
      symbolText: r'$SHIT',
      cardKey: const ValueKey('swap_review_trade_summary'),
    );
  });

  testWidgets('review summary compacts both long amounts', (tester) async {
    await tester.pumpWidget(
      _themeHarness(
        _reviewTestPage(
          direction: SwapDirection.externalToZec,
          sellAsset: _testShitAsset,
          receiveAsset: SwapAsset.zec,
          sellAmountText: r'999,999.99 $SHIT',
          receiveAmountText: '888,888.88 ZEC',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final reviewSummary = find.byKey(
      const ValueKey('swap_review_trade_summary'),
    );
    expect(
      find.descendant(
        of: reviewSummary,
        matching: find.text(r'999,999.99 $SHIT'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: reviewSummary, matching: find.text('888,888.88 ZEC')),
      findsNothing,
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_review_pay_summary_amount',
      numberText: '999.99K',
      symbolText: r'$SHIT',
      cardKey: const ValueKey('swap_review_trade_summary'),
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_review_receive_summary_amount',
      numberText: '888.888K',
      symbolText: 'ZEC',
      cardKey: const ValueKey('swap_review_trade_summary'),
    );
  });

  testWidgets('review details show saved recipient identity', (tester) async {
    await tester.pumpWidget(
      _themeHarness(
        _reviewTestPage(
          direction: SwapDirection.zecToExternal,
          sellAsset: SwapAsset.zec,
          receiveAsset: SwapAsset.usdc,
          sellAmountText: '0.251 ZEC',
          receiveAmountText: '999.99 USDC',
          addressBookContacts: [
            _addressBookContact(
              id: 'treasury',
              label: 'Treasury',
              network: AddressBookNetwork.ethereum,
              address: '0x52908400098527886E0F7030069857D2E4169EE7',
            ),
          ],
        ),
      ),
    );

    final details = find.byKey(const ValueKey('swap_review_details'));
    expect(
      find.descendant(of: details, matching: find.text('Treasury')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: details, matching: find.text('Ethereum')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: details, matching: find.text('0x52908…69ee7')),
      findsOneWidget,
    );
    final addressText = find.descendant(
      of: details,
      matching: find.text('0x52908…69ee7'),
    );
    expect(tester.widget<Text>(addressText).overflow, isNull);
    expect(
      find.ancestor(of: addressText, matching: find.byType(FittedBox)),
      findsOneWidget,
    );
  });

  testWidgets('review details show saved refund identity', (tester) async {
    await tester.pumpWidget(
      _themeHarness(
        _reviewTestPage(
          direction: SwapDirection.externalToZec,
          sellAsset: SwapAsset.usdc,
          receiveAsset: SwapAsset.zec,
          sellAmountText: '999.99 USDC',
          receiveAmountText: '0.251 ZEC',
          addressBookContacts: [
            _addressBookContact(
              id: 'refund',
              label: 'Refund wallet',
              network: AddressBookNetwork.ethereum,
              address: '0x52908400098527886e0f7030069857d2e4169ee7',
            ),
          ],
        ),
      ),
    );

    final details = find.byKey(const ValueKey('swap_review_details'));
    expect(
      find.descendant(of: details, matching: find.text('Refund wallet')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: details, matching: find.text('Ethereum')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: details, matching: find.text('0x52908…69ee7')),
      findsOneWidget,
    );
    final addressText = find.descendant(
      of: details,
      matching: find.text('0x52908…69ee7'),
    );
    expect(tester.widget<Text>(addressText).overflow, isNull);
    expect(
      find.ancestor(of: addressText, matching: find.byType(FittedBox)),
      findsOneWidget,
    );
  });

  testWidgets('deposit tokens countdown starts in the final fifteen minutes', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 5, 26, 0, 0);
    final expiresAt = now.add(const Duration(minutes: 16));

    await tester.pumpWidget(
      _themeHarness(
        SwapDepositTokensPageContent(
          asset: SwapAsset.usdc,
          amountText: '999.99 USDC',
          depositAddress: '0x123kjhc4e984ac1832f10aa4x98g20',
          expiresInLabel: '16mins',
          expiresAt: expiresAt,
          now: () => now,
          onDeposited: () {},
        ),
      ),
    );

    String expiryLabel() {
      return tester
          .widget<RichText>(
            find.byKey(const ValueKey('swap_deposit_expiry_label')),
          )
          .text
          .toPlainText();
    }

    expect(expiryLabel(), 'Deposit within 16mins');

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(expiryLabel(), 'Deposit within 15mins');

    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(expiryLabel(), 'Deposit within 14:59');

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(expiryLabel(), 'Deposit within 14:58');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('deposit tokens hour labels stay rounded and singularized', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 5, 26, 0, 0);
    final expiresAt = now.add(const Duration(hours: 2));

    await tester.pumpWidget(
      _themeHarness(
        SwapDepositTokensPageContent(
          asset: SwapAsset.usdc,
          amountText: '999.99 USDC',
          depositAddress: '0x123kjhc4e984ac1832f10aa4x98g20',
          expiresInLabel: '2hrs',
          expiresAt: expiresAt,
          now: () => now,
          onDeposited: () {},
        ),
      ),
    );

    String expiryLabel() {
      return tester
          .widget<RichText>(
            find.byKey(const ValueKey('swap_deposit_expiry_label')),
          )
          .text
          .toPlainText();
    }

    expect(expiryLabel(), 'Deposit within 2hrs');

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(expiryLabel(), 'Deposit within 2hrs');

    now = DateTime.utc(2026, 5, 26, 1, 0);
    await tester.pump(const Duration(hours: 1));
    expect(expiryLabel(), 'Deposit within 1hr');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('deposit timeout uses theme-specific failure illustration', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themeHarnessWithTheme(
        AppThemeData.light,
        SwapDepositTimeoutPageContent(onRestart: () {}),
      ),
    );

    expect(find.text('Deposit tokens'), findsNothing);
    expect(find.text('Time’s up'), findsOneWidget);
    expect(find.text('Swap failed'), findsOneWidget);
    expect(find.text('Restart swap'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('swap_deposit_restart_button')),
          )
          .variant,
      AppButtonVariant.secondary,
    );
    expect(
      (tester
                  .widget<Image>(
                    find.byKey(
                      const ValueKey('swap_deposit_timeout_illustration'),
                    ),
                  )
                  .image
              as AssetImage)
          .assetName,
      'assets/illustrations/swap_deposit_timeout_illustration_light.png',
    );

    await tester.pumpWidget(
      _themeHarnessWithTheme(
        AppThemeData.dark,
        SwapDepositTimeoutPageContent(onRestart: () {}),
      ),
    );

    expect(
      (tester
                  .widget<Image>(
                    find.byKey(
                      const ValueKey('swap_deposit_timeout_illustration'),
                    ),
                  )
                  .image
              as AssetImage)
          .assetName,
      'assets/illustrations/swap_deposit_timeout_illustration_dark.png',
    );
  });

  testWidgets(
    'expired deposit timeout content stays centered in activity detail',
    (tester) async {
      await _setViewport(tester, const Size(1080, 720));
      final sessionStore = _FakeSwapPersistenceStore(
        initialIntents: [
          _persistedIntent(
            id: 'expired-deposit',
            txHash: '',
            status: SwapIntentStatus.expired,
            nextAction: 'Start a fresh quote',
          ),
        ],
      );

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/activity/swap/expired-deposit?from=swap',
            routes: [_swapRoute(), _swapActivityRoute()],
          ),
          seedSwapActivityFixtures: false,
          sessionStore: sessionStore,
        ),
      );
      await _pumpUntilPresent(
        tester,
        find.byKey(const ValueKey('swap_deposit_timeout_panel')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Time’s up'), findsOneWidget);
      expect(find.text('Restart swap'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('swap_near_intents_attribution')),
        findsOneWidget,
      );
      final detailRect = tester.getRect(
        find.byKey(const ValueKey('swap_activity_detail_page')),
      );
      final timeoutRect = tester.getRect(
        find.byKey(const ValueKey('swap_deposit_timeout_panel')),
      );
      final attributionRect = tester.getRect(
        find.byKey(const ValueKey('swap_near_intents_attribution')),
      );

      expect(timeoutRect.size, const Size(274, 388));
      expect(timeoutRect.center.dy, closeTo(detailRect.center.dy, 1));
      expect(timeoutRect.bottom, lessThan(attributionRect.top));
    },
  );

  testWidgets('swap status summary calculates fiat per asset side', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1080, 720));
    final sessionStore = _FakeSwapPersistenceStore(
      initialIntents: [
        _persistedIntent(
          id: 'status-fiat',
          txHash: '',
          status: SwapIntentStatus.complete,
          nextAction: 'Swap complete',
        ).copyWith(
          receiveEstimate: '123.45 USDC',
          fiatValueBasis: SwapFiatValueBasis(
            capturedAt: DateTime.utc(2026, 5, 7, 10),
            sellUsdUnitPrice: 70.1733333333,
            receiveUsdUnitPrice: 1,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/activity/swap/status-fiat?from=swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: _PricingSwapProvider([70.1733333333]),
        seedSwapActivityFixtures: false,
        sessionStore: sessionStore,
      ),
    );
    await _pumpUntilPresent(
      tester,
      find.byKey(const ValueKey('swap_status_summary_card')),
    );
    await tester.pumpAndSettle();

    final summary = find.byKey(const ValueKey('swap_status_summary_card'));
    expect(
      find.descendant(of: summary, matching: find.text(r'$105.26')),
      findsWidgets,
    );
    expect(
      find.descendant(of: summary, matching: find.text(r'$123.45')),
      findsWidgets,
    );
  });

  testWidgets(
    'status page blinks live quote signal and cycles loader highlight',
    (tester) async {
      await tester.pumpWidget(_themeHarness(_statusTestPage()));

      expect(
        tester.getSize(find.byKey(const ValueKey('swap_status_summary_card'))),
        const Size(400, 120),
      );
      final statusSummary = find.byKey(
        const ValueKey('swap_status_summary_card'),
      );
      expect(
        find.descendant(
          of: statusSummary,
          matching: find.byKey(const ValueKey('swap_asset_chain_badge_zec')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: statusSummary,
          matching: find.byKey(const ValueKey('swap_asset_chain_badge_usdc')),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('swap_status_badge_liveQuote')),
        ),
        const Size(167, 25),
      );
      final liveQuoteBadgeRect = tester.getRect(
        find.byKey(const ValueKey('swap_status_badge_liveQuote')),
      );
      final liveQuoteTextRect = tester.getRect(find.text('In progress'));
      expect(
        (liveQuoteTextRect.top - liveQuoteBadgeRect.top).abs(),
        lessThan(1),
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('swap_status_live_quote_led_opacity')),
            )
            .opacity,
        1,
      );
      expect(
        find.byKey(const ValueKey('swap_status_active_step_loader')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('swap_progress_route')))
            .height,
        206,
      );
      expect(
        tester.getSize(
          find.byKey(
            const ValueKey('swap_activity_copy_near_intents_explorer_button'),
          ),
        ),
        const Size(256, 44),
      );
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('swap_activity_route_step_0_active')),
            )
            .height,
        84,
      );
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('swap_activity_route_step_1_pending')),
            )
            .height,
        37,
      );
      expect(
        find.byKey(const ValueKey('swap_status_active_step_spinner_rotation')),
        findsNothing,
      );

      final firstLineRect = tester.getRect(
        find.byKey(const ValueKey('swap_activity_route_step_0_line')),
      );
      final secondLineRect = tester.getRect(
        find.byKey(const ValueKey('swap_activity_route_step_1_line')),
      );
      expect(firstLineRect.center.dx, secondLineRect.center.dx);

      await tester.pump(const Duration(milliseconds: 121));
      expect(
        find.byKey(const ValueKey('swap_status_active_step_loader')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 901));

      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('swap_status_live_quote_led_opacity')),
            )
            .opacity,
        0.42,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('status summary compacts long pay amount only', (tester) async {
    await tester.pumpWidget(
      _themeHarness(
        _statusTestPage(
          payAmountText: r'999,999.99 $SHIT',
          receiveAmountText: '0.251 ZEC',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_status_summary_card')),
        matching: find.text(r'999,999.99 $SHIT'),
      ),
      findsNothing,
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_status_pay_summary_amount',
      numberText: '999K',
      symbolText: r'$SHIT',
      cardKey: const ValueKey('swap_status_summary_card'),
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_status_receive_summary_amount',
      numberText: '0.251',
      symbolText: 'ZEC',
      cardKey: const ValueKey('swap_status_summary_card'),
    );
  });

  testWidgets('status summary compacts long receive amount only', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themeHarness(
        _statusTestPage(
          payAmountText: '0.251 ZEC',
          receiveAmountText: r'999,999.99 $SHIT',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_status_summary_card')),
        matching: find.text(r'999,999.99 $SHIT'),
      ),
      findsNothing,
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_status_pay_summary_amount',
      numberText: '0.251',
      symbolText: 'ZEC',
      cardKey: const ValueKey('swap_status_summary_card'),
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_status_receive_summary_amount',
      numberText: '999K',
      symbolText: r'$SHIT',
      cardKey: const ValueKey('swap_status_summary_card'),
    );
  });

  testWidgets('status summary compacts both long card amounts', (tester) async {
    await tester.pumpWidget(
      _themeHarness(
        _statusTestPage(
          payAmountText: r'999,999.99 $SHIT',
          receiveAmountText: '888,888.88 USDC',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final statusSummary = find.byKey(
      const ValueKey('swap_status_summary_card'),
    );
    expect(
      find.descendant(
        of: statusSummary,
        matching: find.text(r'999,999.99 $SHIT'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: statusSummary,
        matching: find.text('888,888.88 USDC'),
      ),
      findsNothing,
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_status_pay_summary_amount',
      numberText: '999K',
      symbolText: r'$SHIT',
      cardKey: const ValueKey('swap_status_summary_card'),
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_status_receive_summary_amount',
      numberText: '888K',
      symbolText: 'USDC',
      cardKey: const ValueKey('swap_status_summary_card'),
    );
  });

  testWidgets('status terminal cards match completed and failed variants', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _themeHarness(
        _statusTestPage(
          title: 'Swap completed',
          badgeKind: SwapStatusBadgeKind.completed,
          showTabs: false,
          details: const [
            SwapStatusDetailRowData(label: 'Account', value: 'John'),
            SwapStatusDetailRowData(
              label: 'USDC deposit to',
              value: '0x123kjhc ... 4x98g20',
              copyable: true,
            ),
            SwapStatusDetailRowData(
              label: 'Total fees',
              value: '~0.25 USDC',
              help: true,
            ),
            SwapStatusDetailRowData(
              label: 'Realized slippage',
              value: '0.25 USDC (0.27%)',
            ),
            SwapStatusDetailRowData(
              label: 'Timestamp',
              value: 'May 20, 2026 13:20',
            ),
          ],
        ),
      ),
    );

    final completedIcon = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('swap_status_badge_completed')),
        matching: find.byType(AppIcon),
      ),
    );
    expect(completedIcon.name, AppIcons.checkCircle);
    expect(completedIcon.size, 16);
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('swap_status_summary_receive_opacity')),
          )
          .opacity,
      1,
    );

    final completedCardRect = tester.getRect(
      find.byKey(const ValueKey('swap_status_summary_card')),
    );
    final completedBadgeRect = tester.getRect(
      find.byKey(const ValueKey('swap_status_badge_completed')),
    );
    expect(completedBadgeRect.top, lessThan(completedCardRect.bottom));
    expect(completedCardRect.bottom - completedBadgeRect.top, closeTo(1, 0.1));

    await tester.pumpWidget(
      _themeHarness(
        _statusTestPage(
          title: 'Swap failed',
          badgeKind: SwapStatusBadgeKind.failed,
          showTabs: false,
          details: const [
            SwapStatusDetailRowData(label: 'Account', value: 'John'),
            SwapStatusDetailRowData(
              label: 'USDC refunded to',
              value: '0x123kjhc ... 4x98g20',
            ),
            SwapStatusDetailRowData(
              label: 'Total fees',
              value: '~0.25 USDC',
              help: true,
            ),
            SwapStatusDetailRowData(
              label: 'Timestamp',
              value: 'May 20, 2026 13:20',
            ),
          ],
        ),
      ),
    );

    final failedIcon = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('swap_status_badge_failed')),
        matching: find.byType(AppIcon),
      ),
    );
    expect(failedIcon.name, AppIcons.skull);
    expect(failedIcon.size, 16);
    final failedCardRect = tester.getRect(
      find.byKey(const ValueKey('swap_status_summary_card')),
    );
    final failedBadgeRect = tester.getRect(
      find.byKey(const ValueKey('swap_status_badge_failed')),
    );
    expect(failedBadgeRect.top, lessThan(failedCardRect.bottom));
    expect(failedCardRect.bottom - failedBadgeRect.top, closeTo(1, 0.1));
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('swap_status_summary_receive_opacity')),
          )
          .opacity,
      0.5,
    );
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('swap_status_summary_divider_opacity')),
          )
          .opacity,
      0.5,
    );

    final feeLabelRect = tester.getRect(find.text('Total fees'));
    final feeValueRect = tester.getRect(find.text('~0.25 USDC'));
    final finalDetailsRect = tester.getRect(
      find.byKey(const ValueKey('swap_final_details')),
    );
    final feeHelpIconRect = tester.getRect(
      find
          .descendant(
            of: find.byKey(const ValueKey('swap_final_details')),
            matching: find.byWidgetPredicate(
              (widget) => widget is AppIcon && widget.name == AppIcons.help,
            ),
          )
          .first,
    );
    expect(feeLabelRect.left, lessThan(feeValueRect.left));
    expect(feeValueRect.right, greaterThan(feeLabelRect.right));
    expect(feeValueRect.right, lessThan(feeHelpIconRect.left));
    expect(
      feeHelpIconRect.right,
      closeTo(finalDetailsRect.right - AppSpacing.sm, 1),
    );
  });

  testWidgets('status progress advances skipped steps one at a time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themeHarness(
        _statusTestPage(
          progressIndex: 0,
          progressAdvanceInterval: const Duration(milliseconds: 20),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('swap_activity_route_step_0_active')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _themeHarness(
        _statusTestPage(
          progressIndex: 2,
          progressAdvanceInterval: const Duration(milliseconds: 20),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('swap_activity_route_step_1_active')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_activity_route_step_2_active')),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 21));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('swap_activity_route_step_2_active')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('status progress text keeps title left and check time right', (
    tester,
  ) async {
    await tester.pumpWidget(_themeHarness(_statusTestPage(progressIndex: 1)));

    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('swap_activity_route_step_1_title_row')),
          )
          .height,
      24,
    );

    final titleRect = tester.getRect(find.text('Deposit confirmation...'));
    final checkedRect = tester.getRect(find.text('Last check: just now'));
    final descriptionRect = tester.getRect(
      find.text('Confirming the deposit.'),
    );

    expect(titleRect.left, lessThan(checkedRect.left));
    expect(checkedRect.right, greaterThan(titleRect.right));
    expect((descriptionRect.left - titleRect.left).abs(), lessThan(1));
  });

  testWidgets('status details tab starts collapsed and expands more details', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    var expanded = false;
    await tester.pumpWidget(
      _themeHarness(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => StatefulBuilder(
                builder: (context, setState) {
                  return _statusTestPage(
                    activeTab: SwapStatusTab.details,
                    detailsExpanded: expanded,
                    onToggleDetails: () => setState(() => expanded = !expanded),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('swap_transaction_details_collapsed')),
      findsOneWidget,
    );
    expect(find.text('Transaction details'), findsOneWidget);
    expect(find.text('More details'), findsOneWidget);
    expect(find.text('Slippage tolerance'), findsNothing);
    expect(
      find.ancestor(
        of: find.text('Swap Progress'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is MouseRegion &&
              widget.cursor == SystemMouseCursors.click,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Transaction details'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is MouseRegion &&
              widget.cursor == SystemMouseCursors.click,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('More details'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is MouseRegion &&
              widget.cursor == SystemMouseCursors.click,
        ),
      ),
      findsOneWidget,
    );

    final accountLabelRect = tester.getRect(find.text('Account'));
    final accountValueRect = tester.getRect(find.text('John'));
    final refundLabelRect = tester.getRect(find.text('USDC refund address'));
    final depositLabelRect = tester.getRect(find.text('Deposit USDC to'));
    final refundValueRect = tester.getRect(
      find.text('0x123kjhc ... 4x98g20').first,
    );
    final feeLabelRect = tester.getRect(find.text('Swap fee'));
    final feeValueRect = tester.getRect(find.text('Included in shown rate'));
    final feeHelpIconRect = tester.getRect(
      find
          .descendant(
            of: find.byKey(
              const ValueKey('swap_transaction_details_collapsed'),
            ),
            matching: find.byWidgetPredicate(
              (widget) => widget is AppIcon && widget.name == AppIcons.help,
            ),
          )
          .first,
    );

    expect(accountLabelRect.left, lessThan(accountValueRect.left));
    expect(accountValueRect.right, greaterThan(accountLabelRect.right));
    expect(feeLabelRect.left, lessThan(feeValueRect.left));
    expect(feeValueRect.right, greaterThan(feeLabelRect.right));
    expect((refundLabelRect.left - accountLabelRect.left).abs(), lessThan(1));
    expect((depositLabelRect.left - accountLabelRect.left).abs(), lessThan(1));
    expect((feeLabelRect.left - accountLabelRect.left).abs(), lessThan(1));
    expect(feeValueRect.right, lessThan(feeHelpIconRect.left));
    expect((refundValueRect.right - feeHelpIconRect.right).abs(), lessThan(1));

    await tester.tap(find.text('More details'));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('swap_transaction_details_expanded')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('swap_transaction_details_expanded')),
          )
          .height,
      192,
    );
    expect(
      find.byKey(const ValueKey('swap_transaction_details_scrollbar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_transaction_details_scroll_view')),
      findsOneWidget,
    );
    expect(find.text('Less details'), findsOneWidget);
    expect(find.text('Slippage tolerance'), findsOneWidget);
    expect(find.text('Price protection'), findsNothing);
    expect(_tooltipWithMessage(swapFeeTooltip), findsOneWidget);
    expect(
      _tooltipWithMessage(swapGenericMinimumReceiveTooltip),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Less details'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is MouseRegion &&
              widget.cursor == SystemMouseCursors.click,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('status details render address book labels with addresses', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _themeHarness(
        _statusTestPage(
          activeTab: SwapStatusTab.details,
          details: const [
            SwapStatusDetailRowData(label: 'Account', value: 'John'),
            SwapStatusDetailRowData(
              label: 'USDC recipient',
              value: '0x123kjhc ... 4x98g20',
              copyable: true,
              addressBookLabel: 'Treasury',
              addressNetwork: AddressBookNetwork.ethereum,
            ),
            SwapStatusDetailRowData(
              label: 'Swap fee',
              value: 'Included in shown rate',
              help: true,
            ),
          ],
        ),
      ),
    );

    expect(find.text('USDC recipient'), findsOneWidget);
    expect(find.text('Treasury'), findsOneWidget);
    expect(find.text('0x123kjhc ... 4x98g20'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('0x123kjhc ... 4x98g20')).overflow,
      isNull,
    );
    expect(
      find.ancestor(
        of: find.text('0x123kjhc ... 4x98g20'),
        matching: find.byType(FittedBox),
      ),
      findsOneWidget,
    );
    // The matched-contact cell renders the network chip beside the address.
    expect(find.byType(AddressBookNetworkIcon), findsOneWidget);
  });

  testWidgets('status details absorb saved address row overflow', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _themeHarness(
        _statusTestPage(
          activeTab: SwapStatusTab.details,
          details: const [
            SwapStatusDetailRowData(label: 'Account', value: 'John'),
            SwapStatusDetailRowData(
              label: 'USDC recipient',
              value: '0x1234567…89abc',
              copyable: true,
              addressBookLabel: 'eth account',
              addressNetwork: AddressBookNetwork.ethereum,
            ),
            SwapStatusDetailRowData(
              label: 'Deposit ZEC to',
              value: 't1V4tMBk8 ... hunXYpe',
            ),
            SwapStatusDetailRowData(
              label: 'Swap fee',
              value: 'Included in shown rate',
              help: true,
            ),
            SwapStatusDetailRowData(
              label: 'Slippage tolerance',
              value: '0.01 USDC (1.0%)',
            ),
            SwapStatusDetailRowData(
              label: 'Guaranteed minimum',
              value: '52.00 USDC',
              help: true,
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('swap_transaction_details_collapsed')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('swap_transaction_details_collapsed_scroll_view'),
      ),
      findsOneWidget,
    );
    expect(find.text('eth account'), findsOneWidget);
    expect(find.text('More details'), findsOneWidget);
  });

  testWidgets(
    'status details expanded use case starts inside the scroll range',
    (tester) async {
      await _setDesktopViewport(tester);
      await tester.pumpWidget(
        _themeHarness(
          _statusTestPage(
            activeTab: SwapStatusTab.details,
            detailsExpanded: true,
          ),
        ),
      );
      await tester.pump();

      final scrollView = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('swap_transaction_details_scroll_view')),
      );
      final controller = scrollView.controller!;

      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('swap_transaction_details_expanded')),
            )
            .height,
        192,
      );
      expect(controller.offset, controller.position.maxScrollExtent);
    },
  );

  testWidgets('swap tab renders composer and privacy check', (tester) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Swap'), findsWidgets);
    expect(find.byKey(const ValueKey('swap_page_title')), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_desktop_monitor')), findsNothing);
    expect(find.text('Wait for shielding confirmation'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_monitor_open_activity_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_monitor_refresh_button')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('swap_compact_ticket')), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_rate_line')), findsOneWidget);
    expect(find.text('Draft'), findsNothing);
    expect(find.text('You pay'), findsOneWidget);
    expect(find.text('You receive'), findsOneWidget);
    expect(find.text('From'), findsNothing);
    expect(find.text('To'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_external_asset_selector')),
      findsWidgets,
    );
    expect(find.byKey(const ValueKey('swap_address_summary')), findsOneWidget);
    final addressFieldHeight = tester
        .getSize(find.byKey(const ValueKey('swap_address_summary')))
        .height;
    final addressFieldWidth = tester
        .getSize(find.byKey(const ValueKey('swap_address_summary')))
        .width;
    expect(addressFieldHeight, 32);
    expect(addressFieldWidth, closeTo(196, 1));
    expect(find.text('Ethereum recipient'), findsNothing);
    expect(find.text('Add Recipient address...'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_settlement_path_placeholder')),
      findsNothing,
    );
    expect(find.text('Settlement path'), findsNothing);
    expect(find.text('Enter a trade'), findsNothing);
    expect(find.text('Add recipient address'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_near_intents_attribution')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('swap_review_button'))).width,
      closeTo(256, 1),
    );
    expect(
      find.descendant(
        of: find.byType(SwapScreen),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_review_button')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name != AppIcons.loader,
        ),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_review_button')),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_review_button')),
        matching: find.byType(SvgPicture),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_fiat_value_mode_icon')),
      findsOneWidget,
    );
    final titleRect = tester.getRect(
      find.byKey(const ValueKey('swap_page_title')),
    );
    final ticketRect = tester.getRect(
      find.byKey(const ValueKey('swap_compact_ticket')),
    );
    final rateLineRect = tester.getRect(
      find.byKey(const ValueKey('swap_rate_line')),
    );
    final settingsRowRect = tester.getRect(
      find.byKey(const ValueKey('swap_settings_row')),
    );
    final reviewButtonRect = tester.getRect(
      find.byKey(const ValueKey('swap_review_button')),
    );
    final attributionRect = tester.getRect(
      find.byKey(const ValueKey('swap_near_intents_attribution')),
    );
    final attributionPoweredRect = tester.getRect(
      find.byKey(const ValueKey('swap_near_intents_powered_by')),
    );
    final attributionWordmarkRect = tester.getRect(
      find.byKey(const ValueKey('swap_near_intents_wordmark')),
    );
    final paneRect = tester.getRect(find.byType(AppDesktopPane));
    expect(ticketRect.top - titleRect.bottom, closeTo(AppSpacing.md, 1));
    expect((ticketRect.center.dy - 491).abs(), lessThan(48));
    expect(ticketRect.height, lessThan(440));
    expect(reviewButtonRect.center.dx, closeTo(ticketRect.center.dx, 1));
    expect(settingsRowRect.height, closeTo(32, 1));
    expect(reviewButtonRect.top - settingsRowRect.bottom, closeTo(38, 1));
    expect(rateLineRect.center.dy, closeTo(settingsRowRect.center.dy, 1));
    expect(attributionRect.width, closeTo(90, 1));
    expect(attributionRect.height, closeTo(27.52, 1));
    expect(attributionPoweredRect.size.width, closeTo(64.296, 1));
    expect(attributionPoweredRect.size.height, closeTo(10.32, 1));
    expect(attributionWordmarkRect.size.width, closeTo(90, 1));
    expect(attributionWordmarkRect.size.height, closeTo(11, 1));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_near_intents_attribution')),
        matching: find.byType(SvgPicture),
      ),
      findsNWidgets(2),
    );
    final poweredBySvg = tester.widget<SvgPicture>(
      find.byKey(const ValueKey('swap_near_intents_powered_by')),
    );
    final poweredByLoader = poweredBySvg.bytesLoader;
    expect(poweredByLoader, isA<SvgAssetLoader>());
    expect(
      (poweredByLoader as SvgAssetLoader).assetName,
      'assets/icons/near_intents_powered_by.svg',
    );
    final wordmarkSvg = tester.widget<SvgPicture>(
      find.byKey(const ValueKey('swap_near_intents_wordmark')),
    );
    final wordmarkLoader = wordmarkSvg.bytesLoader;
    expect(wordmarkLoader, isA<SvgAssetLoader>());
    expect(
      (wordmarkLoader as SvgAssetLoader).assetName,
      'assets/icons/near_intents_wordmark.svg',
    );
    expect(
      attributionPoweredRect.left,
      closeTo(attributionWordmarkRect.left, 1),
    );
    expect(
      attributionWordmarkRect.top - attributionPoweredRect.bottom,
      closeTo(6.2, 1),
    );
    expect(attributionRect.left, closeTo(paneRect.left + AppSpacing.md, 1));
    expect(
      paneRect.bottom - attributionRect.bottom,
      closeTo(AppSpacing.md + 0.48, 1),
    );
    expect(find.byKey(const ValueKey('swap_ticket_tabs')), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_activity_open_count')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('swap_page_tab_activity')), findsNothing);
    expect(find.byKey(const ValueKey('swap_page_tab_requests')), findsNothing);
    expect(find.text('Privacy check'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_privacy_scope_provider')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_privacy_scope_wallet')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_privacy_scope_network')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('swap_queue_title')), findsNothing);
    expect(find.text('Status timeline'), findsNothing);
    expect(find.text('Receipt'), findsNothing);
  });

  testWidgets('swap modal overlay is constrained to the desktop pane', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();

    expect(find.text('Ethereum address or account'), findsOneWidget);
    expect(find.text('NEAR or Ethereum address'), findsNothing);

    final paneRect = tester.getRect(find.byType(AppDesktopPane));
    final modalRect = tester.getRect(
      find.byKey(const ValueKey('swap_address_modal')),
    );
    final sidebarItemRect = tester.getRect(
      find.byKey(const ValueKey('sidebar_swap_button')),
    );

    expect((modalRect.center.dx - paneRect.center.dx).abs(), lessThan(1));
    expect((modalRect.center.dy - paneRect.center.dy).abs(), lessThan(1));
    expect(modalRect.left, greaterThan(sidebarItemRect.right));
  });

  testWidgets('address scan modal is constrained to the desktop pane', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_address_scan_button')));
    await tester.pump(const Duration(milliseconds: 100));

    final paneRect = tester.getRect(find.byType(AppDesktopPane));
    final modalRect = tester.getRect(
      find.byKey(const ValueKey('address_scan_modal')),
    );
    final cameraRect = tester.getRect(
      find.byKey(const ValueKey('address_scan_camera_viewport')),
    );
    final sidebarItemRect = tester.getRect(
      find.byKey(const ValueKey('sidebar_swap_button')),
    );

    expect(find.text('Scan the address QR Code'), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_address_modal')), findsNothing);
    expect((modalRect.center.dx - paneRect.center.dx).abs(), lessThan(1));
    expect((modalRect.center.dy - paneRect.center.dy).abs(), lessThan(1));
    expect(modalRect.left, greaterThan(sidebarItemRect.right));
    expect(modalRect.size, const Size(312, 440));
    expect(cameraRect.size, const Size(272, 220));
  });

  testWidgets('address scan modal content matches camera state layouts', (
    tester,
  ) async {
    Future<void> pumpStatus(
      AddressQrCameraStatus status, {
      Widget? cameraView,
      bool canChooseCamera = false,
      VoidCallback? onCameraTap,
      VoidCallback? onRetry,
    }) async {
      await tester.pumpWidget(
        _themeHarness(
          Center(
            child: AddressQrScanModalContent(
              status: status,
              cameraView: cameraView,
              canChooseCamera: canChooseCamera,
              onCameraTap: onCameraTap,
              onRetry: onRetry,
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpStatus(AddressQrCameraStatus.requesting);

    expect(
      tester.getSize(find.byKey(const ValueKey('address_scan_modal'))),
      const Size(312, 440),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('address_scan_camera_modal'))),
      const Size(272, 276),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('address_scan_camera_viewport')),
      ),
      const Size(272, 220),
    );
    expect(find.text('Grant access to your camera'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('address_scan_camera_footer_slot')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('address_scan_camera_border')),
      findsNothing,
    );

    await pumpStatus(AddressQrCameraStatus.denied, onRetry: () {});

    expect(find.text("You've denied Camera access"), findsOneWidget);
    expect(find.text('Allow camera'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('address_scan_retry_button')))
          .height,
      32,
    );
    expect(
      find.byKey(const ValueKey('address_scan_camera_footer_slot')),
      findsNothing,
    );

    await pumpStatus(
      AddressQrCameraStatus.active,
      cameraView: const ColoredBox(color: Color(0xFF2E3232)),
      canChooseCamera: true,
      onCameraTap: () {},
    );

    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('address_scan_camera_footer_slot')),
          )
          .height,
      40,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('address_scan_camera_footer')))
          .height,
      32,
    );
    expect(
      find.byKey(const ValueKey('address_scan_camera_border')),
      findsOneWidget,
    );

    await pumpStatus(
      AddressQrCameraStatus.loading,
      cameraView: const ColoredBox(color: Color(0xFF2E3232)),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      find.byKey(const ValueKey('address_scan_loading_overlay')),
      findsOneWidget,
    );
    expect(find.text('Loading...'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('address_scan_camera_border')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('address_scan_camera_footer_slot')),
          )
          .height,
      40,
    );
  });

  testWidgets('swap address modal blocks a malformed recipient address', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xnope',
    );
    await tester.pumpAndSettle();

    expect(find.text("Invalid EVM address"), findsOneWidget);
    final blockedButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('swap_address_update_button')),
    );
    expect(blockedButton.onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    expect(find.text("Invalid EVM address"), findsNothing);
    final allowedButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('swap_address_update_button')),
    );
    expect(allowedButton.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('swap_address_update_button')));
    await tester.pumpAndSettle();

    expect(_destinationSummaryText(tester), '0x529084...169ee7');
  });

  testWidgets('swap address modal ignores keyboard submit of a bad address', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xnope',
    );
    await tester.pumpAndSettle();

    // Pressing keyboard "done" must not commit the malformed address.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_address_modal')), findsOneWidget);
    expect(_destinationSummaryText(tester), isEmpty);
  });

  testWidgets('swap review button surfaces an invalid destination address', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    // Simulate a non-modal path (contact picker / retry) setting a malformed
    // address directly into state.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SwapScreen)),
      listen: false,
    );
    container.read(swapStateProvider.notifier).updateDestination('0xnope');
    await tester.pumpAndSettle();

    expect(find.text('Invalid EVM address'), findsOneWidget);
    final button = tester.widget<AppButton>(
      find.byKey(const ValueKey('swap_review_button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('swap address modal loads recipient address from contacts', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        addressBookRepository: _FakeAddressBookRepository([
          _addressBookContact(
            id: 'usdc',
            label: 'USDC Friend',
            network: AddressBookNetwork.ethereum,
            address: '0xd1220a0cf47c7b9be7a2e6ba89f429762e7b9adb',
          ),
          _addressBookContact(
            id: 'zcash',
            label: 'Zcash Friend',
            network: AddressBookNetwork.zcash,
            address: 'u1zcashfriend',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('swap_address_contacts_button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('address_book_contact_picker_modal')),
      findsOneWidget,
    );
    expect(find.text('USDC Friend'), findsOneWidget);
    expect(find.text('Zcash Friend'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_picker_contact_usdc')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('address_book_contact_picker_modal')),
      findsNothing,
    );
    expect(_destinationSummaryText(tester), '0xd1220a...7b9adb');
  });

  testWidgets('swap contact picker cancel returns to address editor', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        addressBookRepository: _FakeAddressBookRepository([
          _addressBookContact(
            id: 'usdc',
            label: 'USDC Friend',
            network: AddressBookNetwork.ethereum,
            address: '0xd1220a0cf47c7b9be7a2e6ba89f429762e7b9adb',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('swap_address_contacts_button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('address_book_contact_picker_modal')),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('Close contacts'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('address_book_contact_picker_modal')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('swap_address_modal')), findsOneWidget);
  });

  testWidgets('swap address modal remembers submitted recipient', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final addressBookRepository = _FakeAddressBookRepository();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        addressBookRepository: addressBookRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xdbf03b407c01e7cd3cbea99509d93f8dddc8c6fb',
    );
    await tester.tap(
      find.byKey(const ValueKey('swap_address_remember_toggle')),
    );
    await tester.pumpAndSettle();

    // Enabling "remember" requires a nickname before the address can be saved.
    final beforeNickname = tester.widget<AppButton>(
      find.byKey(const ValueKey('swap_address_update_button')),
    );
    expect(beforeNickname.onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('swap_address_nickname_field')),
      'My USDC',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_address_update_button')));
    await tester.pumpAndSettle();

    expect(addressBookRepository.contacts, hasLength(1));
    expect(
      addressBookRepository.contacts.single.address,
      '0xdbf03b407c01e7cd3cbea99509d93f8dddc8c6fb',
    );
    expect(
      addressBookRepository.contacts.single.network,
      AddressBookNetwork.ethereum,
    );
    expect(addressBookRepository.contacts.single.label, 'My USDC');
  });

  testWidgets('swap address modal requires a valid nickname to remember', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final addressBookRepository = _FakeAddressBookRepository();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        addressBookRepository: addressBookRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xdbf03b407c01e7cd3cbea99509d93f8dddc8c6fb',
    );
    await tester.pumpAndSettle();

    // No nickname field until the user opts to remember the address.
    expect(
      find.byKey(const ValueKey('swap_address_nickname_field')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('swap_address_remember_toggle')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('swap_address_nickname_field')),
      findsOneWidget,
    );

    // A nickname over the 20-char limit surfaces the shared address-book label
    // error and keeps the button disabled, so nothing is saved.
    await tester.enterText(
      find.byKey(const ValueKey('swap_address_nickname_field')),
      'this nickname is definitely too long',
    );
    await tester.pumpAndSettle();

    expect(find.text('Use 1-20 characters'), findsOneWidget);
    final blocked = tester.widget<AppButton>(
      find.byKey(const ValueKey('swap_address_update_button')),
    );
    expect(blocked.onPressed, isNull);
    expect(addressBookRepository.contacts, isEmpty);
  });

  testWidgets('swap address modal warns when the address is already saved', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    const existing = '0x52908400098527886e0f7030069857d2e4169ee7';
    final addressBookRepository = _FakeAddressBookRepository([
      _addressBookContact(
        id: 'existing',
        label: 'Existing',
        network: AddressBookNetwork.ethereum,
        address: existing,
      ),
    ]);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        addressBookRepository: addressBookRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      existing,
    );
    await tester.tap(
      find.byKey(const ValueKey('swap_address_remember_toggle')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('swap_address_nickname_field')),
      'Duplicate',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_address_update_button')));
    // Let the async remember-path run and the toast appear; avoid
    // pumpAndSettle here since it would wait out the toast's auto-dismiss.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Already in your address book'), findsOneWidget);
    // No duplicate created — still just the seeded contact.
    expect(addressBookRepository.contacts, hasLength(1));

    // Drain the toast's auto-dismiss timer so the test ends cleanly.
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('swap clears the destination only when the chain changes', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SwapScreen)),
      listen: false,
    );
    final notifier = container.read(swapStateProvider.notifier);
    const ethAddress = '0x52908400098527886e0f7030069857d2e4169ee7';
    notifier.updateDestination(ethAddress);
    await tester.pumpAndSettle();

    // Same chain (Ethereum USDC -> Ethereum DAI): the address is kept.
    notifier.selectExternalAsset(SwapAsset.dai);
    await tester.pumpAndSettle();
    expect(container.read(swapStateProvider).destinationText, ethAddress);

    // Different chain (Ethereum -> Solana): the address is cleared.
    notifier.selectExternalAsset(SwapAsset.sol);
    await tester.pumpAndSettle();
    expect(container.read(swapStateProvider).destinationText, isEmpty);
  });

  testWidgets('swap address modal saves the chosen avatar with the address', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final addressBookRepository = _FakeAddressBookRepository();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        addressBookRepository: addressBookRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xdbf03b407c01e7cd3cbea99509d93f8dddc8c6fb',
    );
    await tester.tap(
      find.byKey(const ValueKey('swap_address_remember_toggle')),
    );
    await tester.pumpAndSettle();

    // Open the avatar picker and choose a non-default avatar.
    await tester.tap(find.byKey(const ValueKey('swap_address_avatar_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_address_avatar_pfp-02')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_address_nickname_field')),
      'My USDC',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_address_update_button')));
    await tester.pumpAndSettle();

    expect(addressBookRepository.contacts, hasLength(1));
    expect(addressBookRepository.contacts.single.label, 'My USDC');
    expect(addressBookRepository.contacts.single.profilePictureId, 'pfp-02');
  });

  testWidgets('swap address modal shows EVM contacts across chains', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final baseUsdc = SwapAsset.live(
      assetId: 'nep141:base-usdc.example',
      symbol: 'USDC',
      blockchain: 'base',
      decimals: 6,
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: _FakeSwapProvider(supportedAssets: [baseUsdc]),
        seedSwapActivityFixtures: false,
        addressBookRepository: _FakeAddressBookRepository([
          _addressBookContact(
            id: 'base',
            label: 'Base USDC Friend',
            network: AddressBookNetwork.base,
            address: '0xdc2d3454f7baf9f15c98e8f5d6a3cb5a5f1b2c3d',
          ),
          _addressBookContact(
            id: 'polygon',
            label: 'Polygon Friend',
            network: AddressBookNetwork.polygon,
            address: '0x583031d1113ad414f02576bd6afabfb302140225',
          ),
          _addressBookContact(
            id: 'solana',
            label: 'Solana Friend',
            network: AddressBookNetwork.solana,
            address: '7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('swap_address_contacts_button')),
    );
    await tester.pumpAndSettle();

    // EVM addresses are interchangeable across chains, so a Polygon contact is
    // usable as a Base refund/recipient — both EVM contacts show.
    expect(find.text('Base USDC Friend'), findsOneWidget);
    expect(find.text('Polygon Friend'), findsOneWidget);
    // Non-EVM contacts stay hidden.
    expect(find.text('Solana Friend'), findsNothing);
  });

  testWidgets('swap address modal keeps non-EVM contact filtering exact', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: _FakeSwapProvider(supportedAssets: const [SwapAsset.sol]),
        seedSwapActivityFixtures: false,
        addressBookRepository: _FakeAddressBookRepository([
          _addressBookContact(
            id: 'solana',
            label: 'Solana Friend',
            network: AddressBookNetwork.solana,
            address: '7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs',
          ),
          _addressBookContact(
            id: 'ethereum',
            label: 'Ethereum Friend',
            network: AddressBookNetwork.ethereum,
            address: '0x583031d1113ad414f02576bd6afabfb302140225',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('swap_address_contacts_button')),
    );
    await tester.pumpAndSettle();

    // Solana addresses are chain-specific, so only the Solana contact shows.
    expect(find.text('Solana Friend'), findsOneWidget);
    expect(find.text('Ethereum Friend'), findsNothing);
  });

  testWidgets('fresh swap screen starts without seeded activity or requests', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        sessionStore: _FakeSwapPersistenceStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_compact_ticket')), findsOneWidget);
    expect(find.text('Current swap'), findsNothing);

    await _openActivitySurface(tester);

    expect(find.text('No activity yet'), findsOneWidget);
    expect(find.text('Recovery receipt'), findsNothing);

    await _openSwapSurface(tester);

    expect(
      find.byKey(const ValueKey('swap_request_inbox_panel')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('swap_request_list_panel')), findsNothing);
  });

  testWidgets('swap activity ignores sessions from another account', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final sessionStore = _FakeSwapPersistenceStore(
      initialIntents: [
        _persistedIntent(
          id: 't1other-account',
          txHash: 'other-account-txid',
          accountUuid: 'account-2',
        ),
      ],
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(sessionStore.loadedAccounts, ['account-1']);

    await _openActivitySurface(tester);

    expect(find.text('No activity yet'), findsOneWidget);
    expect(find.text('other-account-txid'), findsNothing);
  });

  testWidgets('account switch ignores stale persisted intent restore', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final sessionStore = _DelayedLoadSwapPersistenceStore(
      delayedAccounts: {'account-1'},
      initialIntents: [
        _persistedIntent(
          id: 'account-one-stale-swap',
          txHash: 'account-one-stale-txid',
          accountUuid: 'account-1',
        ),
        _persistedIntent(
          id: 'account-two-current-swap',
          txHash: 'account-two-current-txid',
          accountUuid: 'account-2',
        ),
      ],
    );
    final accountNotifier = _FakeSwapAccountNotifier(
      _twoAccountBootstrap.initialAccountState,
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        bootstrap: _twoAccountBootstrap,
        accountNotifier: () => accountNotifier,
        sessionStore: sessionStore,
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SwapScreen)),
      listen: false,
    );
    await container.read(accountProvider.notifier).switchAccount('account-2');
    await tester.pump();
    await tester.pump();

    expect(
      container.read(swapStateProvider).intents.map((intent) => intent.id),
      ['account-two-current-swap'],
    );

    sessionStore.completeLoad('account-1');
    await tester.pump();
    await tester.pump();

    expect(
      container.read(swapStateProvider).intents.map((intent) => intent.id),
      ['account-two-current-swap'],
    );
  });

  testWidgets('account switch cancels in-flight quote review', (tester) async {
    await _setDesktopViewport(tester);
    final swapProvider = _DelayedQuoteSwapProvider();
    final accountNotifier = _FakeSwapAccountNotifier(
      _twoAccountBootstrap.initialAccountState,
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        bootstrap: _twoAccountBootstrap,
        accountNotifier: () => accountNotifier,
        swapProvider: swapProvider,
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SwapScreen)),
      listen: false,
    );
    await container.read(accountProvider.notifier).switchAccount('account-2');
    await tester.pump();

    swapProvider.completeQuote();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_review_panel')), findsNothing);
    expect(swapProvider.startedQuotes, isEmpty);
  });

  testWidgets('account switch restores composer preferences for the account', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final sessionStore = _FakeSwapPersistenceStore(
      initialPreferencesByAccount: const {
        'account-1': SwapComposerPreferences(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          slippageBps: 50,
        ),
        'account-2': SwapComposerPreferences(
          direction: SwapDirection.externalToZec,
          externalAsset: SwapAsset.near,
          slippageBps: 200,
        ),
      },
    );
    final accountNotifier = _FakeSwapAccountNotifier(
      _twoAccountBootstrap.initialAccountState,
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        bootstrap: _twoAccountBootstrap,
        accountNotifier: () => accountNotifier,
        sessionStore: sessionStore,
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SwapScreen)),
      listen: false,
    );
    expect(container.read(swapStateProvider).slippageBps, 50);

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await container.read(accountProvider.notifier).switchAccount('account-2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final accountTwoState = container.read(swapStateProvider);
    expect(accountTwoState.direction, SwapDirection.externalToZec);
    expect(accountTwoState.externalAsset, SwapAsset.near);
    expect(accountTwoState.slippageBps, 200);
    expect(accountTwoState.amountText, isEmpty);
    expect(accountTwoState.destinationText, isEmpty);
    expect(sessionStore.loadPreferencesCount, 2);
  });

  testWidgets('account switch closes open swap activity detail', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final sessionStore = _FakeSwapPersistenceStore(
      initialIntents: [
        _persistedIntent(
          id: 'account-one-swap',
          txHash: 'account-one-txid',
          accountUuid: 'account-1',
        ),
        _persistedIntent(
          id: 'account-two-swap',
          txHash: 'account-two-txid',
          accountUuid: 'account-2',
        ),
      ],
    );
    final accountNotifier = _FakeSwapAccountNotifier(
      _twoAccountBootstrap.initialAccountState,
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        bootstrap: _twoAccountBootstrap,
        accountNotifier: () => accountNotifier,
        sessionStore: sessionStore,
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    await _openActivitySurface(tester);
    await _openActivityDetail(tester, 'account-one-swap');
    expect(
      find.byKey(const ValueKey('swap_activity_detail_page')),
      findsOneWidget,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppDesktopShell).first),
      listen: false,
    );
    await container.read(accountProvider.notifier).switchAccount('account-2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(const ValueKey('swap_activity_detail_page')),
      findsNothing,
    );
    expect(find.text('Swapping...'), findsWidgets);

    await container.read(accountProvider.notifier).switchAccount('account-1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Swapping...'), findsWidgets);
    expect(
      find.byKey(const ValueKey('swap_activity_detail_page')),
      findsNothing,
    );
  });

  testWidgets('ZEC swap composer shows live balance and applies max amount', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final maxEstimator = _FakeSwapMaxAmountEstimator(
      maxZatoshi: BigInt.from(123390000),
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        sessionStore: _FakeSwapPersistenceStore(),
        spendableBalance: BigInt.from(123450000),
        maxAmountEstimator: maxEstimator,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Max: 1.2345 ZEC'), findsOneWidget);
    expect(find.text('Max: 12.48 ZEC'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_max_amount_button')));
    await tester.pumpAndSettle();

    expect(maxEstimator.requests, ['account-1']);
    expect(_fieldText(tester, 'swap_amount_field'), '1.2339');
  });

  testWidgets('ZEC max amount request keeps the max label spinner-free', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final maxEstimator = _CompletingSwapMaxAmountEstimator();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        sessionStore: _FakeSwapPersistenceStore(),
        spendableBalance: BigInt.from(123450000),
        maxAmountEstimator: maxEstimator,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_max_amount_button')));
    await tester.pump();

    expect(maxEstimator.requests, ['account-1']);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_max_amount_button')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.loader,
        ),
      ),
      findsNothing,
    );

    maxEstimator.complete(BigInt.from(123390000));
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'swap_amount_field'), '1.2339');
  });

  testWidgets('ZEC max amount ignores stale result after account switch', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final maxEstimator = _CompletingSwapMaxAmountEstimator();
    final accountNotifier = _FakeSwapAccountNotifier(
      _twoAccountBootstrap.initialAccountState,
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        bootstrap: _twoAccountBootstrap,
        accountNotifier: () => accountNotifier,
        seedSwapActivityFixtures: false,
        sessionStore: _FakeSwapPersistenceStore(),
        spendableBalance: BigInt.from(123450000),
        maxAmountEstimator: maxEstimator,
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SwapScreen)),
      listen: false,
    );
    unawaited(container.read(swapStateProvider.notifier).useMaxZecAmount());
    await tester.pump();

    expect(maxEstimator.requests, ['account-1']);

    await container.read(accountProvider.notifier).switchAccount('account-2');
    await tester.pump();

    maxEstimator.complete(BigInt.from(123390000));
    await tester.pumpAndSettle();

    final swapState = container.read(swapStateProvider);
    expect(swapState.amountText, isEmpty);
    expect(swapState.maxAmountLoading, isFalse);
  });

  testWidgets(
    'ZEC review is disabled when the amount reaches available balance',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _FakeSwapProvider();

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [_swapRoute(), _swapActivityRoute()],
          ),
          seedSwapActivityFixtures: false,
          spendableBalance: BigInt.from(100000000),
          swapProvider: swapProvider,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '1',
      );
      await _enterDestinationText(
        tester,
        '0x52908400098527886e0f7030069857d2e4169ee7',
      );
      await tester.pumpAndSettle();

      expect(find.text('Max: 1 ZEC'), findsOneWidget);
      expect(find.text('Not enough ZEC'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();

      expect(swapProvider.requests, isEmpty);
      expect(find.text('Review swap'), findsNothing);
    },
  );

  testWidgets('swap composer restores only the last attempted pair', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    final sessionStore = _FakeSwapPersistenceStore(
      initialPreferences: const SwapComposerPreferences(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.near,
        slippageBps: 125,
      ),
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(sessionStore.loadPreferencesCount, 1);
    expect(_fieldText(tester, 'swap_amount_field'), isEmpty);
    expect(_destinationSummaryText(tester), isEmpty);
    expect(find.text('Add Refund address...'), findsOneWidget);
    expect(find.text('NEAR'), findsWidgets);
    expect(find.text('Wallet staging'), findsNothing);
    expect(find.text('1.25%'), findsWidgets);
  });

  testWidgets('swap composer preserves the saved live asset chain', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    final baseUsdc = SwapAsset.live(
      assetId: 'nep141:base-usdc.example',
      symbol: 'USDC',
      blockchain: 'base',
      decimals: 6,
    );
    final sessionStore = _FakeSwapPersistenceStore(
      initialPreferences: SwapComposerPreferences(
        direction: SwapDirection.zecToExternal,
        externalAsset: baseUsdc,
        slippageBps: 50,
      ),
    );
    final swapProvider = _FakeSwapProvider(
      supportedAssets: [SwapAsset.usdc, baseUsdc, SwapAsset.near],
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        sessionStore: sessionStore,
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(sessionStore.loadPreferencesCount, 1);
    expect(find.text('Base'), findsWidgets);
    expect(find.text('Ethereum recipient'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('swap_external_asset_selector')).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('USDC networks'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_asset_row_usdc')),
        matching: find.text('Ethereum'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('swap_asset_row_nep141:base-usdc.example'),
        ),
        matching: find.text('Base'),
      ),
      findsOneWidget,
    );
    expect(find.text('USD Coin'), findsNothing);
    expect(find.text('Ethereum USDC'), findsNothing);
  });

  testWidgets('swap asset selector exposes multi-chain external assets', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('swap_external_asset_selector')).first,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('swap_external_asset_menu')),
      findsOneWidget,
    );
    expect(find.text('ETH'), findsOneWidget);
    expect(find.text('Ethereum'), findsWidgets);
    expect(find.text('Ethereum ETH'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('swap_asset_search_field')),
      'btc',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_asset_row_btc')), findsOneWidget);
    expect(find.text('BTC'), findsWidgets);
    expect(find.text('Bitcoin BTC'), findsNothing);
    expect(find.byKey(const ValueKey('swap_asset_row_sol')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_asset_row_btc')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_compact_ticket')), findsOneWidget);
    expect(find.text('You receive'), findsOneWidget);
    expect(find.text('BTC'), findsWidgets);
  });

  testWidgets('swap asset selector follows the live provider token list', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider(
      supportedAssets: const [SwapAsset.usdc, SwapAsset.near],
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('swap_external_asset_selector')).first,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_asset_row_usdc')), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_asset_row_near')), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_asset_row_eth')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('swap_asset_search_field')),
      'sol',
    );
    await tester.pumpAndSettle();

    expect(find.text('No tokens or chains found'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_asset_search_clear_button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('swap_asset_search_clear_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('No tokens or chains found'), findsNothing);
    expect(find.byKey(const ValueKey('swap_asset_row_usdc')), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_asset_row_near')), findsOneWidget);
  });

  testWidgets('swap asset selector has a click cursor and closes outside', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selectorCursor = tester.widget<MouseRegion>(
      find
          .ancestor(
            of: find
                .byKey(const ValueKey('swap_external_asset_selector'))
                .first,
            matching: find.byType(MouseRegion),
          )
          .first,
    );
    expect(selectorCursor.cursor, SystemMouseCursors.click);

    await tester.tap(
      find.byKey(const ValueKey('swap_external_asset_selector')).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('swap_external_asset_menu')),
      findsOneWidget,
    );
    final assetModal = tester.widget<Container>(
      find.byKey(const ValueKey('swap_external_asset_menu')),
    );
    final assetDecoration = assetModal.decoration as BoxDecoration;
    expect(assetModal.clipBehavior, Clip.antiAlias);
    expect(assetDecoration.color, AppThemeData.light.colors.background.base);
    expect(assetDecoration.borderRadius, BorderRadius.circular(AppRadii.large));
    expect(assetDecoration.boxShadow, _figmaModalSurfaceShadows);
    expect(
      find.byKey(const ValueKey('swap_asset_chain_badge_usdc')),
      findsWidgets,
    );
    final assetScrollbar = tester.widget<RawScrollbar>(
      find.byKey(const ValueKey('swap_asset_selector_scrollbar')),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_external_asset_menu')),
        matching: find.byType(RawScrollbar),
      ),
      findsOneWidget,
    );
    expect(assetScrollbar.thickness, 6);
    expect(assetScrollbar.mainAxisMargin, 3);
    expect(assetScrollbar.crossAxisMargin, 3);
    final assetListGutter = tester.widget<Padding>(
      find.byKey(const ValueKey('swap_asset_selector_list_gutter')),
    );
    expect(
      assetListGutter.padding,
      const EdgeInsets.only(right: AppSpacing.sm),
    );
    final assetMenuWidth = tester
        .getSize(find.byKey(const ValueKey('swap_external_asset_menu')))
        .width;
    final usdcRowWidth = tester
        .getSize(find.byKey(const ValueKey('swap_asset_row_usdc')))
        .width;
    expect(usdcRowWidth, assetMenuWidth - 48);

    await tester.tapAt(const Offset(1200, 64));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('swap_external_asset_menu')),
      findsNothing,
    );
  });

  testWidgets('slippage settings are sent with the next quote request', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final sessionStore = _FakeSwapPersistenceStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        seedSwapActivityFixtures: false,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_settings_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_slippage_modal')), findsOneWidget);
    expect(find.text('Slippage'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('swap_slippage_200bps')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_slippage_modal')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('swap_slippage_update_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_slippage_modal')), findsNothing);
    expect(find.text('2%'), findsWidgets);
    expect(sessionStore.savedPreferences?.slippageBps, 200);

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.requests.single.slippageBps, 200);
  });

  testWidgets('custom slippage settings are sent with the next quote request', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final sessionStore = _FakeSwapPersistenceStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        seedSwapActivityFixtures: false,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_settings_button')));
    await tester.pumpAndSettle();

    final slippageModalTop = tester
        .getTopLeft(find.byKey(const ValueKey('swap_slippage_modal')))
        .dy;
    final customCardTop = tester
        .getTopLeft(find.byKey(const ValueKey('swap_slippage_custom_card')))
        .dy;
    expect(customCardTop - slippageModalTop, 218);
    expect(
      tester.getSize(find.byKey(const ValueKey('swap_slippage_50bps'))).height,
      34,
    );
    final customInputFinder = find.byKey(
      const ValueKey('swap_slippage_custom_input'),
    );
    final percentFinder = find.byKey(
      const ValueKey('swap_slippage_custom_percent'),
    );
    final placeholderInputWidth = tester.getSize(customInputFinder).width;
    expect(placeholderInputWidth, greaterThan(31));
    expect(
      tester.widget<TextField>(customInputFinder).textAlign,
      TextAlign.right,
    );
    expect(
      tester.getTopLeft(percentFinder).dx -
          tester.getTopRight(customInputFinder).dx,
      closeTo(4, 0.1),
    );

    await tester.enterText(
      find.byKey(const ValueKey('swap_slippage_custom_input')),
      '1.25',
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(customInputFinder).width, placeholderInputWidth);
    expect(
      tester.getTopLeft(percentFinder).dx -
          tester.getTopRight(customInputFinder).dx,
      closeTo(4, 0.1),
    );

    await tester.tap(find.byKey(const ValueKey('swap_slippage_update_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_slippage_modal')), findsNothing);
    expect(find.text('1.25%'), findsWidgets);
    expect(sessionStore.savedPreferences?.slippageBps, 125);

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.requests.single.slippageBps, 125);
  });

  testWidgets('custom slippage outside range disables update', (tester) async {
    await _setDesktopViewport(tester);
    final sessionStore = _FakeSwapPersistenceStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_settings_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_slippage_custom_input')),
      '15',
    );
    await tester.pumpAndSettle();

    expect(find.text('Slippage must be 0.1 - 5%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('swap_slippage_update_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_slippage_modal')), findsOneWidget);
    expect(sessionStore.savedPreferences?.slippageBps, isNull);
  });

  testWidgets('slippage modal cancel keeps the existing setting', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final sessionStore = _FakeSwapPersistenceStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_settings_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_slippage_200bps')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_slippage_cancel_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_slippage_modal')), findsNothing);
    expect(sessionStore.savedPreferences?.slippageBps, isNull);
    expect(find.text('2%'), findsNothing);
  });

  testWidgets('draft conversion uses refreshed 1Click token prices', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _PricingSwapProvider(const [540.62]);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '0.01',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    expect(swapProvider.pricingRequests, 1);
    expect(_fieldText(tester, 'swap_receive_amount_field'), '5.40');
    expect(find.text('1 ZEC = 540.62 USDC'), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_rate_line')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_quote_details_strip')),
      findsNothing,
    );
  });

  testWidgets('direction toggle moves the output amount into the input', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _PricingSwapProvider(const [100]);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'swap_receive_amount_field'), '100.00');

    await tester.tap(
      find.byKey(const ValueKey('swap_direction_externalToZec')),
    );
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'swap_amount_field'), '100.00');
    expect(_fieldText(tester, 'swap_receive_amount_field'), '1.0000');
    expect(find.text('1 USDC = 0.0100 ZEC'), findsOneWidget);
  });

  testWidgets('draft conversion refreshes token prices automatically', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _PricingSwapProvider(const [100, 200]);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        seedSwapActivityFixtures: false,
        priceRefreshInterval: const Duration(seconds: 1),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'swap_receive_amount_field'), '100.00');
    expect(find.text('1 ZEC = 100.00 USDC'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(swapProvider.pricingRequests, greaterThanOrEqualTo(2));
    expect(swapProvider.sawForcedRefresh, isTrue);
    expect(_fieldText(tester, 'swap_receive_amount_field'), '200.00');
    expect(find.text('1 ZEC = 200.00 USDC'), findsOneWidget);
  });

  testWidgets('price refresh keeps the review page open and warns on drift', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _PricingSwapProvider(const [100, 200]);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        seedSwapActivityFixtures: false,
        priceRefreshInterval: const Duration(seconds: 1),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_review_panel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_review_amount_warning')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(swapProvider.sawForcedRefresh, isTrue);
    expect(find.byKey(const ValueKey('swap_review_panel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_review_amount_warning')),
      findsOneWidget,
    );
  });

  testWidgets('activity tab renders status, recent swaps, and receipt', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openActivitySurface(tester);

    expect(find.text('Swapping...'), findsWidgets);
    expect(
      find.byKey(const ValueKey('swap_active_summary_panel')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_activity_detail_page')),
      findsNothing,
    );
    expect(find.text('You pay'), findsNothing);
    expect(find.text('Privacy check'), findsNothing);

    await _openActivityDetail(tester, 'swap-8f29');

    expect(
      find.byKey(const ValueKey('swap_activity_detail_page')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('swap_status_title')), findsOneWidget);
    expect(find.text('Swapping ...'), findsOneWidget);
    expect(find.text('Swap Progress'), findsOneWidget);
    expect(find.text('Transaction details'), findsOneWidget);
    expect(find.text('Activity detail'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_status_summary_card')),
      findsOneWidget,
    );
    expect(find.text('Current swap'), findsNothing);
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_status_pay_summary_amount',
      numberText: '2.4000',
      symbolText: 'ZEC',
      cardKey: const ValueKey('swap_status_summary_card'),
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_status_receive_summary_amount',
      numberText: '168.42',
      symbolText: 'USDC',
      cardKey: const ValueKey('swap_status_summary_card'),
    );
    expect(
      find.byKey(const ValueKey('swap_activity_route_step_2_active')),
      findsOneWidget,
    );
    final activityDetailScrollbar = tester.widget<RawScrollbar>(
      find.byKey(const ValueKey('swap_activity_detail_scrollbar')),
    );
    expect(activityDetailScrollbar.thickness, 4);
    expect(activityDetailScrollbar.crossAxisMargin, AppSpacing.xxs);
    final activityDetailScrollGutter = tester.widget<Padding>(
      find.byKey(const ValueKey('swap_activity_detail_scroll_gutter')),
    );
    expect(
      activityDetailScrollGutter.padding,
      activityDetailScrollbar.thumbVisibility == true
          ? const EdgeInsets.only(right: AppSpacing.s)
          : EdgeInsets.zero,
    );
    expect(find.text('Swap...'), findsOneWidget);
    expect(find.text('Technical details'), findsNothing);
    expect(find.text('Status timeline'), findsNothing);
    expect(find.text('Receipt'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_activity_copy_receipt_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_status_refresh_button')),
      findsNothing,
    );
    expect(find.text('Copy redacted receipt'), findsNothing);

    await _closeActivityDetail(tester);

    expect(
      find.byKey(const ValueKey('swap_activity_detail_page')),
      findsNothing,
    );
  });

  testWidgets(
    'activity detail uses status page without manual refresh control',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _FakeSwapProvider();

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [_swapRoute(), _swapActivityRoute()],
          ),
          swapProvider: swapProvider,
        ),
      );
      await tester.pumpAndSettle();

      await _openActivitySurface(tester);

      expect(find.byType(ActivityScreen), findsOneWidget);
      expect(find.text('Privacy check'), findsNothing);

      await _openActivityDetail(tester, 'swap-8f29');

      expect(swapProvider.statusRequests, isEmpty);
      expect(
        find.byKey(const ValueKey('swap_status_refresh_button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('swap_activity_detail_page')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'activity detail moves broadcast ZEC deposits to confirmation step',
    (tester) async {
      await _setDesktopViewport(tester);
      final sessionStore = _FakeSwapPersistenceStore(
        initialIntents: [
          _persistedIntent(
            id: 'confirming-deposit',
            txHash: 'zec-auto-txid',
            status: SwapIntentStatus.awaitingDeposit,
            nextAction: 'Waiting for deposit confirmation',
          ),
        ],
      );
      final swapProvider = _FixedStatusSwapProvider(
        const SwapIntentSnapshot(
          id: 'confirming-deposit',
          providerLabel: 'NEAR Intents',
          pairText: 'ZEC -> USDC',
          sellAmountText: '1.5000 ZEC',
          receiveEstimateText: '105.25 USDC',
          status: SwapIntentStatus.awaitingDeposit,
          nextAction: 'Waiting for deposit confirmation',
          depositInstruction: SwapDepositInstruction(
            asset: SwapAsset.zec,
            address: 'confirming-deposit',
            expiresInLabel: '07:12',
            reuseWarning: 'Do not reuse this address',
            memo: 'memo-7',
          ),
        ),
      );

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [_swapRoute(), _swapActivityRoute()],
          ),
          seedSwapActivityFixtures: false,
          swapProvider: swapProvider,
          sessionStore: sessionStore,
        ),
      );
      await tester.pumpAndSettle();

      await _openActivitySurface(tester);
      expect(find.text('Swapping...'), findsOneWidget);
      expect(find.text('-1.5000 ZEC'), findsOneWidget);

      await _openActivityDetail(tester, 'confirming-deposit');

      expect(
        find.byKey(const ValueKey('swap_activity_route_step_0_complete')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('swap_activity_route_step_1_active')),
        findsOneWidget,
      );
      expect(find.text('Deposit confirmation...'), findsOneWidget);
      expect(find.text('Sending ZEC...'), findsNothing);
    },
  );

  testWidgets('activity route tracker stages skipped status transitions', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _DeferredStatusSwapProvider(
      const SwapIntentSnapshot(
        id: 'jump-deposit',
        providerLabel: 'NEAR Intents',
        pairText: 'ZEC -> USDC',
        sellAmountText: '1.0000 ZEC',
        receiveEstimateText: '70.170000 USDC',
        status: SwapIntentStatus.processing,
        nextAction: 'Swap is processing',
        depositInstruction: SwapDepositInstruction(
          asset: SwapAsset.zec,
          address: 'jump-deposit',
          expiresInLabel: '07:12',
          reuseWarning: 'Do not reuse this address',
          memo: 'memo-7',
        ),
      ),
    );
    final sessionStore = _FakeSwapPersistenceStore(
      initialIntents: [
        _persistedIntent(
          id: 'jump-deposit',
          txHash: '',
          status: SwapIntentStatus.awaitingDeposit,
          nextAction: 'Waiting for deposit',
        ),
      ],
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        swapProvider: swapProvider,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await _openActivitySurface(tester);
    await _openActivityDetail(tester, 'jump-deposit');

    expect(
      find.byKey(const ValueKey('swap_activity_route_step_0_active')),
      findsOneWidget,
    );

    await _sendShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyR,
    );
    expect(swapProvider.statusRequests, isNotEmpty);

    swapProvider.completeStatus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      find.byKey(const ValueKey('swap_activity_route_step_2_active')),
      findsOneWidget,
    );
  });

  testWidgets('activity detail does not expose manual removal controls', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final sessionStore = _FakeSwapPersistenceStore(
      initialIntents: [
        _persistedExternalToZecIntent(
          id: 'oversized-pending',
          stagingAddress: 't1oversized-staging',
        ),
        _persistedExternalToZecIntent(
          id: 'keep-pending',
          stagingAddress: 't1keep-staging',
        ),
      ],
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await _openActivitySurface(tester);

    expect(find.text('Swapping...'), findsNWidgets(2));

    await _openActivityDetail(tester, 'oversized-pending');

    expect(
      find.byKey(const ValueKey('swap_activity_remove_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_remove_intent_modal')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_activity_detail_page')),
      findsOneWidget,
    );
    expect(sessionStore.savedIntents.map((intent) => intent.id), [
      'oversized-pending',
      'keep-pending',
    ]);
  });

  testWidgets('activity detail hides support bundle and opens explorer link', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final clipboardWrites = <String>[];
    Future<Object?> handlePlatformCall(MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        clipboardWrites.add(args['text']! as String);
      }
      return null;
    }

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      handlePlatformCall,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openActivitySurface(tester);

    expect(
      find.byKey(const ValueKey('swap_receipt_scope_panel')),
      findsNothing,
    );

    await _openActivityDetail(tester, 'swap-refund');

    expect(
      find.byKey(const ValueKey('swap_support_details_section')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_support_details_toggle')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_support_bundle_panel')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_copy_support_details_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_receipt_scope_panel')),
      findsNothing,
    );
    await tester.ensureVisible(
      find.byKey(
        const ValueKey('swap_activity_copy_near_intents_explorer_button'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('swap_activity_copy_near_intents_explorer_button'),
      ),
    );
    await tester.pumpAndSettle();

    expect(clipboardWrites, isEmpty);
    expect(find.text('Explorer Link Copied'), findsNothing);
  });

  testWidgets('desktop shortcuts open swap activity and refresh status', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await _sendShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyR,
    );

    expect(swapProvider.statusRequests, hasLength(1));
    expect(find.byKey(const ValueKey('swap_queue_title')), findsNothing);

    await _sendShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.digit2,
    );

    expect(find.byType(ActivityScreen), findsOneWidget);
    expect(find.text('Swapping...'), findsWidgets);
    expect(find.text('Privacy check'), findsNothing);

    await _openSwapSurface(tester);
    expect(find.text('You pay'), findsOneWidget);
  });

  testWidgets('activity queue groups swaps and selection updates detail', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openActivitySurface(tester);

    expect(find.text('Swapping...'), findsWidgets);
    expect(find.text('Swapped'), findsWidgets);
    expect(find.text('ZEC deposit'), findsNothing);

    await _openActivityDetail(tester, 'swap-2a11');

    expect(find.text('Status timeline'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_activity_details_toggle')),
      findsNothing,
    );
    expect(find.text('Technical details'), findsNothing);
    expect(find.text('Swap completed'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);
    expect(find.byKey(const ValueKey('swap_final_details')), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('swap_activity_copy_near_intents_explorer_button'),
      ),
      findsOneWidget,
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_status_pay_summary_amount',
      numberText: '0.7500',
      symbolText: 'ZEC',
      cardKey: const ValueKey('swap_status_summary_card'),
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_status_receive_summary_amount',
      numberText: '37.8',
      symbolText: 'NEAR',
      cardKey: const ValueKey('swap_status_summary_card'),
    );
    expect(
      find.byKey(const ValueKey('swap_support_details_section')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_copy_support_details_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_copy_near_intents_explorer_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_deposit_tx_hash_field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_deposit_submit_button')),
      findsNothing,
    );
  });

  testWidgets('activity page scrolls when swap rows exceed the viewport', (
    tester,
  ) async {
    await _setViewport(tester, const Size(940, 560));
    final baseIntent = swapActivityFixtureIntents.firstWhere(
      (intent) => intent.id == 'swap-2a11',
    );
    final now = DateTime.utc(2026, 5, 27, 12);
    final overflowIntents = [
      for (var i = 0; i < 12; i++)
        baseIntent.copyWith(
          id: 'swap-scroll-$i',
          accountUuid: 'account-1',
          updatedAt: now.subtract(Duration(minutes: i)),
        ),
    ];

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/activity',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        sessionStore: _FakeSwapPersistenceStore(
          initialIntents: overflowIntents,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('activity_screen_scroll_view')),
    );
    final controller = scrollView.controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    final paneRect = tester.getRect(find.byType(AppDesktopPane));
    final pane = tester.widget<AppDesktopPane>(find.byType(AppDesktopPane));
    expect(pane.backgroundColor, isNull);
    final scrollbarRect = tester.getRect(
      find.byKey(const ValueKey('activity_screen_scrollbar')),
    );
    expect((scrollbarRect.right - paneRect.right).abs(), lessThan(1));
    final thumb = find.byKey(const ValueKey('activity_screen_scroll_thumb'));
    expect(thumb, findsOneWidget);
    final thumbDecoration =
        tester.widget<DecoratedBox>(thumb).decoration as BoxDecoration;
    expect(thumbDecoration.color, AppThemeData.light.colors.background.overlay);
    expect(find.byType(RawScrollbar), findsNothing);
    final beforeTop = tester.getTopLeft(thumb).dy;

    await tester.drag(
      find.byKey(const ValueKey('activity_screen_scroll_view')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
    expect(tester.getTopLeft(thumb).dy, greaterThan(beforeTop));
  });

  testWidgets('activity page renders all rows in the scroll feed', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final baseIntent = swapActivityFixtureIntents.firstWhere(
      (intent) => intent.id == 'swap-2a11',
    );
    final now = DateTime.utc(2026, 5, 27, 12);
    final intents = [
      for (var i = 0; i < 7; i++)
        baseIntent.copyWith(
          id: 'swap-page-$i',
          accountUuid: 'account-1',
          updatedAt: now.subtract(Duration(minutes: i)),
        ),
    ];

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/activity',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        sessionStore: _FakeSwapPersistenceStore(initialIntents: intents),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('activity_screen_row_5')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity_screen_row_6')), findsOneWidget);
    final filterLabel = tester.widget<Text>(
      find.byKey(const ValueKey('activity_screen_filter_label')),
    );
    expect(filterLabel.style?.color, AppThemeData.light.colors.text.disabled);
    final filterIcon = tester.widget<AppIcon>(
      find.byKey(const ValueKey('activity_screen_filter_icon')),
    );
    expect(filterIcon.name, AppIcons.filter);
    expect(filterIcon.color, AppThemeData.light.colors.icon.disabled);
  });

  testWidgets('activity progress detail fits without scrollbar chrome', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1080, 720));
    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/activity/swap/swap-8f29',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
      ),
    );
    await _pumpUntilPresent(
      tester,
      find.byKey(const ValueKey('swap_activity_detail_page')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Swapping ...'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_status_page_content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_near_intents_attribution')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_activity_detail_scrollbar')),
      findsOneWidget,
    );
    final explorerButton = find.byKey(
      const ValueKey('swap_activity_copy_near_intents_explorer_button'),
    );
    final progressButtonTop = tester.getRect(explorerButton).top;
    final statusRect = tester.getRect(
      find.byKey(const ValueKey('swap_status_page_content')),
    );
    final titleRect = tester.getRect(
      find.byKey(const ValueKey('swap_status_title')),
    );
    final buttonRect = tester.getRect(explorerButton);

    expect(statusRect.top, closeTo(76, 1));
    expect(titleRect.top - statusRect.top, closeTo(AppSpacing.s, 1));
    expect(buttonRect.top - statusRect.top, closeTo(524, 1));

    final scrollbar = tester.widget<RawScrollbar>(
      find.byKey(const ValueKey('swap_activity_detail_scrollbar')),
    );
    expect(scrollbar.thumbVisibility, isFalse);
    expect(scrollbar.interactive, isFalse);

    final gutter = tester.widget<Padding>(
      find.byKey(const ValueKey('swap_activity_detail_scroll_gutter')),
    );
    expect(gutter.padding.resolve(TextDirection.ltr).right, 0);

    final paneRect = tester.getRect(find.byType(AppDesktopPane));
    final attributionRect = tester.getRect(
      find.byKey(const ValueKey('swap_near_intents_attribution')),
    );
    expect(attributionRect.left, closeTo(paneRect.left + AppSpacing.md, 1));
    expect(paneRect.bottom - attributionRect.bottom, closeTo(AppSpacing.md, 1));

    await tester.tap(find.text('Transaction details'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_status_page_content')),
        matching: find.text('Account 1'),
      ),
      findsOneWidget,
    );
    expect(find.text('Current account'), findsNothing);
    expect(tester.getRect(explorerButton).top, closeTo(progressButtonTop, 1));

    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();

    expect(tester.getRect(explorerButton).top, closeTo(progressButtonTop, 1));
  });

  testWidgets('activity exposes incomplete, refunded, and failed scenarios', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final clipboardWrites = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<Object?, Object?>;
          clipboardWrites.add(args['text']! as String);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openActivitySurface(tester);

    expect(find.text('Action needed'), findsNothing);
    expect(find.text('Incomplete deposit'), findsWidgets);
    expect(find.text('Refunded'), findsWidgets);
    expect(find.text('Failed'), findsWidgets);

    await _openActivityDetail(tester, 'swap-underpaid');

    expect(
      find.byKey(const ValueKey('swap_status_page_content')),
      findsOneWidget,
    );
    expect(find.text('Incomplete deposit'), findsWidgets);
    expect(
      find.byKey(const ValueKey('swap_status_badge_warning')),
      findsOneWidget,
    );

    await _openSwapStatusDetails(tester, expand: true);

    expect(find.text('Incomplete'), findsWidgets);
    expect(find.text('Required deposit'), findsOneWidget);
    expect(find.text('Detected deposit'), findsOneWidget);
    expect(find.text('Missing deposit'), findsOneWidget);
    expect(find.text('Deposit USDC to'), findsOneWidget);
    expect(find.text('Memo'), findsOneWidget);
    expect(find.text('memo-underpaid'), findsOneWidget);
    expect(find.text('Refund fee'), findsOneWidget);
    expect(find.text('Guaranteed minimum'), findsNothing);
    expect(find.text('Resolve incomplete deposit'), findsNothing);
    expect(find.text('Copy top-up details'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_resolution_copy_deposit_button')),
      findsNothing,
    );

    await _openActivityDetail(tester, 'swap-refund');

    expect(find.byKey(const ValueKey('swap_final_details')), findsOneWidget);
    expect(find.text('Swap failed'), findsWidgets);
    expect(find.text('Funds refunded'), findsNothing);
    expect(find.text('Refund complete'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_resolution_review_again_button')),
      findsNothing,
    );
    await tester.ensureVisible(
      find.byKey(
        const ValueKey('swap_activity_copy_near_intents_explorer_button'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('swap_activity_copy_near_intents_explorer_button'),
      ),
    );
    await tester.pumpAndSettle();

    expect(clipboardWrites, isEmpty);
    expect(find.text('Explorer Link Copied'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_support_bundle_panel')),
      findsNothing,
    );

    await _openActivityDetail(tester, 'swap-failed');

    expect(find.byKey(const ValueKey('swap_final_details')), findsOneWidget);
    expect(find.text('Swap failed'), findsWidgets);
    expect(find.text('Start a fresh quote when ready.'), findsNothing);
    expect(find.text('Route failed'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_resolution_review_again_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_support_bundle_panel')),
      findsNothing,
    );
  });

  testWidgets('activity restores persisted swap sessions', (tester) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final sessionStore = _FakeSwapPersistenceStore(
      initialIntents: [
        _persistedIntent(
          id: 'persisted-deposit',
          txHash: 'persisted-txid',
          status: SwapIntentStatus.awaitingDeposit,
          nextAction: 'Waiting for a stored deposit',
        ),
      ],
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await _openActivitySurface(tester);

    expect(sessionStore.loadCount, greaterThanOrEqualTo(3));
    expect(swapProvider.statusRequests, hasLength(1));
    expect(
      swapProvider.statusRequests.single.depositAddress,
      'persisted-deposit',
    );
    expect(swapProvider.statusRequests.single.depositMemo, 'memo-7');
    expect(
      sessionStore.savedIntents.single.status,
      SwapIntentStatus.processing,
    );

    await _openActivityDetail(tester, 'persisted-deposit');

    await _openSwapStatusDetails(tester, expand: true);
    expect(find.text('persisted-deposit'), findsWidgets);
    expect(find.text('persisted-txid'), findsWidgets);
    expect(
      find.byKey(const ValueKey('swap_status_page_content')),
      findsOneWidget,
    );
  });

  testWidgets(
    'restored external-to-ZEC swap keeps wallet UA after status refresh',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _LongExternalStatusSwapProvider();
      final sessionStore = _FakeSwapPersistenceStore(
        initialIntents: [
          _persistedExternalToZecIntent(
            id: '0xpersisted-usdc-deposit',
            stagingAddress: 'u1persistedrecipient',
          ),
        ],
      );

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [_swapRoute(), _swapActivityRoute()],
          ),
          swapProvider: swapProvider,
          sessionStore: sessionStore,
        ),
      );
      await tester.pumpAndSettle();

      await _openActivitySurface(tester);

      expect(sessionStore.loadCount, greaterThanOrEqualTo(3));
      expect(swapProvider.statusRequests, hasLength(1));
      expect(
        swapProvider.statusRequests.single.depositAddress,
        '0xpersisted-usdc-deposit',
      );
      expect(
        sessionStore.savedIntents.single.oneClickRecipient,
        'u1persistedrecipient',
      );
      expect(
        sessionStore.savedIntents.single.oneClickRefundTo,
        '0xpersisted-refund',
      );

      await _openActivityDetail(tester, '0xpersisted-usdc-deposit');

      expect(find.text('u1persistedrecipient'), findsNothing);
      expect(
        find.byKey(const ValueKey('swap_deposit_tokens_panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('swap_activity_deposit_qr_panel')),
        findsOneWidget,
      );
      final detailRect = tester.getRect(
        find.byKey(const ValueKey('swap_activity_detail_page')),
      );
      final depositRect = tester.getRect(
        find.byKey(const ValueKey('swap_deposit_tokens_panel')),
      );
      expect(depositRect.center.dy, closeTo(detailRect.center.dy, 1));
    },
  );

  testWidgets(
    'external-to-ZEC provider success completes without wallet shielding',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _CompletingExternalStatusSwapProvider();
      final sessionStore = _FakeSwapPersistenceStore(
        initialIntents: [
          _persistedExternalToZecIntent(
            id: '0xcomplete',
            stagingAddress: 'u1shieldeddirectrecipient',
          ),
        ],
      );

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [_swapRoute(), _swapActivityRoute()],
          ),
          swapProvider: swapProvider,
          sessionStore: sessionStore,
        ),
      );
      await tester.pumpAndSettle();

      await _openActivitySurface(tester);

      expect(swapProvider.statusRequests, hasLength(1));
      expect(
        sessionStore.savedIntents.single.status,
        SwapIntentStatus.complete,
      );
      expect(
        sessionStore.savedIntents.single.nextAction,
        'Provider reports destination settlement complete',
      );
      expect(find.text('Swapped'), findsOneWidget);
      await _openActivityDetail(tester, '0xcomplete');

      expect(find.text('Swap completed'), findsOneWidget);
      expect(find.byKey(const ValueKey('swap_final_details')), findsOneWidget);
      expect(find.text('Make spendable'), findsNothing);
      expect(find.text('Technical details'), findsNothing);
    },
  );

  testWidgets('completed swap detail keeps final status details compact', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final sessionStore = _FakeSwapPersistenceStore(
      initialIntents: [
        _persistedIntent(
          id: 'completed-deposit',
          txHash: 'completed-deposit-txid',
          status: SwapIntentStatus.complete,
          nextAction: 'Complete',
        ).copyWith(
          depositAddress: 't1completed-deposit',
          destinationChainTxHash: 'usdc-delivery-txid',
          swapFeeText: '~0.25 USDC',
          totalFeesText: '0.0000134 ZEC',
          realisedSlippageText: '0.000758 USDC (0.07%)',
          completedAt: DateTime.utc(2026, 5, 20, 13, 20),
        ),
      ],
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await _openActivityDetail(tester, 'completed-deposit');

    expect(find.text('Swap completed'), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_final_details')), findsOneWidget);
    expect(find.text('USDC recipient'), findsOneWidget);
    expect(find.text('0x5290840 ... 4169ee7'), findsOneWidget);
    expect(find.text('ZEC deposit to'), findsOneWidget);
    expect(find.text('Total fees'), findsOneWidget);
    expect(find.text('0.0000134 ZEC'), findsOneWidget);
    expect(find.text('Realized slippage'), findsOneWidget);
    expect(find.text('0.000758 USDC (0.07%)'), findsOneWidget);
    expect(find.text('Timestamp'), findsOneWidget);
    expect(find.text('ZEC deposit tx'), findsNothing);
    expect(find.text('completed-deposit-txid'), findsNothing);
    expect(find.text('USDC delivery tx'), findsNothing);
    expect(find.text('usdc-delivery-txid'), findsNothing);
    expect(find.text('Slippage tolerance'), findsNothing);
    expect(find.text('Guaranteed minimum'), findsNothing);
  });

  testWidgets('failed swap detail keeps final status details compact', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final sessionStore = _FakeSwapPersistenceStore(
      initialIntents: [
        _persistedExternalToZecIntent(
          id: 'failed-usdc-deposit',
          stagingAddress: 'u1failed-recipient',
        ).copyWith(
          status: SwapIntentStatus.failed,
          nextAction: 'Failed',
          oneClickRefundTo: '0xusdc-refund-address',
          depositTxHash: 'failed-deposit-txid',
          destinationChainTxHash: 'failed-delivery-txid',
          swapFeeText: '~0.25 USDC',
          totalFeesText: '0.19 USDC',
          completedAt: DateTime.utc(2026, 5, 20, 13, 20),
        ),
      ],
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await _openActivityDetail(tester, 'failed-usdc-deposit');

    expect(find.text('Swap failed'), findsWidgets);
    expect(find.byKey(const ValueKey('swap_final_details')), findsOneWidget);
    expect(find.text('USDC refunded to'), findsOneWidget);
    expect(find.text('Total fees'), findsOneWidget);
    expect(find.text('0.19 USDC'), findsOneWidget);
    expect(find.text('Timestamp'), findsOneWidget);
    expect(find.text('USDC deposit to'), findsNothing);
    expect(find.text('USDC deposit tx'), findsNothing);
    expect(find.text('failed-deposit-txid'), findsNothing);
    expect(find.text('ZEC delivery tx'), findsNothing);
    expect(find.text('failed-delivery-txid'), findsNothing);
    expect(find.text('Realized slippage'), findsNothing);
    expect(find.text('Slippage tolerance'), findsNothing);
    expect(find.text('Guaranteed minimum'), findsNothing);
  });

  testWidgets('open swap sessions poll status after the configured interval', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final sessionStore = _FakeSwapPersistenceStore(
      initialIntents: [
        _persistedIntent(
          id: 'polling-deposit',
          txHash: 'polling-txid',
          status: SwapIntentStatus.awaitingDeposit,
          nextAction: 'Waiting for a stored deposit',
        ),
      ],
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        sessionStore: sessionStore,
        statusPollInterval: const Duration(milliseconds: 20),
      ),
    );
    await tester.pump();
    await tester.pump();

    final requestCountAfterRestore = swapProvider.statusRequests.length;
    expect(requestCountAfterRestore, greaterThanOrEqualTo(1));

    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();

    expect(
      swapProvider.statusRequests.length,
      greaterThan(requestCountAfterRestore),
    );
    expect(swapProvider.statusRequests.last.depositAddress, 'polling-deposit');
    expect(swapProvider.statusRequests.last.depositMemo, 'memo-7');
  });

  testWidgets('restored swap status uses the stored deposit address', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final sessionStore = _FakeSwapPersistenceStore(
      initialIntents: [
        _persistedIntent(
          id: 'swap-session-1',
          txHash: 'restored-txid',
          depositAddress: 't1restored-deposit',
          status: SwapIntentStatus.awaitingDeposit,
          nextAction: 'Waiting for a stored deposit',
        ),
      ],
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(swapProvider.statusRequests, hasLength(1));
    expect(
      swapProvider.statusRequests.single.depositAddress,
      't1restored-deposit',
    );
    expect(sessionStore.savedIntents.single.id, 'swap-session-1');
    expect(
      sessionStore.savedIntents.single.depositAddress,
      't1restored-deposit',
    );
  });

  testWidgets('delayed status refresh does not resurrect removed intent', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _DeferredStatusSwapProvider(
      _statusSnapshot(id: 'hardware-cancelled-swap'),
    );
    final sessionStore = _FakeSwapPersistenceStore(
      initialIntents: [
        _persistedIntent(
          id: 'hardware-cancelled-swap',
          txHash: '',
          status: SwapIntentStatus.awaitingDeposit,
          nextAction: 'Waiting for hardware deposit',
        ),
      ],
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        sessionStore: sessionStore,
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SwapScreen)),
      listen: false,
    );
    expect(
      container.read(swapStateProvider).intents.map((intent) => intent.id),
      ['hardware-cancelled-swap'],
    );
    expect(swapProvider.statusRequests, hasLength(1));

    await container
        .read(swapStateProvider.notifier)
        .removeIntent('hardware-cancelled-swap');
    await tester.pump();

    expect(container.read(swapStateProvider).intents, isEmpty);
    expect(sessionStore.savedIntents, isEmpty);

    swapProvider.completeStatus();
    await tester.pump();
    await tester.pump();

    expect(container.read(swapStateProvider).intents, isEmpty);
    expect(sessionStore.savedIntents, isEmpty);
  });

  testWidgets('deposit transaction submit uses the stored deposit address', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final sessionStore = _FakeSwapPersistenceStore(
      initialIntents: [
        _persistedIntent(
          id: 'swap-session-2',
          txHash: '',
          depositAddress: '0xstored-deposit',
          status: SwapIntentStatus.processing,
          nextAction: 'Waiting for deposit confirmation',
        ),
      ],
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await _openActivitySurface(tester);
    await _openActivityDetail(tester, 'swap-session-2');

    expect(
      find.byKey(const ValueKey('swap_support_details_section')),
      findsNothing,
    );

    await _openSwapStatusDetails(tester);

    expect(swapProvider.submittedDeposits, isEmpty);
    expect(find.text('0xstored-deposit'), findsOneWidget);
    expect(sessionStore.savedIntents.single.depositAddress, '0xstored-deposit');
  });

  testWidgets('swap screen does not overflow on compact desktop sizes', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1180, 720));

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('swap_compact_ticket')), findsOneWidget);
    expect(find.text('Privacy check'), findsNothing);
    expect(
      tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!
          .position
          .maxScrollExtent,
      0,
    );

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('swap_rate_line')), findsOneWidget);
    expect(
      tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!
          .position
          .maxScrollExtent,
      0,
    );

    await _openActivitySurface(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Technical details'), findsNothing);
    expect(find.text('Status timeline'), findsNothing);
  });

  testWidgets('activity layout holds long provider fields on narrow desktop', (
    tester,
  ) async {
    await _setViewport(tester, const Size(940, 720));

    final longIntent =
        _persistedIntent(
          id: 'swap-long-provider-data',
          txHash:
              '0xdeposit-transaction-hash-with-a-very-long-source-chain-suffix-9876543210',
          depositAddress:
              '0xone-time-usdc-deposit-address-with-a-long-provider-suffix-abcdef1234567890',
          status: SwapIntentStatus.awaitingExternalDeposit,
          nextAction:
              'Send the external deposit, then submit the source-chain transaction hash after confirmation.',
        ).copyWith(
          pair: 'USDC -> ZEC',
          sellAmount: '12345.678901 USDC',
          receiveEstimate: '175.9421 ZEC',
          direction: SwapDirection.externalToZec,
          externalAsset: SwapAsset.usdc,
          depositMemo:
              'memo-with-a-long-routing-tag-and-provider-reference-9876543210',
          oneClickRefundTo: '0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359',
        );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: _LongExternalStatusSwapProvider(),
        sessionStore: _FakeSwapPersistenceStore(initialIntents: [longIntent]),
      ),
    );
    await tester.pumpAndSettle();

    await _openActivitySurface(tester);
    await _openActivityDetail(tester, 'swap-long-provider-data');

    expect(tester.takeException(), isNull);
    expect(find.text('Deposit tokens'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_activity_deposit_qr_panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_deposit_tx_hash_disclosure')),
      findsNothing,
    );
  });

  testWidgets('review panel holds long quote values on narrow desktop', (
    tester,
  ) async {
    await _setViewport(tester, const Size(940, 720));

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: _LongQuoteSwapProvider(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('swap_direction_externalToZec')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '12345.678901',
    );
    await _enterDestinationText(
      tester,
      '0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359',
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('swap_review_button')),
    );
    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('swap_review_panel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_review_trade_summary')),
      findsOneWidget,
    );
    expect(find.text('Slippage tolerance'), findsOneWidget);
  });

  testWidgets('review panel formats tiny slippage and omits price protection', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_slippage_50bps')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_slippage_update_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '0.002',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_review_panel')), findsOneWidget);
    expect(find.text('Slippage tolerance'), findsOneWidget);
    expect(find.text('0.00001 ZEC (0.5%)'), findsOneWidget);
    expect(find.text('Price protection'), findsNothing);
    expect(
      _tooltipWithMessage(
        "Covers our fee and the route providers' costs to process this swap. "
        'Already included in the rate above.',
      ),
      findsOneWidget,
    );
    expect(
      _tooltipWithMessage(
        "The lowest amount of USDC you'll get after slippage. "
        'You may get more, never less.',
      ),
      findsOneWidget,
    );
    expect(swapProvider.requests.single.slippageBps, 50);
  });

  testWidgets('swap composer estimates, reviews, and starts an intent', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    expect(find.text('Minimum receive'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0xde709f2102306220921060314715629080e2fb77',
    );
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'swap_receive_amount_field'), '105.26');
    expect(find.text('1 ZEC = 70.17 USDC'), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_rate_line')), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_address_summary')), findsOneWidget);
    expect(find.text('Ethereum recipient'), findsNothing);
    expect(find.text('0xde709f...e2fb77'), findsWidgets);
    expect(find.text('Settlement path'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_review_panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_review_actions')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_start_button')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AppIcon && widget.name == AppIcons.arrowForwardIos,
        ),
      ),
      findsOneWidget,
    );
    final reviewPanelRect = tester.getRect(
      find.byKey(const ValueKey('swap_review_panel')),
    );
    final reviewActionsRect = tester.getRect(
      find.byKey(const ValueKey('swap_review_actions')),
    );
    expect(
      reviewActionsRect.top - reviewPanelRect.bottom,
      closeTo(AppSpacing.sm, 0.1),
    );
    final reviewScrollbar = tester.widget<RawScrollbar>(
      find.byKey(const ValueKey('swap_review_scrollbar')),
    );
    expect(reviewScrollbar.thickness, 4);
    expect(reviewScrollbar.crossAxisMargin, AppSpacing.xxs);
    final scrollGutter = tester.widget<Padding>(
      find.byKey(const ValueKey('swap_review_scroll_gutter')),
    );
    expect(scrollGutter.padding, const EdgeInsets.only(right: AppSpacing.s));
    final scrollAreaSize = tester.getSize(
      find.byKey(const ValueKey('swap_review_scrollbar')),
    );
    final panelSize = tester.getSize(
      find.byKey(const ValueKey('swap_review_panel')),
    );
    expect(scrollAreaSize.width, greaterThan(panelSize.width));
    expect(scrollAreaSize.height, greaterThan(800));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('swap_review_title')))
          .style!
          .fontSize,
      greaterThanOrEqualTo(26),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('swap_start_button'))).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('swap_review_cancel_button')))
          .height,
      greaterThanOrEqualTo(44),
    );
    final startButtonWidth = tester
        .getSize(find.byKey(const ValueKey('swap_start_button')))
        .width;
    final cancelButtonWidth = tester
        .getSize(find.byKey(const ValueKey('swap_review_cancel_button')))
        .width;
    expect(startButtonWidth, greaterThanOrEqualTo(148));
    expect(cancelButtonWidth, greaterThanOrEqualTo(148));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_compact_ticket')),
        matching: find.byKey(const ValueKey('swap_review_panel')),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_review_deposit_qr_panel')),
      findsNothing,
    );
    expect(find.text('Review swap'), findsOneWidget);
    final reviewSummary = find.byKey(
      const ValueKey('swap_review_trade_summary'),
    );
    expect(
      find.descendant(
        of: reviewSummary,
        matching: find.byKey(const ValueKey('swap_asset_chain_badge_zec')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: reviewSummary,
        matching: find.byKey(const ValueKey('swap_asset_chain_badge_usdc')),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_review_consent_panel')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_review_details_toggle')),
      findsNothing,
    );
    _expectSummaryAmountPartsFitCard(
      tester,
      keyPrefix: 'swap_review_pay_summary_amount',
      numberText: '1.5000',
      symbolText: 'ZEC',
      cardKey: const ValueKey('swap_review_trade_summary'),
    );
    expect(find.text('Slippage tolerance'), findsOneWidget);
    expect(find.text('Guaranteed minimum'), findsOneWidget);
    expect(find.text('Swap fee'), findsOneWidget);
    expect(find.text('Third-party data'), findsNothing);
    expect(find.text('Network disclosure'), findsNothing);
    expect(find.text('Confirm swap'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('swap_activity_detail_page')),
      findsOneWidget,
    );
    expect(find.text('Technical details'), findsNothing);
    await _closeActivityDetail(tester);
    await _openSwapSurface(tester);
    expect(_fieldText(tester, 'swap_amount_field'), isEmpty);
    expect(_destinationSummaryText(tester), isEmpty);
  });

  testWidgets(
    'review quote uses live request semantics and renders provider deposit details',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _FakeSwapProvider();

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [_swapRoute(), _swapActivityRoute()],
          ),
          swapProvider: swapProvider,
          seedSwapActivityFixtures: false,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '1.5',
      );
      await _enterDestinationText(
        tester,
        '0x52908400098527886e0f7030069857d2e4169ee7',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();

      expect(swapProvider.requests, hasLength(1));
      final request = swapProvider.requests.single;
      expect(request.dryRun, isFalse);
      expect(request.direction, SwapDirection.zecToExternal);
      expect(request.externalAsset, SwapAsset.usdc);
      expect(request.sellAmount, 1.5);
      expect(request.sellAmountText, '1.5');
      expect(request.destination, '0x52908400098527886e0f7030069857d2e4169ee7');
      expect(request.refundAddress, 'u1actualshieldedrecipient');

      expect(find.byKey(const ValueKey('swap_review_panel')), findsOneWidget);
      expect(find.text('Review swap'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('swap_review_details')),
          matching: find.text('To'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('swap_review_details')),
          matching: find.text('From'),
        ),
        findsOneWidget,
      );
      expect(find.text('Guaranteed minimum'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('swap_review_details_toggle')),
        findsNothing,
      );
      expect(find.text('Expires in'), findsNothing);

      final reviewDetails = find.byKey(const ValueKey('swap_review_details'));
      final reviewDetailsRect = tester.getRect(reviewDetails);
      final recipientValueRect = tester.getRect(
        find.descendant(
          of: reviewDetails,
          matching: find.text('0x5290840 ... 4169ee7'),
        ),
      );
      final feeValueRect = tester.getRect(
        find.descendant(
          of: reviewDetails,
          matching: find.text('Included in shown rate'),
        ),
      );
      final feeHelpIconRect = tester.getRect(
        find
            .descendant(
              of: reviewDetails,
              matching: find.byWidgetPredicate(
                (widget) => widget is AppIcon && widget.name == AppIcons.help,
              ),
            )
            .last,
      );
      expect(
        recipientValueRect.right,
        closeTo(reviewDetailsRect.right - AppSpacing.sm, 1),
      );
      expect(feeValueRect.right, lessThan(feeHelpIconRect.left));
      expect(
        feeHelpIconRect.right,
        closeTo(reviewDetailsRect.right - AppSpacing.sm, 1),
      );
    },
  );

  testWidgets('fiat pay input converts to a token exact-input quote', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _PricingSwapProvider(const [70]);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_fiat_value_mode_icon')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '105',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'swap_amount_field'), '105');
    expect(_fieldText(tester, 'swap_receive_amount_field'), '105');
    expect(find.text('1.5000 ZEC'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.requests, hasLength(1));
    final liveRequest = swapProvider.requests.single;
    expect(liveRequest.dryRun, isFalse);
    expect(liveRequest.mode, SwapQuoteMode.exactInput);
    expect(liveRequest.amount, 1.5);
    expect(liveRequest.amountText, '1.5000');
    expect(liveRequest.amountAsset, SwapAsset.zec);
    expect(
      liveRequest.destination,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
  });

  testWidgets('token amount fields cap fractional digits by asset decimals', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.12345678',
    );
    await tester.pump();
    expect(_fieldText(tester, 'swap_amount_field'), '1.12345678');

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.123456789',
    );
    await tester.pump();
    expect(_fieldText(tester, 'swap_amount_field'), '1.12345678');

    await tester.enterText(
      find.byKey(const ValueKey('swap_receive_amount_field')),
      '105.123456',
    );
    await tester.pump();
    expect(_fieldText(tester, 'swap_receive_amount_field'), '105.123456');

    await tester.enterText(
      find.byKey(const ValueKey('swap_receive_amount_field')),
      '105.1234567',
    );
    await tester.pump();
    expect(_fieldText(tester, 'swap_receive_amount_field'), '105.123456');
  });

  testWidgets('fiat receive input estimates exact-output locally', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _PricingSwapProvider(const [70.1733333333]);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_receive_amount_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_fiat_value_mode_icon')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('swap_receive_amount_field')),
      '105.26',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'swap_receive_amount_field'), '105.26');
    expect(_fieldText(tester, 'swap_amount_field'), '105');
    expect(find.text('1.5000 ZEC'), findsOneWidget);
    expect(swapProvider.requests, isEmpty);
  });

  testWidgets(
    'editing receive amount estimates locally and reviews exact-output quote',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _FakeSwapProvider();

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [_swapRoute(), _swapActivityRoute()],
          ),
          swapProvider: swapProvider,
          seedSwapActivityFixtures: false,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('swap_receive_amount_field')),
        '105.27',
      );
      await _enterDestinationText(
        tester,
        '0x52908400098527886e0f7030069857d2e4169ee7',
      );
      await tester.pumpAndSettle();

      expect(_fieldText(tester, 'swap_receive_amount_field'), '105.27');
      expect(_fieldText(tester, 'swap_amount_field'), '1.5002');
      expect(swapProvider.requests, isEmpty);

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();

      expect(swapProvider.requests, hasLength(1));
      final liveRequest = swapProvider.requests.single;
      expect(liveRequest.dryRun, isFalse);
      expect(liveRequest.mode, SwapQuoteMode.exactOutput);
      expect(liveRequest.amount, 105.27);
      expect(liveRequest.amountText, '105.27');
      expect(
        liveRequest.destination,
        '0x52908400098527886e0f7030069857d2e4169ee7',
      );
      expect(liveRequest.refundAddress, 'u1actualshieldedrecipient');
      expect(find.text('Review swap'), findsOneWidget);
      expect(find.text('Slippage tolerance'), findsOneWidget);
      expect(find.text('Guaranteed minimum'), findsOneWidget);
    },
  );

  testWidgets(
    'exact-output review blocks start when live required pay exceeds balance',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _DriftingExactOutputSwapProvider();

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [_swapRoute(), _swapActivityRoute()],
          ),
          swapProvider: swapProvider,
          spendableBalance: BigInt.from(155000000),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('swap_receive_amount_field')),
        '105.26',
      );
      await _enterDestinationText(
        tester,
        '0x52908400098527886e0f7030069857d2e4169ee7',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();

      final reviewSummary = find.byKey(
        const ValueKey('swap_review_trade_summary'),
      );
      _expectSummaryAmountPartsFitCard(
        tester,
        keyPrefix: 'swap_review_pay_summary_amount',
        numberText: '1.6000',
        symbolText: 'ZEC',
        cardKey: const ValueKey('swap_review_trade_summary'),
      );
      expect(
        find.descendant(of: reviewSummary, matching: find.text(r'$105.26')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: reviewSummary, matching: find.text(r'$112.28')),
        findsOneWidget,
      );
      expect(
        find.text(
          "You don't have enough ZEC for this swap. Try a smaller amount.",
        ),
        findsOneWidget,
      );
      expect(find.text('Not enough ZEC'), findsOneWidget);
      expect(swapProvider.startedQuotes, isEmpty);
    },
  );

  testWidgets('review summary fiat values use the live exact-input quote', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _DriftingExactInputSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        seedSwapActivityFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    final reviewSummary = find.byKey(
      const ValueKey('swap_review_trade_summary'),
    );
    expect(
      find.descendant(of: reviewSummary, matching: find.text('123.45')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: reviewSummary, matching: find.text('USDC')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: reviewSummary, matching: find.text(r'$123.45')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: reviewSummary, matching: find.text(r'$105.26')),
      findsOneWidget,
    );
  });

  testWidgets('review quote can be cancelled without clearing the draft', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(find.text('Review swap'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('swap_review_cancel_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_review_cancel_button')));
    await tester.pumpAndSettle();

    expect(find.text('Review swap'), findsNothing);
    expect(_fieldText(tester, 'swap_amount_field'), '1.5');
    expect(_destinationSummaryText(tester), '0x529084...169ee7');
  });

  testWidgets('quote loading separates draft estimate from live review', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _DelayedQuoteSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_rate_line')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pump();

    expect(find.text('Getting live quote'), findsNothing);
    expect(find.text('Getting quote'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_rate_line')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.loader,
        ),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_review_button')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.loader,
        ),
      ),
      findsOneWidget,
    );
    final gettingQuoteRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_review_button')),
        matching: find.text('Getting quote'),
      ),
    );
    final buttonLoaderRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_review_button')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.loader,
        ),
      ),
    );
    expect(buttonLoaderRect.left - gettingQuoteRect.right, closeTo(4, 1));

    swapProvider.completeQuote();
    await tester.pumpAndSettle();

    expect(find.text('Getting live quote'), findsNothing);
    expect(find.byKey(const ValueKey('swap_review_panel')), findsOneWidget);
  });

  testWidgets('expired review quote blocks start until reviewed again', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    expect(swapProvider.requests, hasLength(1));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SwapReviewScreen)),
    );
    container.read(swapStateProvider.notifier).expireReviewQuote();
    await tester.pumpAndSettle();

    expect(
      find.text('Quote expired. Review again for an updated rate.'),
      findsOneWidget,
    );
    expect(find.text('Review again required'), findsNothing);

    expect(find.byKey(const ValueKey('swap_start_button')), findsNothing);
    expect(swapProvider.startedQuotes, isEmpty);

    await tester.tap(find.byKey(const ValueKey('swap_review_again_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.requests, hasLength(2));
    expect(
      find.text('Quote expired. Review again for an updated rate.'),
      findsNothing,
    );
    expect(find.text('Confirm swap'), findsOneWidget);
  });

  testWidgets('startIntent blocks a quote whose deadline has already passed', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider(
      quoteExpiresAt: DateTime.utc(2020, 1, 1),
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    expect(swapProvider.requests, hasLength(1));

    final notifier = ProviderScope.containerOf(
      tester.element(find.byType(SwapReviewScreen)),
    ).read(swapStateProvider.notifier);

    final started = await notifier.startIntent();
    await tester.pumpAndSettle();

    expect(started, isFalse);
    expect(swapProvider.startedQuotes, isEmpty);
    expect(
      find.text('Quote expired. Review again for an updated rate.'),
      findsOneWidget,
    );
    expect(find.byType(SwapActivityDetailScreen), findsNothing);
  });

  testWidgets('startIntent blocks a quote inside the expiry safety buffer', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    // Within the 5s pre-deadline buffer in SwapNotifier.startIntent.
    final swapProvider = _FakeSwapProvider(
      quoteExpiresAt: DateTime.now().toUtc().add(const Duration(seconds: 2)),
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    final notifier = ProviderScope.containerOf(
      tester.element(find.byType(SwapReviewScreen)),
    ).read(swapStateProvider.notifier);

    final started = await notifier.startIntent();
    await tester.pumpAndSettle();

    expect(started, isFalse);
    expect(swapProvider.startedQuotes, isEmpty);
  });

  testWidgets('startIntent allows a quote whose deadline is in the future', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider(
      quoteExpiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    final notifier = ProviderScope.containerOf(
      tester.element(find.byType(SwapReviewScreen)),
    ).read(swapStateProvider.notifier);

    final started = await notifier.startIntent();
    await tester.pumpAndSettle();

    expect(started, isTrue);
    expect(swapProvider.startedQuotes, hasLength(1));
  });

  testWidgets('quote failure shows an inline error and preserves the draft', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: _FailingQuoteSwapProvider(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(find.text('Review swap'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_quote_error_message')),
      findsOneWidget,
    );
    expect(find.text('Quote unavailable'), findsNothing);
    expect(
      find.textContaining('Quote is unavailable right now.'),
      findsOneWidget,
    );
    expect(_fieldText(tester, 'swap_amount_field'), '1.5');
    expect(_destinationSummaryText(tester), '0x529084...169ee7');
  });

  testWidgets('start failure stays on review and shows an inline error', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FailingStartSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.startedQuotes, hasLength(1));
    expect(find.byKey(const ValueKey('swap_review_panel')), findsOneWidget);
    expect(find.textContaining('Swap could not be started.'), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_queue_title')), findsNothing);
  });

  testWidgets('swap composer supports receiving ZEC from an external asset', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('swap_direction_externalToZec')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '140.35',
    );
    await _enterDestinationText(
      tester,
      '0x8617e340b3d01fa5f11f306f4090fd50e238070d',
    );
    await tester.pumpAndSettle();

    expect(find.text('Ethereum refund'), findsNothing);
    expect(find.byKey(const ValueKey('swap_address_summary')), findsOneWidget);
    expect(find.text('0x8617e3...38070d'), findsWidgets);
    expect(find.text('ZEC delivery'), findsNothing);
    expect(find.text('u1wallet-refund-placeholder'), findsNothing);
    expect(find.text('USDC source deposit'), findsNothing);
    expect(find.text('ZEC staging'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_settlement_shielding_note')),
      findsNothing,
    );
    expect(_fieldText(tester, 'swap_receive_amount_field'), '2.0000');
    expect(find.text('1 USDC = 0.0143 ZEC'), findsOneWidget);
    expect(find.text('USDC -> ZEC'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(find.text('Review swap'), findsOneWidget);
    expect(find.text('Slippage tolerance'), findsOneWidget);
    expect(find.text('Swap fee'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_review_deposit_qr_panel')),
      findsNothing,
    );
    expect(find.text('ZEC delivery'), findsNothing);
    expect(find.text('Approval locks deposit instructions'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_review_details_toggle')),
      findsNothing,
    );

    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    expect(find.text('Deposit tokens'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_activity_deposit_qr_panel')),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Back to Swap'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_compact_ticket')), findsOneWidget);
    expect(find.text('Review swap'), findsNothing);
    expect(_fieldText(tester, 'swap_amount_field'), isEmpty);
    expect(_destinationSummaryText(tester), isEmpty);
  });

  testWidgets('review quote blocks when wallet UA cannot be loaded', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1180, 720));
    final swapProvider = _FakeSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        loadShieldedAddress: ({required accountUuid}) async {
          throw Exception('shielded address unavailable');
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.requests, isEmpty);
    expect(find.text('Review swap'), findsNothing);
    expect(
      find.textContaining('Could not prepare a fresh wallet receive address.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('review quote uses shielded unified address as ZEC recipient', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('swap_direction_externalToZec')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '140.35',
    );
    await _enterDestinationText(
      tester,
      '0x8617e340b3d01fa5f11f306f4090fd50e238070d',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.requests, hasLength(1));
    expect(swapProvider.requests.single.direction, SwapDirection.externalToZec);
    expect(
      swapProvider.requests.single.destination,
      'u1actualshieldedrecipient',
    );
    expect(
      swapProvider.requests.single.refundAddress,
      '0x8617e340b3d01fa5f11f306f4090fd50e238070d',
    );
    expect(find.text('Review swap'), findsOneWidget);
    expect(
      find.textContaining('ZEC arrives at your shielded address'),
      findsNothing,
    );
  });

  testWidgets('hardware review quote rotates shielded ZEC recipient', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        bootstrap: _hardwareBootstrap,
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('swap_direction_externalToZec')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '140.35',
    );
    await _enterDestinationText(
      tester,
      '0x8617e340b3d01fa5f11f306f4090fd50e238070d',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.requests, hasLength(1));
    expect(swapProvider.requests.single.direction, SwapDirection.externalToZec);
    expect(
      swapProvider.requests.single.destination,
      'u1actualshieldedrecipient',
    );
    expect(
      swapProvider.requests.single.destination,
      isNot(_hardwareBootstrap.initialAccountState.activeAddress),
    );
    expect(
      swapProvider.requests.single.refundAddress,
      '0x8617e340b3d01fa5f11f306f4090fd50e238070d',
    );
  });

  testWidgets('started swap can refresh status from provider', (tester) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.startedQuotes, hasLength(1));
    await _openSwapStatusDetails(tester);
    expect(find.text('t1live-deposit'), findsWidgets);
    expect(find.text('Technical details'), findsNothing);

    expect(swapProvider.statusRequests, isNotEmpty);
    expect(swapProvider.statusRequests.last.depositAddress, 't1live-deposit');
    expect(swapProvider.statusRequests.last.depositMemo, 'memo-live');
    expect(
      find.byKey(const ValueKey('swap_support_bundle_panel')),
      findsNothing,
    );
  });

  testWidgets('started swap routes to status page when deposit is claimed', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('swap_direction_externalToZec')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '140.35',
    );
    await _enterDestinationText(
      tester,
      '0x8617e340b3d01fa5f11f306f4090fd50e238070d',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    expect(find.text('Deposit tokens'), findsOneWidget);
    expect(find.text('0xlive-deposit'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_deposit_check_warning')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('swap_deposit_confirm_button')));
    await tester.pumpAndSettle();

    // Tapping "I've deposited" immediately routes to the status page;
    // no provider status request is triggered by this tap.
    expect(swapProvider.submittedDeposits, isEmpty);
    expect(
      find.byKey(const ValueKey('swap_deposit_confirm_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_status_page_content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_deposit_check_warning')),
      findsNothing,
    );
  });

  testWidgets(
    'external deposit claim immediately routes to status page without warning',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _PendingExternalDepositSwapProvider();

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [_swapRoute(), _swapActivityRoute()],
          ),
          swapProvider: swapProvider,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('swap_direction_externalToZec')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '140.35',
      );
      await _enterDestinationText(
        tester,
        '0x8617e340b3d01fa5f11f306f4090fd50e238070d',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('swap_start_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('swap_start_button')));
      await tester.pumpAndSettle();

      // Deposit page is shown before pressing.
      expect(find.text('Deposit tokens'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('swap_deposit_confirm_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('swap_deposit_check_warning')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('swap_deposit_confirm_button')),
      );
      await tester.pumpAndSettle();

      // After tapping, deposit page is gone and status page is shown.
      expect(
        find.byKey(const ValueKey('swap_deposit_confirm_button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('swap_status_page_content')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('swap_deposit_check_warning')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'activity shows direction-specific external deposit instructions',
    (tester) async {
      await _setDesktopViewport(tester);
      final sessionStore = _FakeSwapPersistenceStore();
      final clipboardWrites = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<Object?, Object?>;
            clipboardWrites.add(args['text']! as String);
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [_swapRoute(), _swapActivityRoute()],
          ),
          sessionStore: sessionStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('swap_direction_externalToZec')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '140.35',
      );
      await _enterDestinationText(
        tester,
        '0x8617e340b3d01fa5f11f306f4090fd50e238070d',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirm swap'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm swap'));
      await tester.pumpAndSettle();

      expect(find.text('Deposit tokens'), findsOneWidget);
      expect(find.text('0xlive-deposit'), findsOneWidget);
      expect(find.text('Make spendable'), findsNothing);
      expect(
        find.byKey(const ValueKey('swap_activity_deposit_qr_panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('swap_near_intents_attribution')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('swap_copy_deposit_address')),
        findsOneWidget,
      );
      expect(find.text('Memo'), findsOneWidget);
      expect(find.text('memo-live'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('swap_copy_deposit_memo')),
        findsOneWidget,
      );
      final copyDepositAddress = find.byKey(
        const ValueKey('swap_copy_deposit_address'),
      );
      final copyCursor = tester.widget<MouseRegion>(
        find
            .ancestor(
              of: copyDepositAddress,
              matching: find.byType(MouseRegion),
            )
            .first,
      );
      expect(copyCursor.cursor, SystemMouseCursors.click);
      final copyIcon = tester.widget<AppIcon>(
        find.descendant(
          of: copyDepositAddress,
          matching: find.byWidgetPredicate(
            (widget) => widget is AppIcon && widget.name == AppIcons.copy,
          ),
        ),
      );
      expect(copyIcon.size, AppIconSize.medium);
      expect(
        tester.getSize(find.byKey(const ValueKey('swap_deposit_qr_logo'))),
        const Size(34, 34),
      );
      final qrLogo = find.byKey(const ValueKey('swap_deposit_qr_logo'));
      final qrNetworkTooltip = tester.widget<Tooltip>(
        find.ancestor(of: qrLogo, matching: find.byType(Tooltip)).first,
      );
      expect(qrNetworkTooltip.message, SwapAsset.usdc.chainLabel);
      final qrNetworkImage = tester.widget<Image>(
        find.descendant(of: qrLogo, matching: find.byType(Image)),
      );
      expect(
        (qrNetworkImage.image as AssetImage).assetName,
        SwapAsset.usdc.chainIconAsset,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('swap_deposit_tokens_qr_code')),
          matching: find.byType(SwapAssetIcon),
        ),
        findsNothing,
      );
      await tester.ensureVisible(copyDepositAddress);
      await tester.pumpAndSettle();
      await tester.tap(copyDepositAddress);
      await tester.pumpAndSettle();
      expect(clipboardWrites.last, '0xlive-deposit');
      expect(find.text('Address copied'), findsOneWidget);
      final copyDepositMemo = find.byKey(
        const ValueKey('swap_copy_deposit_memo'),
      );
      await tester.ensureVisible(copyDepositMemo);
      await tester.pumpAndSettle();
      await tester.tap(copyDepositMemo);
      await tester.pumpAndSettle();
      expect(clipboardWrites.last, 'memo-live');
      expect(find.text('Memo copied'), findsOneWidget);
      expect(find.text('Receive address'), findsNothing);
      expect(
        find.byKey(const ValueKey('swap_copy_receive_address')),
        findsNothing,
      );
      expect(find.text('u1actualshieldedrecipient'), findsNothing);
      expect(
        find.byKey(const ValueKey('swap_open_receive_staging_button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('swap_deposit_tx_hash_disclosure')),
        findsNothing,
      );
      expect(find.text('Add tx hash'), findsNothing);
      expect(
        find.textContaining(
          'Add the deposit transaction hash to speed up status checks.',
        ),
        findsNothing,
      );
      expect(find.text('Live submit disabled'), findsNothing);
      expect(sessionStore.savedIntents, hasLength(1));
      expect(sessionStore.savedIntents.single.id, '0xlive-deposit');
      expect(sessionStore.savedIntents.single.depositAddress, '0xlive-deposit');
      expect(sessionStore.savedIntents.single.depositMemo, 'memo-live');
      expect(sessionStore.savedIntents.single.providerQuoteId, 'quote-live');
      expect(
        sessionStore.savedIntents.single.oneClickRecipient,
        'u1actualshieldedrecipient',
      );
      expect(
        sessionStore.savedIntents.single.oneClickRefundTo,
        '0x8617e340b3d01fa5f11f306f4090fd50e238070d',
      );
    },
  );

  testWidgets('starting a ZEC swap sends and submits the deposit tx', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final depositSender = _FakeSwapDepositSender();
    final sessionStore = _FakeSwapPersistenceStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        depositSender: depositSender,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    expect(depositSender.requests, hasLength(1));
    expect(depositSender.requests.single.accountUuid, 'account-1');
    expect(depositSender.requests.single.depositAddress, 't1live-deposit');
    expect(depositSender.requests.single.sellAmountText, '1.5000 ZEC');
    expect(
      depositSender.requests.single.sellAmountBaseUnits,
      BigInt.from(150000000),
    );
    expect(swapProvider.submittedDeposits, hasLength(1));
    expect(swapProvider.submittedDeposits.single.txHash, 'zec-auto-txid');
    expect(
      swapProvider.submittedDeposits.single.depositAddress,
      't1live-deposit',
    );
    expect(swapProvider.submittedDeposits.single.depositMemo, 'memo-live');
    expect(sessionStore.savedIntents, hasLength(1));
    expect(sessionStore.savedIntents.single.id, 't1live-deposit');
    expect(sessionStore.savedIntents.single.depositAddress, 't1live-deposit');
    expect(sessionStore.savedIntents.single.accountUuid, 'account-1');
    expect(sessionStore.savedIntents.single.depositMemo, 'memo-live');
    expect(sessionStore.savedIntents.single.depositTxHash, 'zec-auto-txid');
    expect(sessionStore.savedIntents.single.providerQuoteId, 'quote-live');
    expect(
      sessionStore.savedIntents.single.direction,
      SwapDirection.zecToExternal,
    );
    expect(
      sessionStore.savedIntents.single.oneClickRecipient,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    expect(
      sessionStore.savedIntents.single.oneClickRefundTo,
      'u1actualshieldedrecipient',
    );
    await _openSwapStatusDetails(tester, expand: true);
    expect(find.text('USDC recipient'), findsOneWidget);
    expect(find.text('0x5290840 ... 4169ee7'), findsOneWidget);
    expect(find.text('t1live-deposit'), findsWidgets);
    expect(find.text('ZEC deposit tx hash'), findsNothing);
    expect(find.text('Submit ZEC deposit'), findsNothing);
    expect(find.text('zec-auto-txid'), findsWidgets);
  });

  testWidgets(
    'pending ZEC deposit broadcast is checkpointed without provider submit',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _FakeSwapProvider();
      final depositSender = _FakeSwapDepositSender(
        broadcastStatus: SwapDepositBroadcastStatus.pendingBroadcast,
        broadcastMessage: 'Broadcast could not start after local creation',
      );
      final sessionStore = _FakeSwapPersistenceStore();

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [_swapRoute(), _swapActivityRoute()],
          ),
          swapProvider: swapProvider,
          depositSender: depositSender,
          sessionStore: sessionStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '1.5',
      );
      await _enterDestinationText(
        tester,
        '0x52908400098527886e0f7030069857d2e4169ee7',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('swap_start_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('swap_start_button')));
      await tester.pumpAndSettle();

      expect(depositSender.requests, hasLength(1));
      expect(swapProvider.submittedDeposits, isEmpty);
      expect(sessionStore.savedIntents, hasLength(1));
      expect(sessionStore.savedIntents.single.depositTxHash, 'zec-auto-txid');
      expect(
        sessionStore.savedIntents.single.broadcastNotice,
        'Broadcast could not start after local creation',
      );
      await _openSwapStatusDetails(tester, expand: true);
      expect(find.text('zec-auto-txid'), findsWidgets);
      expect(
        find.text('Broadcast could not start after local creation'),
        findsWidgets,
      );
    },
  );

  testWidgets('pending ZEC deposit broadcast switches to a fallback endpoint', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final depositSender = _FakeSwapDepositSender(
      broadcastStatus: SwapDepositBroadcastStatus.pendingBroadcast,
      broadcastMessage: 'gRPC connect failed: connection refused',
    );
    final sessionStore = _FakeSwapPersistenceStore();
    final primary = defaultRpcEndpointConfig('main');
    final fallback = fallbackRpcEndpointCandidatesFor(primary).first;

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        depositSender: depositSender,
        sessionStore: sessionStore,
        failoverChainNameGetter: (url) async => 'main',
        failoverHeightGetter: (url) async =>
            url == fallback.normalizedLightwalletdUrl
            ? BigInt.from(100)
            : BigInt.from(100),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SwapScreen)),
    );

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    final failoverState = container.read(rpcEndpointFailoverProvider);
    expect(depositSender.requests, hasLength(1));
    expect(failoverState.isUsingFallback, isTrue);
    expect(
      failoverState.current.normalizedLightwalletdUrl,
      fallback.normalizedLightwalletdUrl,
    );
    final syncNotifier =
        container.read(syncProvider.notifier) as _FakeSwapSyncNotifier;
    expect(syncNotifier.restartCount, 1);
  });

  testWidgets('ZEC swap opens activity before deposit broadcast finishes', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _AwaitingSubmitSwapProvider();
    final depositSender = _DelayedSwapDepositSender();
    final sessionStore = _FakeSwapPersistenceStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        depositSender: depositSender,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('swap_review_panel')), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_activity_detail_page')),
      findsOneWidget,
    );
    expect(depositSender.requests, hasLength(1));
    expect(swapProvider.submittedDeposits, isEmpty);
    expect(sessionStore.savedIntents, hasLength(1));
    expect(sessionStore.savedIntents.single.depositTxHash, isNull);

    depositSender.completeSend();
    await tester.pumpAndSettle();

    expect(swapProvider.submittedDeposits, hasLength(1));
    expect(sessionStore.savedIntents.last.depositTxHash, 'zec-auto-txid');
    await _openSwapStatusDetails(tester, expand: true);
    expect(find.text('zec-auto-txid'), findsWidgets);
  });

  testWidgets('ZEC deposit tx hash is checkpointed when submit fails', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider(
      submitDepositError: Exception('submit temporarily unavailable'),
    );
    final depositSender = _FakeSwapDepositSender();
    final sessionStore = _FakeSwapPersistenceStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        depositSender: depositSender,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    expect(depositSender.requests, hasLength(1));
    expect(swapProvider.submittedDeposits, hasLength(1));
    expect(sessionStore.savedIntents, hasLength(1));
    expect(sessionStore.savedIntents.single.depositTxHash, 'zec-auto-txid');
    expect(sessionStore.savedIntents.single.accountUuid, 'account-1');
    await _openSwapStatusDetails(tester, expand: true);
    expect(find.text('zec-auto-txid'), findsWidgets);
    expect(find.textContaining('Could not send ZEC deposit'), findsNothing);
  });

  testWidgets('ZEC deposit preflight failure does not start a swap intent', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final depositSender = _FakeSwapDepositSender(
      preflightError: Exception(
        'Propose failed: Insufficient balance (have 0, need 210000 including fee)',
      ),
    );
    final sessionStore = _FakeSwapPersistenceStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        depositSender: depositSender,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '0.002',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    expect(depositSender.preflightRequests, hasLength(1));
    expect(depositSender.requests, isEmpty);
    expect(swapProvider.startedQuotes, isEmpty);
    expect(swapProvider.submittedDeposits, isEmpty);
    expect(sessionStore.savedIntents, isEmpty);
    expect(find.byKey(const ValueKey('swap_review_panel')), findsOneWidget);
    expect(
      find.textContaining('ZEC deposit could not be prepared.'),
      findsOneWidget,
    );
    expect(find.textContaining('Insufficient balance'), findsNothing);
  });

  testWidgets('hardware ZEC swaps open deposit page before Keystone signing', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final depositSender = _FakeSwapDepositSender();
    final hardwareSigningService = _FakeSwapHardwareSigningService();
    final sessionStore = _FakeSwapPersistenceStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        bootstrap: _hardwareBootstrap,
        swapProvider: swapProvider,
        depositSender: depositSender,
        hardwareSigningService: hardwareSigningService,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '0.003',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(depositSender.preflightRequests, hasLength(1));
    expect(depositSender.requests, isEmpty);
    expect(swapProvider.startedQuotes, hasLength(1));
    expect(swapProvider.submittedDeposits, isEmpty);
    expect(sessionStore.savedIntents, hasLength(1));
    expect(
      sessionStore.savedIntents.single.status,
      SwapIntentStatus.awaitingDeposit,
    );
    expect(sessionStore.savedIntents.single.depositTxHash, isNull);
    expect(hardwareSigningService.depositDrafts, isEmpty);
    expect(find.byKey(const ValueKey('swap_review_panel')), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_deposit_tokens_panel')),
      findsOneWidget,
    );
    final detailRect = tester.getRect(
      find.byKey(const ValueKey('swap_activity_detail_page')),
    );
    final depositRect = tester.getRect(
      find.byKey(const ValueKey('swap_deposit_tokens_panel')),
    );
    expect(depositRect.center.dy, closeTo(detailRect.center.dy, 1));
    expect(find.text('Deposit tokens'), findsOneWidget);
    expect(find.text('0.0030 ZEC'), findsWidgets);
    expect(find.text('t1live-deposit'), findsOneWidget);
    expect(find.text('Deposit ZEC'), findsOneWidget);
    expect(find.text("I've deposited"), findsNothing);
    expect(find.text('Sign ZEC deposit on Keystone'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_hardware_deposit_action_panel')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('swap_deposit_confirm_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(hardwareSigningService.depositDrafts, ['t1live-deposit']);
    expect(find.text('Sign ZEC deposit on Keystone'), findsWidgets);
    final paneRect = tester.getRect(
      find.byKey(const ValueKey('swap_activity_detail_pane')),
    );
    final signingOverlayRect = tester.getRect(
      find.byKey(const ValueKey('swap_keystone_signing_overlay_surface')),
    );
    expect(signingOverlayRect.left, closeTo(paneRect.left, 1));
    expect(signingOverlayRect.top, closeTo(paneRect.top, 1));
    expect(signingOverlayRect.right, closeTo(paneRect.right, 1));
    expect(signingOverlayRect.bottom, closeTo(paneRect.bottom, 1));
  });

  testWidgets(
    'hardware ZEC signing shows QR while proofs are still preparing',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _FakeSwapProvider();
      final depositSender = _FakeSwapDepositSender();
      final proofCompleter = Completer<List<int>>();
      final hardwareSigningService = _FakeSwapHardwareSigningService(
        proofCompleter: proofCompleter,
      );
      final sessionStore = _FakeSwapPersistenceStore();

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [_swapRoute(), _swapActivityRoute()],
          ),
          bootstrap: _hardwareBootstrap,
          swapProvider: swapProvider,
          depositSender: depositSender,
          hardwareSigningService: hardwareSigningService,
          sessionStore: sessionStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '0.003',
      );
      await _enterDestinationText(
        tester,
        '0x52908400098527886e0f7030069857d2e4169ee7',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('swap_start_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('swap_start_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('swap_deposit_confirm_button')),
      );
      await tester.pump();
      for (
        var i = 0;
        i < 20 && hardwareSigningService.proofDrafts.isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(hardwareSigningService.proofDrafts, hasLength(1));
      expect(find.text('Sign ZEC deposit on Keystone'), findsOneWidget);
      expect(
        find.text('Scan now. Signature import unlocks after proofs are ready.'),
        findsOneWidget,
      );
      expect(find.text('Preparing'), findsOneWidget);
      expect(find.text('Get signature'), findsNothing);

      proofCompleter.complete(const [7, 8, 9]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Get signature'), findsOneWidget);
    },
  );

  testWidgets('hardware ZEC signing cancel keeps the deposit page', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final depositSender = _FakeSwapDepositSender();
    final hardwareSigningService = _FakeSwapHardwareSigningService();
    final sessionStore = _FakeSwapPersistenceStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        bootstrap: _hardwareBootstrap,
        swapProvider: swapProvider,
        depositSender: depositSender,
        hardwareSigningService: hardwareSigningService,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '0.003',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    expect(sessionStore.savedIntents, hasLength(1));
    expect(hardwareSigningService.depositDrafts, isEmpty);

    await tester.tap(find.byKey(const ValueKey('swap_deposit_confirm_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(hardwareSigningService.depositDrafts, ['t1live-deposit']);

    await tester.tap(find.text('Reject'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(sessionStore.savedIntents, hasLength(1));
    expect(find.text('Sign ZEC deposit on Keystone'), findsNothing);
    expect(find.text('Deposit tokens'), findsOneWidget);
    expect(find.text('Deposit ZEC'), findsOneWidget);
  });

  testWidgets(
    'hardware ZEC broadcast storage failure still records deposit txid',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _FakeSwapProvider();
      final depositSender = _FakeSwapDepositSender();
      final hardwareSigningService = _FakeSwapHardwareSigningService(
        broadcastStatus: 'broadcasted_storage_failed',
        broadcastMessage: 'local storage failed after broadcast',
      );
      final sessionStore = _FakeSwapPersistenceStore();

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [
              _swapRoute(),
              _swapActivityRoute(),
              GoRoute(
                path: '/send/keystone/scan',
                builder: (_, _) => const _FakeKeystoneScanScreen(),
              ),
            ],
          ),
          bootstrap: _hardwareBootstrap,
          swapProvider: swapProvider,
          depositSender: depositSender,
          hardwareSigningService: hardwareSigningService,
          sessionStore: sessionStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '0.003',
      );
      await _enterDestinationText(
        tester,
        '0x52908400098527886e0f7030069857d2e4169ee7',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('swap_start_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('swap_start_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('swap_deposit_confirm_button')),
      );
      await tester.pump();
      for (
        var i = 0;
        i < 20 && hardwareSigningService.proofDrafts.isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(hardwareSigningService.proofDrafts, hasLength(1));
      await tester.pump();

      await tester.tap(find.text('Get signature'));
      for (
        var i = 0;
        i < 20 &&
            find
                .byKey(const ValueKey('fake_keystone_signature_done'))
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.byKey(const ValueKey('fake_keystone_signature_done')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('fake_keystone_signature_done')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      expect(hardwareSigningService.broadcasts, hasLength(1));
      expect(swapProvider.submittedDeposits, hasLength(1));
      expect(
        swapProvider.submittedDeposits.single.txHash,
        'hardware-broadcast-txid',
      );
      expect(
        sessionStore.savedIntents.single.depositTxHash,
        'hardware-broadcast-txid',
      );
      await _openSwapStatusDetails(tester, expand: true);
      expect(find.text('hardware- ... st-txid'), findsWidgets);
      expect(find.text('Sign ZEC deposit on Keystone'), findsNothing);
    },
  );

  testWidgets(
    'hardware ZEC unknown broadcast is checkpointed without provider submit',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _FakeSwapProvider();
      final depositSender = _FakeSwapDepositSender();
      final hardwareSigningService = _FakeSwapHardwareSigningService(
        broadcastStatus: SwapDepositBroadcastStatus.broadcastUnknown,
        broadcastMessage: 'broadcast timed out before confirmation',
      );
      final sessionStore = _FakeSwapPersistenceStore();

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [
              _swapRoute(),
              _swapActivityRoute(),
              GoRoute(
                path: '/send/keystone/scan',
                builder: (_, _) => const _FakeKeystoneScanScreen(),
              ),
            ],
          ),
          bootstrap: _hardwareBootstrap,
          swapProvider: swapProvider,
          depositSender: depositSender,
          hardwareSigningService: hardwareSigningService,
          sessionStore: sessionStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '0.003',
      );
      await _enterDestinationText(
        tester,
        '0x52908400098527886e0f7030069857d2e4169ee7',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('swap_start_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('swap_start_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('swap_deposit_confirm_button')),
      );
      await tester.pump();
      for (
        var i = 0;
        i < 20 && hardwareSigningService.proofDrafts.isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(hardwareSigningService.proofDrafts, hasLength(1));
      await tester.pump();

      await tester.tap(find.text('Get signature'));
      for (
        var i = 0;
        i < 20 &&
            find
                .byKey(const ValueKey('fake_keystone_signature_done'))
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.byKey(const ValueKey('fake_keystone_signature_done')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('fake_keystone_signature_done')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      expect(hardwareSigningService.broadcasts, hasLength(1));
      expect(swapProvider.submittedDeposits, isEmpty);
      expect(
        sessionStore.savedIntents.single.depositTxHash,
        'hardware-broadcast-txid',
      );
      expect(
        sessionStore.savedIntents.single.broadcastNotice,
        'broadcast timed out before confirmation',
      );
      await _openSwapStatusDetails(tester, expand: true);
      expect(find.text('hardware- ... st-txid'), findsWidgets);
      expect(
        find.text('broadcast timed out before confirmation'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'hardware unknown ZEC broadcast switches to a fallback endpoint',
    (tester) async {
      // pending_broadcast/partial_broadcast are dropped by the Keystone
      // overlay's _hasBroadcastTxid gate (no txid to forward), so the only
      // non-certain status that reaches submitDepositTransactionForIntent on
      // the hardware path is broadcast_unknown.
      await _setDesktopViewport(tester);
      final swapProvider = _FakeSwapProvider();
      final depositSender = _FakeSwapDepositSender();
      final hardwareSigningService = _FakeSwapHardwareSigningService(
        broadcastStatus: SwapDepositBroadcastStatus.broadcastUnknown,
        broadcastMessage: 'gRPC connect failed: connection refused',
      );
      final sessionStore = _FakeSwapPersistenceStore();
      final primary = defaultRpcEndpointConfig('main');
      final fallback = fallbackRpcEndpointCandidatesFor(primary).first;

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [
              _swapRoute(),
              _swapActivityRoute(),
              GoRoute(
                path: '/send/keystone/scan',
                builder: (_, _) => const _FakeKeystoneScanScreen(),
              ),
            ],
          ),
          bootstrap: _hardwareBootstrap,
          swapProvider: swapProvider,
          depositSender: depositSender,
          hardwareSigningService: hardwareSigningService,
          sessionStore: sessionStore,
          failoverChainNameGetter: (_) async => 'main',
          failoverHeightGetter: (_) async => BigInt.from(100),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SwapScreen)),
      );

      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '0.003',
      );
      await _enterDestinationText(
        tester,
        '0x52908400098527886e0f7030069857d2e4169ee7',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('swap_start_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('swap_start_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('swap_deposit_confirm_button')),
      );
      await tester.pump();
      for (
        var i = 0;
        i < 20 && hardwareSigningService.proofDrafts.isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(hardwareSigningService.proofDrafts, hasLength(1));
      await tester.pump();

      await tester.tap(find.text('Get signature'));
      for (
        var i = 0;
        i < 20 &&
            find
                .byKey(const ValueKey('fake_keystone_signature_done'))
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.byKey(const ValueKey('fake_keystone_signature_done')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('fake_keystone_signature_done')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      expect(hardwareSigningService.broadcasts, hasLength(1));
      final failoverState = container.read(rpcEndpointFailoverProvider);
      expect(failoverState.isUsingFallback, isTrue);
      expect(
        failoverState.current.normalizedLightwalletdUrl,
        fallback.normalizedLightwalletdUrl,
      );
      final syncNotifier =
          container.read(syncProvider.notifier) as _FakeSwapSyncNotifier;
      expect(syncNotifier.restartCount, 1);
    },
  );

  testWidgets('hardware receive-ZEC swaps start without automatic signing', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final depositSender = _FakeSwapDepositSender();
    final hardwareSigningService = _FakeSwapHardwareSigningService();
    final sessionStore = _FakeSwapPersistenceStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        bootstrap: _hardwareBootstrap,
        swapProvider: swapProvider,
        depositSender: depositSender,
        hardwareSigningService: hardwareSigningService,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('swap_direction_externalToZec')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '8.5',
    );
    await _enterDestinationText(
      tester,
      '0x8617e340b3d01fa5f11f306f4090fd50e238070d',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    expect(depositSender.preflightRequests, isEmpty);
    expect(depositSender.requests, isEmpty);
    final quoteDestinations = swapProvider.requests.map(
      (request) => request.destination,
    );
    expect(quoteDestinations, contains('u1actualshieldedrecipient'));
    expect(
      quoteDestinations,
      isNot(contains(_hardwareBootstrap.initialAccountState.activeAddress)),
    );
    expect(swapProvider.startedQuotes, hasLength(1));
    expect(swapProvider.submittedDeposits, isEmpty);
    expect(sessionStore.savedIntents, hasLength(1));
    expect(
      sessionStore.savedIntents.single.status,
      isIn([
        SwapIntentStatus.awaitingExternalDeposit,
        SwapIntentStatus.processing,
      ]),
    );
    expect(hardwareSigningService.depositDrafts, isEmpty);
    expect(find.byKey(const ValueKey('swap_review_panel')), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_hardware_deposit_action_panel')),
      findsNothing,
    );
    expect(find.text('Sign ZEC deposit on Keystone'), findsNothing);
  });

  testWidgets('starting a ZEC swap ignores duplicate taps while in flight', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _DelayedStartSwapProvider();
    final depositSender = _FakeSwapDepositSender();
    final sessionStore = _FakeSwapPersistenceStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        swapProvider: swapProvider,
        depositSender: depositSender,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await _enterDestinationText(
      tester,
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pump();
    expect(find.text('Sending'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pump();

    expect(swapProvider.startedQuotes, hasLength(1));
    expect(depositSender.requests, isEmpty);

    swapProvider.completeStart();
    await tester.pumpAndSettle();

    expect(swapProvider.startedQuotes, hasLength(1));
    expect(depositSender.requests, hasLength(1));
    expect(swapProvider.submittedDeposits, hasLength(1));
  });
}

const _figmaModalSurfaceShadows = [
  BoxShadow(color: Color(0x14000000), offset: Offset(0, 14), blurRadius: 28),
  BoxShadow(color: Color(0x08000000), offset: Offset(0, -6), blurRadius: 12),
  BoxShadow(color: Color(0x0F000000), offset: Offset(0, 2), blurRadius: 8),
];

Widget _routerHarness(
  GoRouter router, {
  SwapProvider? swapProvider,
  SwapDepositSender? depositSender,
  SwapMaxAmountEstimator? maxAmountEstimator,
  SwapHardwareSigningService? hardwareSigningService,
  _FakeSwapPersistenceStore? sessionStore,
  BigInt? spendableBalance,
  Duration? statusPollInterval,
  Duration? priceRefreshInterval,
  LoadShieldedAddress? loadShieldedAddress,
  bool seedSwapActivityFixtures = true,
  AppBootstrapState? bootstrap,
  AccountNotifier Function()? accountNotifier,
  AddressBookRepository? addressBookRepository,
  RpcEndpointChainNameGetter? failoverChainNameGetter,
  RpcEndpointLatestBlockHeightGetter? failoverHeightGetter,
}) {
  final fixtureIntents = seedSwapActivityFixtures
      ? _accountScopedSwapActivityFixtureIntents()
      : const <SwapIntent>[];
  final effectiveSessionStore =
      sessionStore ?? _FakeSwapPersistenceStore(initialIntents: fixtureIntents);
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(bootstrap ?? _bootstrap),
      addressBookRepositoryProvider.overrideWithValue(
        addressBookRepository ?? _FakeAddressBookRepository(),
      ),
      if (accountNotifier != null)
        accountProvider.overrideWith(accountNotifier),
      syncProvider.overrideWith(
        () =>
            _FakeSwapSyncNotifier(spendableBalance ?? BigInt.from(10000000000)),
      ),
      receiveAddressServiceProvider.overrideWith(
        _FakeReceiveAddressService.new,
      ),
      swapZecStagingAddressServiceProvider.overrideWith(
        (ref) => SwapZecStagingAddressService(
          loadCurrentShieldedAddress:
              loadShieldedAddress ??
              ({required accountUuid}) {
                return ref
                    .read(receiveAddressServiceProvider)
                    .loadShieldedAddress(accountUuid: accountUuid);
              },
          prepareFreshShieldedAddress:
              loadShieldedAddress ??
              ({required accountUuid}) {
                final receiveAddressService = ref.read(
                  receiveAddressServiceProvider,
                );
                return receiveAddressService.renewShieldedAddress(
                  accountUuid: accountUuid,
                );
              },
        ),
      ),
      swapIntentProvider.overrideWithValue(swapProvider ?? _FakeSwapProvider()),
      swapDepositSenderProvider.overrideWithValue(
        depositSender ?? _FakeSwapDepositSender(),
      ),
      swapMaxAmountEstimatorProvider.overrideWithValue(
        maxAmountEstimator ?? _FakeSwapMaxAmountEstimator(),
      ),
      swapHardwareSigningServiceProvider.overrideWithValue(
        hardwareSigningService ?? _FakeSwapHardwareSigningService(),
      ),
      swapActivityStoreProvider.overrideWithValue(effectiveSessionStore),
      swapComposerPreferencesStoreProvider.overrideWithValue(
        effectiveSessionStore,
      ),
      if (seedSwapActivityFixtures) ...[
        swapInitialIntentsProvider.overrideWithValue(fixtureIntents),
      ],
      if (priceRefreshInterval != null)
        swapPriceRefreshIntervalProvider.overrideWithValue(
          priceRefreshInterval,
        ),
      if (statusPollInterval != null)
        swapStatusPollIntervalProvider.overrideWithValue(statusPollInterval),
      // Always override the failover health probes so no test reaches real
      // FFI/network. The defaults report a non-matching chain, so fallback
      // health checks fail and failover stays inert unless a test opts in
      // with passing getters.
      rpcEndpointFailoverChainNameGetterProvider.overrideWithValue(
        failoverChainNameGetter ?? (_) async => 'inert-no-failover',
      ),
      rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
        failoverHeightGetter ?? (_) async => BigInt.zero,
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) {
        final media = MediaQuery.maybeOf(context);
        final themed = AppTheme(data: AppThemeData.light, child: child!);
        if (media == null) return themed;
        return MediaQuery(
          data: media.copyWith(disableAnimations: true),
          child: themed,
        );
      },
    ),
  );
}

GoRoute _swapRoute() {
  return GoRoute(
    path: '/swap',
    builder: (_, _) => const SwapScreen(),
    routes: [
      GoRoute(path: 'review', builder: (_, _) => const SwapReviewScreen()),
    ],
  );
}

GoRoute _swapActivityRoute() {
  return GoRoute(
    path: '/activity',
    builder: (_, _) => const ActivityScreen(),
    routes: [
      GoRoute(
        path: 'swap/:swapId',
        builder: (_, state) => SwapActivityDetailScreen(
          swapIntentId: state.pathParameters['swapId'] ?? '',
          returnTarget: SwapActivityReturnTarget.fromQueryValue(
            state.uri.queryParameters[swapActivityReturnQueryKey],
          ),
          autoSignZecDeposit:
              state.uri.queryParameters[swapActivitySignQueryKey] ==
              swapActivitySignZecDepositValue,
        ),
      ),
    ],
  );
}

List<SwapIntent> _accountScopedSwapActivityFixtureIntents() {
  return [
    for (final intent in swapActivityFixtureIntents)
      intent.copyWith(accountUuid: 'account-1'),
  ];
}

Widget _themeHarness(Widget child) {
  return _themeHarnessWithTheme(AppThemeData.light, child);
}

Widget _themeHarnessWithTheme(AppThemeData theme, Widget child) {
  return AppTheme(
    data: theme,
    child: Directionality(textDirection: TextDirection.ltr, child: child),
  );
}

final _testShitAsset = SwapAsset.live(
  assetId: 'test-shit-sol',
  symbol: r'$SHIT',
  blockchain: 'sol',
  decimals: 6,
);

void _expectSummaryAmountPartsFitCard(
  WidgetTester tester, {
  required String keyPrefix,
  required String numberText,
  required String symbolText,
  required Key cardKey,
}) {
  final cardFinder = find.byKey(cardKey);
  final numberFinder = find.descendant(
    of: cardFinder,
    matching: find.byKey(ValueKey('${keyPrefix}_number')),
  );
  final symbolFinder = find.descendant(
    of: cardFinder,
    matching: find.byKey(ValueKey('${keyPrefix}_symbol')),
  );
  expect(numberFinder, findsOneWidget);
  expect(symbolFinder, findsOneWidget);
  expect(tester.widget<Text>(numberFinder).data, numberText);
  expect(tester.widget<Text>(symbolFinder).data, symbolText);
  expect(
    find.ancestor(of: numberFinder, matching: find.byType(FittedBox)),
    findsOneWidget,
  );

  final cardRect = tester.getRect(cardFinder);
  for (final finder in [numberFinder, symbolFinder]) {
    final rect = tester.getRect(finder);
    expect(
      rect.left,
      greaterThanOrEqualTo(cardRect.left),
      reason: '$keyPrefix should stay inside the summary card',
    );
    expect(
      rect.right,
      lessThanOrEqualTo(cardRect.right),
      reason: '$keyPrefix should stay inside the summary card',
    );
  }
}

Widget _reviewTestPage({
  required SwapDirection direction,
  required SwapAsset sellAsset,
  required SwapAsset receiveAsset,
  required String sellAmountText,
  required String receiveAmountText,
  Iterable<AddressBookContact> addressBookContacts = const [],
}) {
  final externalAsset = direction.sendsZec ? receiveAsset : sellAsset;
  return SwapReviewPageContent(
    quote: SwapQuote(
      direction: direction,
      sellAsset: sellAsset,
      receiveAsset: receiveAsset,
      externalAsset: externalAsset,
      sellAmount: 1,
      receiveAmount: 1,
      minimumReceiveAmount: 1,
      providerLabel: 'NEAR Intents',
      feeLabel: 'Included in shown rate',
      expiryLabel: '2hrs',
      depositInstruction: SwapDepositInstruction(
        asset: sellAsset,
        address: 't1testdepositaddress',
        expiresInLabel: '2hrs',
        reuseWarning: 'Do not reuse this address',
      ),
      sellAmountTextOverride: sellAmountText,
      receiveEstimateTextOverride: receiveAmountText,
      minimumReceiveTextOverride: receiveAmountText,
    ),
    addressPlan: SwapAddressPlan.fromUserInput(
      direction: direction,
      externalAsset: externalAsset,
      userExternalAddress: '0x52908400098527886e0f7030069857d2e4169ee7',
      walletZecAddress: 'u1wallet',
    ),
    addressBookContacts: addressBookContacts,
    accountLabel: 'John',
    expired: false,
    amountWarning: null,
    startError: null,
  );
}

Widget _statusTestPage({
  String title = 'Swapping ...',
  SwapAsset payAsset = SwapAsset.usdc,
  SwapAsset receiveAsset = SwapAsset.zec,
  String payFiatText = r'$110.24',
  String receiveFiatText = r'$110.24',
  String payAmountText = '999.99 USDC',
  String receiveAmountText = '0.251 ZEC',
  int progressIndex = 0,
  Duration progressAdvanceInterval = const Duration(milliseconds: 520),
  SwapStatusBadgeKind badgeKind = SwapStatusBadgeKind.liveQuote,
  SwapStatusTab activeTab = SwapStatusTab.progress,
  bool detailsExpanded = false,
  bool showTabs = true,
  List<SwapStatusDetailRowData>? details,
  VoidCallback? onToggleDetails,
}) {
  return SwapStatusPageContent(
    title: title,
    payAsset: payAsset,
    receiveAsset: receiveAsset,
    payFiatText: payFiatText,
    receiveFiatText: receiveFiatText,
    payAmountText: payAmountText,
    receiveAmountText: receiveAmountText,
    badgeKind: badgeKind,
    progressIndex: progressIndex,
    progressAdvanceInterval: progressAdvanceInterval,
    activeTab: activeTab,
    showTabs: showTabs,
    steps: const [
      SwapStatusStepData(
        title: 'USDC source deposit',
        state: SwapStatusStepState.pending,
        completeTitle: 'USDC Deposited',
        activeTitle: 'Depositing USDC...',
        pendingTitle: 'Deposit USDC',
        lastCheckedLabel: 'Last check: just now',
        description: 'Waiting for the source chain.',
      ),
      SwapStatusStepData(
        title: 'Deposit confirmation',
        state: SwapStatusStepState.pending,
        activeTitle: 'Deposit confirmation...',
        lastCheckedLabel: 'Last check: just now',
        description: 'Confirming the deposit.',
      ),
      SwapStatusStepData(
        title: 'Swap',
        state: SwapStatusStepState.pending,
        activeTitle: 'Swap...',
        lastCheckedLabel: 'Last check: just now',
        description: 'The provider is executing the swap route.',
      ),
      SwapStatusStepData(
        title: 'Send ZEC',
        state: SwapStatusStepState.pending,
        activeTitle: 'Send ZEC...',
        lastCheckedLabel: 'Last check: just now',
        description: 'Delivering ZEC.',
      ),
    ],
    details:
        details ??
        const [
          SwapStatusDetailRowData(label: 'Account', value: 'John'),
          SwapStatusDetailRowData(
            label: 'USDC refund address',
            value: '0x123kjhc ... 4x98g20',
          ),
          SwapStatusDetailRowData(
            label: 'Deposit USDC to',
            value: '0x123kjhc ... 4x98g20',
          ),
          SwapStatusDetailRowData(
            label: 'Swap fee',
            value: 'Included in shown rate',
            help: true,
          ),
          SwapStatusDetailRowData(
            label: 'Slippage tolerance',
            value: '0.25 USDC (0.5%)',
          ),
          SwapStatusDetailRowData(
            label: 'Guaranteed minimum',
            value: '0.249 ZEC',
            help: true,
          ),
        ],
    detailsExpanded: detailsExpanded,
    onToggleDetails: onToggleDetails,
    onOpenExplorer: () {},
  );
}

SwapIntent _persistedIntent({
  required String id,
  required String txHash,
  String? depositAddress,
  SwapIntentStatus status = SwapIntentStatus.processing,
  String? nextAction,
  String accountUuid = 'account-1',
}) {
  final effectiveNextAction = nextAction ?? status.label;
  return SwapIntent(
    id: id,
    pair: 'ZEC -> USDC',
    sellAmount: '1.5000 ZEC',
    receiveEstimate: '105.25 USDC',
    provider: 'NEAR Intents',
    status: status,
    nextAction: effectiveNextAction,
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: depositAddress ?? id,
    depositMemo: 'memo-7',
    depositTxHash: txHash,
    providerQuoteId: 'quote-1',
    oneClickRecipient: '0x52908400098527886e0f7030069857d2e4169ee7',
    oneClickRefundTo: 'u1refund',
    accountUuid: accountUuid,
  );
}

SwapIntentSnapshot _statusSnapshot({required String id}) {
  return SwapIntentSnapshot(
    id: id,
    providerLabel: 'NEAR Intents',
    pairText: 'ZEC -> USDC',
    sellAmountText: '1.5000 ZEC',
    receiveEstimateText: '105.25 USDC',
    status: SwapIntentStatus.processing,
    nextAction: 'Swap is processing',
    depositInstruction: SwapDepositInstruction(
      asset: SwapAsset.zec,
      address: id,
      expiresInLabel: '07:12',
      reuseWarning: 'Do not reuse this address',
      memo: 'memo-7',
    ),
  );
}

SwapIntent _persistedExternalToZecIntent({
  required String id,
  required String stagingAddress,
}) {
  return SwapIntent(
    id: id,
    pair: 'USDC -> ZEC',
    sellAmount: '140.350000 USDC',
    receiveEstimate: '2.0000 ZEC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.awaitingExternalDeposit,
    nextAction: 'Waiting for the stored source-chain deposit',
    direction: SwapDirection.externalToZec,
    externalAsset: SwapAsset.usdc,
    depositAddress: id,
    depositMemo: 'memo-7',
    providerQuoteId: 'quote-1',
    oneClickRecipient: stagingAddress,
    oneClickRefundTo: '0xpersisted-refund',
  );
}

class _DepositSendRequest {
  const _DepositSendRequest({
    required this.accountUuid,
    required this.depositAddress,
    required this.sellAmountText,
    required this.sellAmountBaseUnits,
  });

  final String accountUuid;
  final String depositAddress;
  final String sellAmountText;
  final BigInt? sellAmountBaseUnits;
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await _setViewport(tester, const Size(1512, 982));
}

Future<void> _sendShortcut(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _openActivitySurface(WidgetTester tester) async {
  final context = tester.element(find.byType(AppDesktopShell).first);
  GoRouter.of(context).go('/activity');
  await _pumpUntilPresent(
    tester,
    find.byKey(const ValueKey('activity_screen_title_row')),
  );
  await tester.pump(const Duration(milliseconds: 250));
  await _pumpUntilAbsent(
    tester,
    find.byKey(const ValueKey('swap_compact_ticket')),
  );
}

Future<void> _openSwapSurface(WidgetTester tester) async {
  final context = tester.element(find.byType(AppDesktopShell).first);
  GoRouter.of(context).go('/swap');
  await _pumpUntilPresent(
    tester,
    find.byKey(const ValueKey('swap_compact_ticket')),
  );
}

Future<void> _openActivityDetail(WidgetTester tester, String intentId) async {
  await _closeActivityDetail(tester);
  final context = tester.element(find.byType(AppDesktopShell).first);
  GoRouter.of(context).go(
    swapActivityDetailUri(
      intentId: intentId,
      returnTarget: SwapActivityReturnTarget.activity,
    ).toString(),
  );
  await _pumpUntilPresent(
    tester,
    find.byKey(const ValueKey('swap_activity_detail_page')),
  );
}

Future<void> _closeActivityDetail(WidgetTester tester) async {
  final page = find.byKey(const ValueKey('swap_activity_detail_page'));
  if (page.evaluate().isEmpty) return;
  final context = tester.element(find.byType(AppDesktopShell).first);
  GoRouter.of(context).go('/activity');
  await _pumpUntilAbsent(
    tester,
    find.byKey(const ValueKey('swap_activity_detail_page')),
  );
}

Future<void> _pumpUntilPresent(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

Future<void> _pumpUntilAbsent(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isEmpty) return;
  }
}

Future<void> _openSwapStatusDetails(
  WidgetTester tester, {
  bool expand = false,
}) async {
  final tab = find.byKey(const ValueKey('swap_status_tab_details'));
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
  if (!expand) return;

  final moreDetails = find.text('More details');
  if (moreDetails.evaluate().isEmpty) return;
  await tester.ensureVisible(moreDetails);
  await tester.pumpAndSettle();
  await tester.tap(moreDetails);
  await tester.pumpAndSettle();
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/swap',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1swapaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

final _twoAccountBootstrap = AppBootstrapState(
  initialLocation: '/swap',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(uuid: 'account-1', name: 'Primary', order: 0),
      AccountInfo(uuid: 'account-2', name: 'Trading', order: 1),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1accountone',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

final _hardwareBootstrap = AppBootstrapState(
  initialLocation: '/swap',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Keystone',
        order: 0,
        isHardware: true,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1swapaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

Future<void> _enterDestinationText(WidgetTester tester, String value) async {
  final field = find.byKey(const ValueKey('swap_destination_field'));
  if (field.evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
  }
  await tester.enterText(field, value);
  await tester.tap(find.byKey(const ValueKey('swap_address_update_button')));
  await tester.pumpAndSettle();
}

String _destinationSummaryText(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('swap_destination_value'));
  if (finder.evaluate().isEmpty) return '';
  final text = tester.widget<Text>(finder.first).data ?? '';
  return text.startsWith('Add ') ? '' : text;
}

Finder _tooltipWithMessage(String message) {
  return find.byWidgetPredicate(
    (widget) => widget is Tooltip && widget.message == message,
  );
}

String _fieldText(WidgetTester tester, String keyValue) {
  final editable = tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(ValueKey(keyValue)),
      matching: find.byType(EditableText),
    ),
  );
  return editable.controller.text;
}
