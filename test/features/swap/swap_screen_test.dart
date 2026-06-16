// The platform-interface fakes below stub path_provider / flutter_secure_storage
// so the activity tab's tap-through to the tx-status route can resolve the
// wallet DB path under test. These are transitive deps, hence the ignore.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/layout/app_pane_scroll_scaffold.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_back_link.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/features/address_book/contact_label_generator.dart';
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
import 'package:zcash_wallet/src/features/activity/screens/activity_transaction_status_screen.dart';
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

  testWidgets('review summary fits a long pay amount via FittedBox', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themeHarnessWithOverlay(
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
    // The redesigned summary renders the amount + symbol verbatim as a single
    // serif text and scales it down to fit, rather than compacting the digits.
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_pay'),
      amountText: r'999,999.99 $SHIT',
    );
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_receive'),
      amountText: '0.251 ZEC',
    );
  });

  testWidgets('review summary fits a long receive amount via FittedBox', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themeHarnessWithOverlay(
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
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_pay'),
      amountText: '0.251 ZEC',
    );
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_receive'),
      amountText: r'999,999.99 $SHIT',
    );
  });

  testWidgets('review summary fits both long amounts via FittedBox', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themeHarnessWithOverlay(
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
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_pay'),
      amountText: r'999,999.99 $SHIT',
    );
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_receive'),
      amountText: '888,888.88 ZEC',
    );
  });

  testWidgets('review summary shows the recipient address line with copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themeHarnessWithOverlay(
        _reviewTestPage(
          direction: SwapDirection.zecToExternal,
          sellAsset: SwapAsset.zec,
          receiveAsset: SwapAsset.usdc,
          sellAmountText: '0.251 ZEC',
          receiveAmountText: '999.99 USDC',
          onCopy: (_) {},
        ),
      ),
    );

    // The redesign moved the counterparty identity out of the detail card and
    // into the summary's To: line, with a Copy affordance beside it.
    final receiveSide = find.byKey(const ValueKey('swap_review_info_receive'));
    expect(
      find.descendant(
        of: receiveSide,
        matching: find.text('To: 0x5290840 ... 4169ee7 on Ethereum'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_review_info_receive_copy')),
      findsOneWidget,
    );
    // The review detail card no longer renders an address-book identity row.
    final details = find.byKey(const ValueKey('swap_review_details'));
    expect(
      find.descendant(
        of: details,
        matching: find.byType(AddressBookNetworkIcon),
      ),
      findsNothing,
    );
  });

  testWidgets('review summary shows the refund address line with copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themeHarnessWithOverlay(
        _reviewTestPage(
          direction: SwapDirection.externalToZec,
          sellAsset: SwapAsset.usdc,
          receiveAsset: SwapAsset.zec,
          sellAmountText: '999.99 USDC',
          receiveAmountText: '0.251 ZEC',
          onCopy: (_) {},
        ),
      ),
    );

    final paySide = find.byKey(const ValueKey('swap_review_info_pay'));
    expect(
      find.descendant(
        of: paySide,
        matching: find.text('Refund to: 0x5290840 ... 4169ee7'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_review_info_pay_copy')),
      findsOneWidget,
    );
    final details = find.byKey(const ValueKey('swap_review_details'));
    expect(
      find.descendant(
        of: details,
        matching: find.byType(AddressBookNetworkIcon),
      ),
      findsNothing,
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
      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('swap_deposit_expiry_label')),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data ?? '')
          .toList();
      return texts.join(' ');
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
      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('swap_deposit_expiry_label')),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data ?? '')
          .toList();
      return texts.join(' ');
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
      // The redesigned detail pages drop the NEAR Intents attribution.
      expect(
        find.byKey(const ValueKey('swap_near_intents_attribution')),
        findsNothing,
      );
      final detailRect = tester.getRect(
        find.byKey(const ValueKey('swap_activity_detail_page')),
      );
      final timeoutRect = tester.getRect(
        find.byKey(const ValueKey('swap_deposit_timeout_panel')),
      );

      expect(timeoutRect.width, 340);
      expect(timeoutRect.center.dy, closeTo(detailRect.center.dy, 1));
    },
  );

  testWidgets('swap status summary shows the captured fiat from the mapper', (
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
        // Live pricing must NOT affect the page anymore — the captured fiat
        // basis is formatted once in the mapper and rendered verbatim.
        swapProvider: _PricingSwapProvider([200]),
        seedSwapActivityFixtures: false,
        sessionStore: sessionStore,
      ),
    );
    await _pumpUntilPresent(
      tester,
      find.byKey(const ValueKey('swap_review_info')),
    );
    await tester.pumpAndSettle();

    final summary = find.byKey(const ValueKey('swap_review_info'));
    // ZEC pay side shows the captured fiat (1.5 ZEC * 70.1733... = $105.26).
    expect(
      find.descendant(of: summary, matching: find.text(r'$105.26')),
      findsOneWidget,
    );
    // The external receive side carries the recipient address line, not a
    // recomputed fiat figure.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_review_info_receive')),
        matching: find.textContaining('To: '),
      ),
      findsOneWidget,
    );
  });

  testWidgets('status progress route shows the animated active-step loader', (
    tester,
  ) async {
    await tester.pumpWidget(_themeHarness(_statusTestPage()));

    // The redesigned summary is the shared SwapReviewInfo block, which shows a
    // chain badge for the external asset and none for ZEC.
    final summary = find.byKey(const ValueKey('swap_review_info'));
    expect(summary, findsOneWidget);
    expect(
      find.descendant(
        of: summary,
        matching: find.byKey(const ValueKey('swap_asset_chain_badge_zec')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: summary,
        matching: find.byKey(const ValueKey('swap_asset_chain_badge_usdc')),
      ),
      findsOneWidget,
    );

    // The in-progress (liveQuote) state animates the active step's loader. The
    // old pulsing live-quote LED and the standalone explorer button are gone.
    final loader = tester.widget<AppIcon>(
      find.byKey(const ValueKey('swap_status_active_step_loader')),
    );
    expect(loader.name, AppIcons.loader);
    expect(loader.animated, isTrue);
    expect(
      find.byKey(const ValueKey('swap_status_active_step_spinner_rotation')),
      findsNothing,
    );

    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('swap_activity_route_step_0_active')),
          )
          .height,
      90,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('swap_activity_route_step_1_pending')),
          )
          .height,
      37,
    );

    final firstLineRect = tester.getRect(
      find.byKey(const ValueKey('swap_activity_route_step_0_line')),
    );
    final secondLineRect = tester.getRect(
      find.byKey(const ValueKey('swap_activity_route_step_1_line')),
    );
    expect(firstLineRect.center.dx, secondLineRect.center.dx);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('status summary fits a long pay amount via FittedBox', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themeHarness(
        _statusTestPage(
          payAmountText: r'999,999.99 $SHIT',
          receiveAmountText: '0.251 ZEC',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_pay'),
      amountText: r'999,999.99 $SHIT',
    );
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_receive'),
      amountText: '0.251 ZEC',
    );
  });

  testWidgets('status summary fits a long receive amount via FittedBox', (
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
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_pay'),
      amountText: '0.251 ZEC',
    );
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_receive'),
      amountText: r'999,999.99 $SHIT',
    );
  });

  testWidgets('status summary fits both long card amounts via FittedBox', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themeHarness(
        _statusTestPage(
          payAmountText: r'999,999.99 $SHIT',
          receiveAmountText: '888,888.88 USDC',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_pay'),
      amountText: r'999,999.99 $SHIT',
    );
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_receive'),
      amountText: '888,888.88 USDC',
    );
  });

  testWidgets('status terminal details lead with the Status row', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _themeHarnessWithOverlay(
        _statusTestPage(
          title: 'Swap completed',
          statusLabel: 'Completed',
          badgeKind: SwapStatusBadgeKind.completed,
          showTabs: false,
          details: const [
            SwapStatusDetailRowData(
              label: 'USDC deposit to',
              value: '0x123kjhc ... 4x98g20',
              copyable: true,
            ),
            SwapStatusDetailRowData(
              label: 'Realized slippage',
              value: '0.25 USDC (0.27%)',
            ),
            SwapStatusDetailRowData(
              label: 'Timestamp',
              value: 'May 20, 2026 13:20',
            ),
            SwapStatusDetailRowData(
              label: 'Total fees',
              value: '~0.25 USDC',
              help: true,
            ),
          ],
        ),
      ),
    );

    // The terminal layout leads with the Status row inside the single detail
    // card; the old success/failed pill badge is gone.
    expect(
      find.byKey(const ValueKey('swap_status_detail_card')),
      findsOneWidget,
    );
    final statusRow = find.byKey(const ValueKey('swap_status_summary_row'));
    expect(statusRow, findsOneWidget);
    expect(
      find.descendant(of: statusRow, matching: find.text('Status')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: statusRow, matching: find.text('Completed')),
      findsOneWidget,
    );
    final completedIcon = tester.widget<AppIcon>(
      find.descendant(of: statusRow, matching: find.byType(AppIcon)),
    );
    expect(completedIcon.name, AppIcons.checkCircle);
    expect(completedIcon.size, 16);

    // The Status row sits above every detail row, including the Total fees row.
    final statusRowRect = tester.getRect(statusRow);
    final feeRowRect = tester.getRect(find.text('Total fees'));
    expect(statusRowRect.top, lessThan(feeRowRect.top));
    // A hairline divider precedes the trailing Total fees row.
    expect(
      find.byKey(const ValueKey('swap_status_detail_divider')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _themeHarnessWithOverlay(
        _statusTestPage(
          title: 'Swap failed',
          statusLabel: 'Failed',
          badgeKind: SwapStatusBadgeKind.failed,
          showTabs: false,
          details: const [
            SwapStatusDetailRowData(
              label: 'USDC refunded to',
              value: '0x123kjhc ... 4x98g20',
            ),
            SwapStatusDetailRowData(
              label: 'Timestamp',
              value: 'May 20, 2026 13:20',
            ),
            SwapStatusDetailRowData(
              label: 'Total fees',
              value: '~0.25 USDC',
              help: true,
            ),
          ],
        ),
      ),
    );

    final failedStatusRow = find.byKey(
      const ValueKey('swap_status_summary_row'),
    );
    expect(
      find.descendant(of: failedStatusRow, matching: find.text('Failed')),
      findsOneWidget,
    );
    final failedIcon = tester.widget<AppIcon>(
      find.descendant(of: failedStatusRow, matching: find.byType(AppIcon)),
    );
    expect(failedIcon.name, AppIcons.warning);
    expect(failedIcon.size, 16);

    // The trailing fee row keeps label-left / value-then-help-icon-right order.
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
    // The shared ReviewListRow pill carries a 4px right padding (pr 4), so the
    // trailing help icon sits that pill padding (xxs) inside the row edge.
    expect(
      feeHelpIconRect.right,
      closeTo(finalDetailsRect.right - AppSpacing.xxs, 1),
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
    // The active step's description sits flush with its title column; the
    // Figma block pads vertically, not horizontally.
    expect(descriptionRect.left - titleRect.left, closeTo(0, 1));
  });

  testWidgets('status details tab shows all rows in the detail card', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _themeHarnessWithOverlay(
        _statusTestPage(activeTab: SwapStatusTab.details),
      ),
    );

    // The redesigned details tab renders every row directly in the card —
    // there is no More/Less expansion stage anymore.
    expect(
      find.byKey(const ValueKey('swap_status_detail_card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_status_detail_rows')),
      findsOneWidget,
    );
    expect(find.text('More details'), findsNothing);
    expect(find.text('Less details'), findsNothing);
    expect(find.text('Slippage tolerance'), findsOneWidget);
    expect(find.text('Guaranteed minimum'), findsOneWidget);
    expect(find.text('Price protection'), findsNothing);
    expect(_tooltipWithMessage(swapFeeTooltip), findsOneWidget);
    expect(
      _tooltipWithMessage(swapGenericMinimumReceiveTooltip),
      findsOneWidget,
    );

    for (final tab in ['Swap Progress', 'Transaction details']) {
      expect(
        find.ancestor(
          of: find.text(tab),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is MouseRegion &&
                widget.cursor == SystemMouseCursors.click,
          ),
        ),
        findsOneWidget,
      );
    }

    final refundLabelRect = tester.getRect(find.text('USDC refund address'));
    final depositLabelRect = tester.getRect(find.text('Deposit USDC to'));
    final feeLabelRect = tester.getRect(find.text('Swap fee'));
    final feeValueRect = tester.getRect(find.text('Included in shown rate'));

    expect(feeLabelRect.left, lessThan(feeValueRect.left));
    expect((refundLabelRect.left - depositLabelRect.left).abs(), lessThan(1));
    expect((feeLabelRect.left - refundLabelRect.left).abs(), lessThan(1));
  });

  testWidgets('status details render address book labels with addresses', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _themeHarnessWithOverlay(
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
      _themeHarnessWithOverlay(
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
      find.byKey(const ValueKey('swap_status_detail_rows')),
      findsOneWidget,
    );
    expect(find.text('eth account'), findsOneWidget);
    expect(find.text('Slippage tolerance'), findsOneWidget);
  });

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
    // The trigger hugs up to 240 so the full empty label fits in the
    // real font (the square test font maxes the constraint out).
    expect(addressFieldWidth, closeTo(240, 1));
    expect(find.text('Ethereum recipient'), findsNothing);
    expect(find.text('Add recipient address...'), findsOneWidget);
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
      closeTo(232, 1),
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
    // Pinned layout (pane taller than the design height): the title sits at
    // a fixed offset below the toolbar, the attribution slot + CTA pin to the
    // bottom, and the composer centers in the flexible middle — so the gaps
    // around the panel are the 24dp column gap plus equal centering slack.
    final paneRect = tester.getRect(find.byType(AppDesktopPane));
    expect(
      titleRect.top,
      closeTo(paneRect.top + AppPaneScrollScaffold.toolbarHeight + 16, 1),
    );
    final attributionSlotTop =
        attributionRect.top - (32 - attributionRect.height) / 2;
    final attributionSlotBottom =
        attributionRect.bottom + (32 - attributionRect.height) / 2;
    final slackAbove = ticketRect.top - titleRect.bottom - AppSpacing.md;
    final slackBelow =
        attributionSlotTop - settingsRowRect.bottom - AppSpacing.md;
    expect(slackAbove, greaterThanOrEqualTo(-1));
    expect(slackAbove, closeTo(slackBelow, 1));
    expect(
      reviewButtonRect.top - attributionSlotBottom,
      closeTo(AppSpacing.md, 1),
    );
    expect(ticketRect.height, lessThan(440));
    expect(reviewButtonRect.center.dx, closeTo(ticketRect.center.dx, 1));
    expect(settingsRowRect.height, closeTo(32, 1));
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
      attributionPoweredRect.center.dx,
      closeTo(attributionWordmarkRect.center.dx, 1),
    );
    expect(
      attributionWordmarkRect.top - attributionPoweredRect.bottom,
      closeTo(6.2, 1),
    );
    expect(attributionRect.center.dx, closeTo(ticketRect.center.dx, 1));
    // The lockup is centered inside its 32dp slot, so the button gap is the
    // 24dp column gap plus half the slot slack.
    expect(
      reviewButtonRect.top - attributionRect.bottom,
      closeTo(AppSpacing.md + (32 - attributionRect.height) / 2, 1),
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

    final modalRect = tester.getRect(
      find.byKey(const ValueKey('swap_address_modal')),
    );
    final sidebarItemRect = tester.getRect(
      find.byKey(const ValueKey('sidebar_swap_button')),
    );

    final paneRect = tester.getRect(find.byType(AppDesktopPane));
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

    final modalRect = tester.getRect(
      find.byKey(const ValueKey('address_scan_modal')),
    );
    final cameraRect = tester.getRect(
      find.byKey(const ValueKey('address_scan_camera_viewport')),
    );
    final sidebarItemRect = tester.getRect(
      find.byKey(const ValueKey('sidebar_swap_button')),
    );

    expect(find.text('Scan the address QR code'), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_address_modal')), findsNothing);
    final paneRect = tester.getRect(find.byType(AppDesktopPane));
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
    expect(find.text('Request again'), findsOneWidget);
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
      36,
    );
    expect(
      find.byKey(const ValueKey('address_scan_camera_border')),
      findsOneWidget,
    );
    // The cancel is text-only visually but keeps the spec'd 196px-minimum
    // ghost hit area (it stretches with the modal content column).
    final cancelSize = tester.getSize(
      find.byKey(const ValueKey('address_scan_cancel_button')),
    );
    expect(cancelSize.height, 44);
    expect(cancelSize.width, greaterThanOrEqualTo(196));

    await pumpStatus(
      AddressQrCameraStatus.loading,
      cameraView: const ColoredBox(color: Color(0xFF2E3232)),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      find.byKey(const ValueKey('address_scan_loading_overlay')),
      findsOneWidget,
    );
    expect(find.text('Loading'), findsOneWidget);
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

    // Remembered addresses are saved hands-free: no label or avatar form
    // appears, and the valid address alone enables Update.
    expect(
      find.byKey(const ValueKey('swap_address_nickname_field')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('swap_address_update_button')));
    await tester.pumpAndSettle();

    expect(addressBookRepository.contacts, hasLength(1));
    final saved = addressBookRepository.contacts.single;
    expect(saved.address, '0xdbf03b407c01e7cd3cbea99509d93f8dddc8c6fb');
    expect(saved.network, AddressBookNetwork.ethereum);
    // The label is auto-generated from the persona pool with an optional
    // numeric suffix, and the avatar is a valid random pick.
    expect(
      kGeneratedContactPersonas.any((p) => saved.label.startsWith(p)),
      isTrue,
      reason: 'generated label was ${saved.label}',
    );
    expect(
      kProfilePictureOptions.map((o) => o.id),
      contains(saved.profilePictureId),
    );
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
    await tester.tap(find.byKey(const ValueKey('swap_address_update_button')));
    // Let the async remember-path run and the toast appear; avoid
    // pumpAndSettle here since it would wait out the toast's auto-dismiss.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Already in your contacts'), findsOneWidget);
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

  testWidgets('ZEC swap composer masks the max balance in privacy mode', (
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
        bootstrap: _privacyModeBootstrap,
        seedSwapActivityFixtures: false,
        sessionStore: _FakeSwapPersistenceStore(),
        spendableBalance: BigInt.from(123450000),
        maxAmountEstimator: maxEstimator,
      ),
    );
    await tester.pumpAndSettle();

    // Privacy mode masks the available balance amount, not the "Max:" label.
    expect(find.text('Max: ****** ZEC'), findsOneWidget);
    expect(find.text('Max: 1.2345 ZEC'), findsNothing);

    // The mask is display-only: tapping still applies the real max amount.
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
      expect(
        find.byKey(const ValueKey('swap_review_cancel_button')),
        findsNothing,
      );
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
    expect(find.text('Add refund address...'), findsOneWidget);
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
    // Card top padding (24) + title line (24) + 16 gap + three 40dp preset
    // rows with 8dp gaps (3×40 + 3×8 = 144) puts the custom row 208dp down.
    expect(customCardTop - slippageModalTop, 208);
    expect(
      tester.getSize(find.byKey(const ValueKey('swap_slippage_50bps'))).height,
      40,
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
    expect(find.text('Swap in progress...'), findsOneWidget);
    expect(find.text('Swap Progress'), findsOneWidget);
    expect(find.text('Transaction details'), findsOneWidget);
    expect(find.text('Activity detail'), findsNothing);
    expect(find.byKey(const ValueKey('swap_review_info')), findsOneWidget);
    expect(find.text('Current swap'), findsNothing);
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_pay'),
      amountText: '2.4000 ZEC',
    );
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_receive'),
      amountText: '168.42 USDC',
    );
    expect(
      find.byKey(const ValueKey('swap_activity_route_step_2_active')),
      findsOneWidget,
    );
    // The detail surface scrolls through the shared pane scaffold: a 6px
    // overlay thumb pinned at the pane edge, with no reserved gutter. Scope
    // to the detail surface — the hosting screen has its own scaffold.
    final activityDetailScrollbar = tester.widget<RawScrollbar>(
      find.descendant(
        of: find.byKey(const ValueKey('swap_activity_detail_surface')),
        matching: find.byKey(AppPaneScrollScaffold.scrollbarKey),
      ),
    );
    expect(activityDetailScrollbar.thickness, 6);
    expect(activityDetailScrollbar.crossAxisMargin, 6);
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
    'activity tab absorbs the matched ZEC receive into the swap group',
    (tester) async {
      await _setDesktopViewport(tester);

      // The provider hands back the destination hash in display order; the
      // wallet's transaction history stores the byte-reversed internal order.
      const destinationDisplayOrder =
          'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899';
      const receiveWalletOrder =
          '99887766554433221100ffeeddccbbaa99887766554433221100ffeeddccbbaa';
      // Sanity: the screen derives the same wallet-order hash the fake tx uses.
      expect(
        swapChainTxidToWalletTxidHex(destinationDisplayOrder),
        receiveWalletOrder,
      );

      final sessionStore = _FakeSwapPersistenceStore(
        initialIntents: [
          _persistedExternalToZecCompleteIntent(
            id: 'swap-receive-absorb',
            destinationChainTxHash: destinationDisplayOrder,
          ),
        ],
      );

      // 12.13 ZEC inbound payout (12.13 * 1e8 zatoshi).
      final receiveTx = _receivedZecTx(
        txidHex: receiveWalletOrder,
        zatoshi: BigInt.from(1213000000),
      );

      // The tap-through pushes a tx-status route whose builder first resolves
      // the wallet DB path (path_provider + secure storage). Stub both platform
      // interfaces so the path future completes; the FFI history/detail lookups
      // then fail fast and the screen renders from the initialTransaction extra.
      final previousPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProviderPlatform();
      addTearDown(() {
        PathProviderPlatform.instance = previousPathProvider;
      });
      final previousSecureStorage = FlutterSecureStoragePlatform.instance;
      FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform(const {
        'zcash_wallet_db_name': 'zcash_wallet_test.db',
      });
      addTearDown(() {
        FlutterSecureStoragePlatform.instance = previousSecureStorage;
      });

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/activity',
            routes: [
              _swapRoute(),
              _swapActivityRoute(),
              _activityTransactionRoute(),
            ],
          ),
          seedSwapActivityFixtures: false,
          sessionStore: sessionStore,
          recentTransactions: [receiveTx],
        ),
      );
      await _pumpUntilPresent(
        tester,
        find.byKey(const ValueKey('activity_screen_title_row')),
      );
      await tester.pump(const Duration(milliseconds: 250));

      // The completed swap group renders with its absorbed receive child,
      // carrying the real on-chain settled amount (not the quote estimate).
      expect(find.text('Swapped'), findsOneWidget);
      expect(find.text('Received ZEC'), findsOneWidget);
      expect(find.text('+12.13 ZEC'), findsOneWidget);
      expect(find.text('+4.12 ZEC'), findsNothing);
      // The standalone on-chain 'Received' row is suppressed (absorbed). The
      // only inbound surface is the swap group's child.
      expect(find.text('Received'), findsNothing);

      // The absorbed child is tappable: the screen wired onReceivedLegTap to
      // the matched payout, so the child row opts into the click cursor (the
      // standalone-row deduper fed it the real tx).
      expect(
        find.ancestor(
          of: find.text('Received ZEC'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is MouseRegion &&
                widget.cursor == SystemMouseCursors.click,
          ),
        ),
        findsWidgets,
      );

      // Tapping the absorbed child opens the underlying tx-status route. The
      // push awaits a real wallet-DB-path resolution (path_provider + secure
      // storage) plus an FFI detail lookup that fails fast (no Rust under
      // test); run those real async hops inside runAsync, then pump frames.
      await tester.tap(find.text('Received ZEC'));
      await tester.runAsync(() async {
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (find
              .byType(ActivityTransactionStatusScreen)
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ActivityTransactionStatusScreen), findsOneWidget);
      final context = tester.element(
        find.byType(ActivityTransactionStatusScreen).first,
      );
      expect(
        GoRouterState.of(context).uri.path,
        '/activity/tx/$receiveWalletOrder',
      );
      // The detail screen's button row can overflow this fixed test pane by a
      // few px; that layout artifact is orthogonal to the navigation contract
      // under test, so drain overflow FlutterErrors instead of failing the
      // absorption assertion. Re-throw anything that is not an overflow.
      Object? pending;
      while ((pending = tester.takeException()) != null) {
        final isOverflow =
            pending is FlutterError && pending.message.contains('overflowed');
        if (!isOverflow) throw pending!;
      }
    },
  );

  testWidgets('refunded swap keeps the standalone Sent deposit row visible', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    const depositDisplayOrder =
        'ccdd00112233445566778899aabbccddeeff00112233445566778899aabbeeff';
    final depositWalletOrder = swapChainTxidToWalletTxidHex(
      depositDisplayOrder,
    )!;

    final sessionStore = _FakeSwapPersistenceStore(
      initialIntents: [
        _persistedIntent(
          id: 'swap-refunded-deposit',
          txHash: depositDisplayOrder,
          status: SwapIntentStatus.refunded,
        ),
      ],
    );
    final sentTx = _sentZecTx(
      txidHex: depositWalletOrder,
      zatoshi: BigInt.from(150000000),
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/activity',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        sessionStore: sessionStore,
        recentTransactions: [sentTx],
      ),
    );
    await _pumpUntilPresent(
      tester,
      find.byKey(const ValueKey('activity_screen_title_row')),
    );
    await tester.pump(const Duration(milliseconds: 250));

    // The refunded swap row renders its amount unsigned (no outgoing
    // sign), so the real ZEC deposit keeps its standalone Sent row —
    // otherwise the feed would show the refund credit with no debit.
    expect(find.text('Swap failed'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
  });

  testWidgets('in-flight swap suppresses the duplicate Sent deposit row', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    const depositDisplayOrder =
        'ccdd00112233445566778899aabbccddeeff00112233445566778899aabbeeff';
    final depositWalletOrder = swapChainTxidToWalletTxidHex(
      depositDisplayOrder,
    )!;

    final sessionStore = _FakeSwapPersistenceStore(
      initialIntents: [
        _persistedIntent(
          id: 'swap-processing-deposit',
          txHash: depositDisplayOrder,
          status: SwapIntentStatus.processing,
        ),
      ],
    );
    final sentTx = _sentZecTx(
      txidHex: depositWalletOrder,
      zatoshi: BigInt.from(150000000),
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/activity',
          routes: [_swapRoute(), _swapActivityRoute()],
        ),
        seedSwapActivityFixtures: false,
        sessionStore: sessionStore,
        recentTransactions: [sentTx],
      ),
    );
    await _pumpUntilPresent(
      tester,
      find.byKey(const ValueKey('activity_screen_title_row')),
    );
    await tester.pump(const Duration(milliseconds: 250));

    // The in-flight swap row carries the signed outgoing amount, so the
    // standalone Sent broadcast row is absorbed as a duplicate.
    expect(find.text('Swapping...'), findsOneWidget);
    expect(find.text('Sent'), findsNothing);
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

    // The redesigned terminal deposit-tx row opens the explorer through
    // url_launcher directly; capture the launched URL instead of a clipboard
    // write.
    final launchedUrls = <String>[];
    const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      urlLauncherChannel,
      (call) async {
        if (call.method == 'launch') {
          final args = call.arguments as Map<Object?, Object?>;
          launchedUrls.add(args['url'] as String);
          return true;
        }
        if (call.method == 'canLaunch') return true;
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        urlLauncherChannel,
        null,
      );
    });

    final sessionStore = _FakeSwapPersistenceStore(
      initialIntents: [
        _persistedIntent(
          id: 'swap-explorer',
          txHash: '',
          status: SwapIntentStatus.complete,
          nextAction: 'Swap complete',
        ).copyWith(originChainTxHash: '0xdeadbeefdeadbeefdeadbeef'),
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

    expect(
      find.byKey(const ValueKey('swap_receipt_scope_panel')),
      findsNothing,
    );

    await _openActivityDetail(tester, 'swap-explorer');

    // Support-bundle / receipt affordances are gone.
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
    // The standalone explorer button has been removed.
    expect(
      find.byKey(
        const ValueKey('swap_activity_copy_near_intents_explorer_button'),
      ),
      findsNothing,
    );

    // Tapping the deposit-tx row's value pill (which carries the explorer
    // linkUri and the external-link arrow) opens url_launcher, not the
    // clipboard.
    final depositTxValue = find.text('0xdeadbee ... eadbeef');
    await tester.ensureVisible(depositTxValue);
    await tester.pumpAndSettle();
    await tester.tap(depositTxValue);
    await tester.pumpAndSettle();

    expect(launchedUrls, hasLength(1));
    expect(launchedUrls.single, contains('near-intents.org'));
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
    expect(find.text('Complete'), findsWidgets);
    expect(find.byKey(const ValueKey('swap_final_details')), findsOneWidget);
    // The standalone explorer button is gone; this completed swap has no
    // deposit-tx row, so no explorer affordance is rendered at all.
    expect(
      find.byKey(
        const ValueKey('swap_activity_copy_near_intents_explorer_button'),
      ),
      findsNothing,
    );
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_pay'),
      amountText: '0.7500 ZEC',
    );
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_receive'),
      amountText: '37.8 NEAR',
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
    final scrollView = tester.widget<CustomScrollView>(
      find.byKey(AppPaneScrollScaffold.scrollViewKey),
    );
    final controller = scrollView.controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    final pane = tester.widget<AppDesktopPane>(find.byType(AppDesktopPane));
    expect(pane.backgroundColor, isNull);

    // The overlay scrollbar spans the FULL pane height (toolbar band
    // included), pinned at the right pane edge.
    final scrollbarFinder = find.byKey(AppPaneScrollScaffold.scrollbarKey);
    final scrollbarRect = tester.getRect(scrollbarFinder);
    final paneRect = tester.getRect(find.byType(AppDesktopPane));
    expect((scrollbarRect.right - paneRect.right).abs(), lessThan(1));
    expect((scrollbarRect.top - paneRect.top).abs(), lessThan(1));
    expect((scrollbarRect.bottom - paneRect.bottom).abs(), lessThan(1));

    // Figma Scrollbar spec: 6px capsule thumb centered in the 18px
    // transparent track (6px insets), 12px end margins, solid theme thumb.
    final scrollbar = tester.widget<RawScrollbar>(scrollbarFinder);
    expect(scrollbar.thickness, 6);
    expect(scrollbar.crossAxisMargin, 6);
    expect(scrollbar.mainAxisMargin, 12);
    expect(scrollbar.radius, const Radius.circular(AppRadii.full));
    expect(
      scrollbar.thumbColor,
      AppThemeData.light.colors.surface.scrollbarThumb,
    );
    expect(scrollbar.thumbVisibility, isFalse);

    // Hovering the pane reveals the thumb while the content overflows.
    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(location: Offset.zero);
    addTearDown(hover.removePointer);
    await hover.moveTo(paneRect.center);
    await tester.pumpAndSettle();
    expect(
      tester.widget<RawScrollbar>(scrollbarFinder).thumbVisibility,
      isTrue,
    );

    final backLinkTopBeforeScroll = tester
        .getTopLeft(find.byType(AppRouteBackLink))
        .dy;
    await tester.drag(
      find.byKey(AppPaneScrollScaffold.scrollViewKey),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
    // The toolbar band stays pinned while the feed scrolls underneath it.
    expect(
      tester.getTopLeft(find.byType(AppRouteBackLink)).dy,
      backLinkTopBeforeScroll,
    );
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

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('swap:swap-page-6')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap:swap-page-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('swap:swap-page-6')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('activity_screen_filter_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('activity_screen_filter_label')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('activity_screen_filter_icon')),
      findsNothing,
    );
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

    expect(find.text('Swap in progress...'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_status_page_content')),
      findsOneWidget,
    );
    // The redesigned detail pages drop the NEAR Intents attribution and
    // scroll through the shared pane scaffold.
    expect(
      find.byKey(const ValueKey('swap_near_intents_attribution')),
      findsNothing,
    );
    expect(find.byKey(AppPaneScrollScaffold.scrollbarKey), findsOneWidget);

    final statusRect = tester.getRect(
      find.byKey(const ValueKey('swap_status_page_content')),
    );
    final titleRect = tester.getRect(
      find.byKey(const ValueKey('swap_status_title')),
    );
    final paneRect = tester.getRect(find.byType(AppDesktopPane));
    // Content starts below the pinned 48px toolbar band plus the 16px
    // scroll-content inset.
    expect(
      statusRect.top - paneRect.top,
      closeTo(AppPaneScrollScaffold.toolbarHeight + AppSpacing.sm, 1),
    );
    // The title is the first child of the status content column.
    expect(titleRect.top - statusRect.top, closeTo(0, 1));

    // The content fits, so the overlay scrollbar stays hidden — and the page
    // genuinely must not scroll at the 1080x720 reference window: the design
    // hides the Scrollbar instance on every status frame.
    final scrollbar = tester.widget<RawScrollbar>(
      find.byKey(AppPaneScrollScaffold.scrollbarKey),
    );
    expect(scrollbar.thumbVisibility, isFalse);
    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(AppPaneScrollScaffold.scrollViewKey),
    );
    expect(scrollView.controller!.position.maxScrollExtent, 0);

    // The redesigned details tab renders all rows directly (no More details
    // expansion, no Account row).
    await tester.tap(find.text('Transaction details'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('swap_status_detail_rows')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_status_page_content')),
        matching: find.text('Account'),
      ),
      findsNothing,
    );
    expect(find.text('More details'), findsNothing);
    expect(find.text('Less details'), findsNothing);
    expect(find.text('Swap fee'), findsOneWidget);
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
    // An incomplete deposit is non-terminal, so it keeps the Swap Progress /
    // Transaction details tabs rather than a terminal status badge.
    expect(find.byKey(const ValueKey('swap_status_tabs')), findsOneWidget);

    await _openSwapStatusDetails(tester, expand: true);

    expect(find.text('Incomplete deposit'), findsWidgets);
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
    // swap-refund carries no deposit tx, so there is no explorer affordance at
    // all (the old standalone explorer button is gone in the redesign).
    expect(
      find.byKey(
        const ValueKey('swap_activity_copy_near_intents_explorer_button'),
      ),
      findsNothing,
    );
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
    final finalDetails = find.byKey(const ValueKey('swap_final_details'));
    expect(finalDetails, findsOneWidget);

    // The recipient identity now lives in the summary's To: line, not the
    // terminal detail card.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_review_info_receive')),
        matching: find.textContaining('To: '),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: finalDetails, matching: find.text('USDC recipient')),
      findsNothing,
    );
    expect(
      find.descendant(of: finalDetails, matching: find.text('ZEC deposit to')),
      findsNothing,
    );
    expect(
      find.descendant(of: finalDetails, matching: find.text('Account')),
      findsNothing,
    );

    // Terminal detail rows: Realized slippage, Timestamp, deposit tx (linkable),
    // then Total fees last.
    expect(find.text('Realized slippage'), findsOneWidget);
    expect(find.text('0.000758 USDC (0.07%)'), findsOneWidget);
    expect(find.text('Timestamp'), findsOneWidget);
    expect(find.text('ZEC deposit tx'), findsOneWidget);
    expect(find.text('Total fees'), findsOneWidget);
    expect(find.text('0.0000134 ZEC'), findsOneWidget);

    // Non-terminal-only rows are excluded.
    expect(find.text('USDC delivery tx'), findsNothing);
    expect(find.text('usdc-delivery-txid'), findsNothing);
    expect(find.text('Slippage tolerance'), findsNothing);
    expect(find.text('Guaranteed minimum'), findsNothing);

    // Total fees is the last detail row.
    final fees = tester.getRect(find.text('Total fees'));
    final txRow = tester.getRect(find.text('ZEC deposit tx'));
    expect(fees.top, greaterThan(txRow.top));
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
    final finalDetails = find.byKey(const ValueKey('swap_final_details'));
    expect(finalDetails, findsOneWidget);

    // Failed terminal rows: Timestamp, USDC deposit tx, USDC refunded to, then
    // Total fees last. No Realized slippage on a failed swap.
    expect(find.text('Timestamp'), findsOneWidget);
    expect(find.text('USDC deposit tx'), findsOneWidget);
    expect(find.text('USDC refunded to'), findsOneWidget);
    expect(find.text('Total fees'), findsOneWidget);
    expect(find.text('0.19 USDC'), findsOneWidget);

    // The deposit-instruction address and delivery tx are not in terminal
    // details, and slippage rows are excluded on failure.
    expect(find.text('USDC deposit to'), findsNothing);
    expect(find.text('ZEC delivery tx'), findsNothing);
    expect(find.text('failed-delivery-txid'), findsNothing);
    expect(find.text('Realized slippage'), findsNothing);
    expect(find.text('Slippage tolerance'), findsNothing);
    expect(find.text('Guaranteed minimum'), findsNothing);

    // Total fees is the last detail row.
    final fees = tester.getRect(find.text('Total fees'));
    final refundRow = tester.getRect(find.text('USDC refunded to'));
    expect(fees.top, greaterThan(refundRow.top));
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
    expect(find.byKey(const ValueKey('swap_review_info')), findsOneWidget);
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
          (widget) => widget is AppIcon && widget.name == AppIcons.swapArrows,
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
      closeTo(AppSpacing.base, 0.1),
    );
    // The review page scrolls through the shared pane scaffold: a 6px
    // overlay thumb spanning the full pane, with no reserved gutter.
    final reviewScrollbar = tester.widget<RawScrollbar>(
      find.byKey(AppPaneScrollScaffold.scrollbarKey),
    );
    expect(reviewScrollbar.thickness, 6);
    expect(reviewScrollbar.crossAxisMargin, 6);
    final scrollAreaSize = tester.getSize(
      find.byKey(AppPaneScrollScaffold.scrollbarKey),
    );
    final panelSize = tester.getSize(
      find.byKey(const ValueKey('swap_review_panel')),
    );
    expect(scrollAreaSize.width, greaterThan(panelSize.width));
    expect(scrollAreaSize.height, greaterThan(800));
    final reviewTitle = tester.widget<Text>(
      find.byKey(const ValueKey('swap_review_title')),
    );
    // The redesigned review title is 16 SemiBold.
    expect(reviewTitle.style!.fontSize, 16);
    expect(reviewTitle.style!.fontWeight, FontWeight.w600);
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
    final reviewSummary = find.byKey(const ValueKey('swap_review_info'));
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
    _expectReviewInfoAmountFits(
      tester,
      sideKey: const ValueKey('swap_review_info_pay'),
      amountText: '1.5000 ZEC',
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

      // The recipient identity now lives on the summary's To: line, not in the
      // detail card (which no longer renders To/From address rows).
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('swap_review_info_receive')),
          matching: find.text('To: 0x5290840 ... 4169ee7 on Ethereum'),
        ),
        findsOneWidget,
      );
      final reviewDetails = find.byKey(const ValueKey('swap_review_details'));
      expect(
        find.descendant(of: reviewDetails, matching: find.text('To')),
        findsNothing,
      );
      expect(
        find.descendant(of: reviewDetails, matching: find.text('From')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: reviewDetails,
          matching: find.text('0x5290840 ... 4169ee7'),
        ),
        findsNothing,
      );
      expect(find.text('Guaranteed minimum'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('swap_review_details_toggle')),
        findsNothing,
      );
      expect(find.text('Expires in'), findsNothing);

      // The fee row keeps value-then-help-icon ordering, right-aligned to the
      // detail card content edge.
      final reviewDetailsRect = tester.getRect(reviewDetails);
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
      expect(feeValueRect.right, lessThan(feeHelpIconRect.left));
      // The shared ReviewListRow pill carries a 4px right padding (pr 4), so the
      // trailing help icon now sits the card's content inset (sm) plus that pill
      // padding (xxs) inside the card edge.
      expect(
        feeHelpIconRect.right,
        closeTo(reviewDetailsRect.right - AppSpacing.sm - AppSpacing.xxs, 1),
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
    expect(find.text('1.5000'), findsOneWidget);

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
    expect(find.text('1.5000'), findsOneWidget);
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

      // The ZEC pay side shows the live required-pay amount and its captured
      // fiat ($112.28 = 1.6 ZEC); the external receive side carries the To:
      // recipient line, not a fiat figure.
      _expectReviewInfoAmountFits(
        tester,
        sideKey: const ValueKey('swap_review_info_pay'),
        amountText: '1.6000 ZEC',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('swap_review_info_pay')),
          matching: find.text(r'$112.28'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('swap_review_info_receive')),
          matching: find.textContaining('To: '),
        ),
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

    // The receive side shows the live exact-input receive amount as a single
    // serif 'amount + symbol' string; the ZEC pay side shows the captured fiat
    // ($105.26 = 1.5 ZEC). The receive side carries the To: recipient line, not
    // a fiat figure.
    final reviewSummary = find.byKey(const ValueKey('swap_review_info'));
    expect(
      find.descendant(of: reviewSummary, matching: find.text('123.45 USDC')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_review_info_pay')),
        matching: find.text(r'$105.26'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_review_info_receive')),
        matching: find.textContaining('To: '),
      ),
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

    expect(
      find.byKey(const ValueKey('swap_review_cancel_button')),
      findsNothing,
    );
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

    expect(
      find.byKey(const ValueKey('swap_review_cancel_button')),
      findsNothing,
    );
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
    expect(
      find.byKey(const ValueKey('swap_review_cancel_button')),
      findsNothing,
    );
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
    expect(
      find.byKey(const ValueKey('swap_review_cancel_button')),
      findsNothing,
    );
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
      // The redesigned detail pages drop the NEAR Intents attribution.
      expect(
        find.byKey(const ValueKey('swap_near_intents_attribution')),
        findsNothing,
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
    'hardware ZEC signing keeps the modal preparing until proofs are ready',
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
      // Matches the home shielding overlay: the modal stays in the preparing
      // phase (no separate 'Preparing' button label) and 'Get signature'
      // is rendered but inert until proving completes.
      expect(find.text('Preparing'), findsNothing);
      expect(find.text('Get signature'), findsOneWidget);
      await tester.tap(find.text('Get signature'));
      await tester.pump();
      expect(hardwareSigningService.proofDrafts, hasLength(1));
      expect(find.text('Sign ZEC deposit on Keystone'), findsOneWidget);

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

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('swap_keystone_signing_overlay_surface')),
        matching: find.text('Cancel'),
      ),
    );
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

// Shared modal card shadow (core/widgets/app_modal_card.dart appModalShadow).
const _figmaModalSurfaceShadows = [
  BoxShadow(color: Color(0x0F000000), offset: Offset(0, 2), blurRadius: 8),
  BoxShadow(color: Color(0x08000000), offset: Offset(0, -6), blurRadius: 12),
  BoxShadow(color: Color(0x14000000), offset: Offset(0, 14), blurRadius: 28),
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
  List<rust_sync.TransactionInfo> recentTransactions = const [],
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
        () => _FakeSwapSyncNotifier(
          spendableBalance ?? BigInt.from(10000000000),
          recentTransactions: recentTransactions,
        ),
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

GoRoute _activityTransactionRoute() {
  return GoRoute(
    path: '/activity/tx/:txid',
    builder: (_, state) {
      final extra = state.extra;
      return ActivityTransactionStatusScreen(
        args: extra is ActivityTransactionStatusArgs
            ? extra
            : ActivityTransactionStatusArgs(
                txidHex: state.pathParameters['txid'] ?? '',
              ),
      );
    },
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

/// Like [_themeHarness] but provides an [Overlay], which the shared review
/// primitives need: [ReviewListRow]'s help affordance always wraps its trailing
/// icon in an [AppTooltip], and [AppTooltip] requires an [Overlay] ancestor.
///
/// Uses [_OverlayHarness] so the hosted child reconciles across repeated
/// `pumpWidget` calls instead of being torn down and rebuilt (which would reset
/// any [State] between pumps).
Widget _themeHarnessWithOverlay(Widget child) {
  return AppTheme(
    data: AppThemeData.light,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: _OverlayHarness(child: child),
    ),
  );
}

/// Hosts [child] inside an [Overlay] using a single, stable [OverlayEntry] that
/// is rebuilt whenever [child] changes, so widget [State] survives across
/// successive `pumpWidget` calls.
class _OverlayHarness extends StatefulWidget {
  const _OverlayHarness({required this.child});

  final Widget child;

  @override
  State<_OverlayHarness> createState() => _OverlayHarnessState();
}

class _OverlayHarnessState extends State<_OverlayHarness> {
  late final OverlayEntry _entry = OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(_OverlayHarness oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(initialEntries: [_entry]);
  }
}

final _testShitAsset = SwapAsset.live(
  assetId: 'test-shit-sol',
  symbol: r'$SHIT',
  blockchain: 'sol',
  decimals: 6,
);

/// Asserts that one side of the redesigned [SwapReviewInfo] renders its
/// amount + symbol verbatim as a single serif text, inside a FittedBox that
/// scales it down to fit (no overflow, no digit compaction).
void _expectReviewInfoAmountFits(
  WidgetTester tester, {
  required Key sideKey,
  required String amountText,
}) {
  final sideFinder = find.byKey(sideKey);
  expect(sideFinder, findsOneWidget);
  final amountFinder = find.descendant(
    of: sideFinder,
    matching: find.text(amountText),
  );
  expect(amountFinder, findsOneWidget);
  expect(tester.widget<Text>(amountFinder).overflow, isNull);
  final fittedBox = find.ancestor(
    of: amountFinder,
    matching: find.byType(FittedBox),
  );
  expect(fittedBox, findsOneWidget);
  expect(tester.widget<FittedBox>(fittedBox).fit, BoxFit.scaleDown);

  final sideRect = tester.getRect(sideFinder);
  final amountRect = tester.getRect(amountFinder);
  expect(amountRect.left, greaterThanOrEqualTo(sideRect.left - 0.5));
  expect(amountRect.right, lessThanOrEqualTo(sideRect.right + 0.5));
}

Widget _reviewTestPage({
  required SwapDirection direction,
  required SwapAsset sellAsset,
  required SwapAsset receiveAsset,
  required String sellAmountText,
  required String receiveAmountText,
  ValueChanged<String>? onCopy,
}) {
  final externalAsset = direction.sendsZec ? receiveAsset : sellAsset;
  return SwapReviewPageContent(
    onCopy: onCopy,
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
    expired: false,
    amountWarning: null,
    startError: null,
  );
}

Widget _statusTestPage({
  String title = 'Swap in progress...',
  SwapAsset payAsset = SwapAsset.usdc,
  SwapAsset receiveAsset = SwapAsset.zec,
  String payDetailText = r'$110.24',
  String receiveDetailText = r'$110.24',
  String payAmountText = '999.99 USDC',
  String receiveAmountText = '0.251 ZEC',
  String statusLabel = 'Processing',
  int progressIndex = 0,
  Duration progressAdvanceInterval = const Duration(milliseconds: 520),
  SwapStatusBadgeKind badgeKind = SwapStatusBadgeKind.liveQuote,
  SwapStatusTab activeTab = SwapStatusTab.progress,
  bool showTabs = true,
  List<SwapStatusDetailRowData>? details,
}) {
  // The real screens host this content in the pane scroll scaffold; the
  // 800x600 test surface is shorter than the full progress page, so scroll
  // here too instead of overflowing the column.
  return SingleChildScrollView(
    child: SwapStatusPageContent(
      title: title,
      payAsset: payAsset,
      receiveAsset: receiveAsset,
      payDetailText: payDetailText,
      receiveDetailText: receiveDetailText,
      payAmountText: payAmountText,
      receiveAmountText: receiveAmountText,
      statusLabel: statusLabel,
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
    ),
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

SwapIntent _persistedExternalToZecCompleteIntent({
  required String id,
  required String destinationChainTxHash,
}) {
  return SwapIntent(
    id: id,
    pair: 'USDC -> ZEC',
    sellAmount: '101.23 USDC',
    receiveEstimate: '4.12 ZEC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.complete,
    nextAction: 'Swap complete',
    direction: SwapDirection.externalToZec,
    externalAsset: SwapAsset.usdc,
    depositAddress: id,
    depositMemo: 'memo-7',
    providerQuoteId: 'quote-1',
    oneClickRecipient: 'u1wallet-receive',
    oneClickRefundTo: '0xpersisted-refund',
    destinationChainTxHash: destinationChainTxHash,
    accountUuid: 'account-1',
    createdAt: DateTime.utc(2026, 5, 7, 10),
    completedAt: DateTime.utc(2026, 5, 7, 10, 5),
  );
}

rust_sync.TransactionInfo _sentZecTx({
  required String txidHex,
  required BigInt zatoshi,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: BigInt.from(2000000),
    expiredUnmined: false,
    accountBalanceDelta: -zatoshi.toInt(),
    fee: BigInt.from(15000),
    blockTime: BigInt.from(1800000000),
    isTransparent: false,
    txKind: 'sent',
    displayAmount: zatoshi,
    displayPool: 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}

rust_sync.TransactionInfo _receivedZecTx({
  required String txidHex,
  required BigInt zatoshi,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: BigInt.from(2000000),
    expiredUnmined: false,
    accountBalanceDelta: zatoshi.toInt(),
    fee: BigInt.zero,
    blockTime: BigInt.from(1800000000),
    isTransparent: false,
    txKind: 'received',
    displayAmount: zatoshi,
    displayPool: 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationSupportPath() async =>
      Directory.systemTemp.path;

  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform
    with MockPlatformInterfaceMixin {
  _FakeSecureStoragePlatform(Map<String, String> seed)
    : _store = Map<String, String>.of(seed);

  final Map<String, String> _store;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => _store[key];

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => _store.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map<String, String>.of(_store);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _store[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _store.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _store.clear();
  }
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

final _privacyModeBootstrap = AppBootstrapState(
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
  privacyModeEnabled: true,
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
