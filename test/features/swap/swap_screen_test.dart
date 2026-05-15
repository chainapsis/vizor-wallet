import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/layout/app_main_sidebar.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_prototype_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_prototype_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_deposit_sender.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_max_amount_estimator.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_shielding_service.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_session_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_zec_staging_address_service.dart';
import 'package:zcash_wallet/src/features/swap/screens/swap_screen.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_amount_text.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_deposit_qr_panel.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_queue_panel.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/receive_address_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

void main() {
  test('compactSwapAmountText truncates visible decimals without ellipsis', () {
    expect(compactSwapAmountText('~0.123456789 BTC'), '~0.123456 BTC');
    expect(compactSwapAmountText('12345.678901 USDC'), '12345.678901 USDC');
    expect(compactSwapAmountText('2 ZEC'), '2 ZEC');
    expect(
      compactSwapAmountText('1.1234567 ZEC -> ~2.7654321 USDC'),
      '1.123456 ZEC -> ~2.765432 USDC',
    );
    expect(compactSwapAmountText('~0.9 BTC', maxFractionDigits: 0), '~0 BTC');
  });

  testWidgets('sidebar Swap item opens the swap prototype route', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => AppDesktopShell(
            sidebar: const AppMainSidebar(),
            pane: AppDesktopPane(
              child: Text(
                'home route',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppThemeData.light.colors.text.primary,
                ),
              ),
            ),
          ),
        ),
        GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
        GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
        GoRoute(
          path: '/receive',
          builder: (_, _) => const Text('receive route'),
        ),
        GoRoute(
          path: '/activity',
          builder: (_, _) => const Text('activity route'),
        ),
        GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
        GoRoute(path: '/about', builder: (_, _) => const Text('about route')),
      ],
    );

    await tester.pumpWidget(_routerHarness(router));

    await tester.tap(find.text('Swap'));
    await tester.pumpAndSettle();

    expect(find.text('Powered by NEAR Intents'), findsWidgets);
  });

  testWidgets('swap tab renders composer and privacy check', (tester) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Swap'), findsWidgets);
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
    expect(find.text('Powered by NEAR Intents'), findsWidgets);
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
    expect(addressFieldHeight, greaterThanOrEqualTo(42));
    expect(addressFieldHeight, lessThanOrEqualTo(56));
    expect(find.text('Recipient'), findsOneWidget);
    expect(find.text('Add Ethereum USDC recipient'), findsOneWidget);
    expect(find.text('Ethereum'), findsWidgets);
    expect(
      find.byKey(const ValueKey('swap_settlement_path_preview')),
      findsNothing,
    );
    expect(find.text('Settlement path'), findsNothing);
    expect(find.text('Enter a trade'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('swap_review_button'))).width,
      greaterThanOrEqualTo(540),
    );
    final ticketRect = tester.getRect(
      find.byKey(const ValueKey('swap_compact_ticket')),
    );
    final reviewButtonRect = tester.getRect(
      find.byKey(const ValueKey('swap_review_button')),
    );
    expect((ticketRect.center.dy - 491).abs(), lessThan(48));
    expect(ticketRect.height, lessThan(440));
    expect(
      reviewButtonRect.top,
      greaterThan(ticketRect.bottom + AppSpacing.xs),
    );
    expect(982 - reviewButtonRect.bottom, lessThanOrEqualTo(32));
    expect(
      find.byKey(const ValueKey('swap_activity_open_count')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('swap_ticket_tabs')), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_page_tab_requests')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_activity_open_count')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
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

  testWidgets('fresh swap screen starts without preview activity or requests', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        seedPrototypeFixtures: false,
        sessionStore: _FakeSwapSessionStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_compact_ticket')), findsOneWidget);
    expect(find.text('Current swap'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('swap_activity_empty_state')),
      findsOneWidget,
    );
    expect(find.text('No swap activity yet'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_queue_empty_state')),
      findsOneWidget,
    );
    expect(find.text('Recovery receipt'), findsNothing);

    await _openRequestsSurface(tester);

    expect(find.text('No request selected'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_request_empty_state')),
      findsOneWidget,
    );
    expect(find.text('No saved requests'), findsOneWidget);
  });

  testWidgets('swap activity ignores sessions from another account', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final sessionStore = _FakeSwapSessionStore(
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        seedPrototypeFixtures: false,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(sessionStore.loadedAccounts, ['account-1']);

    await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
    await tester.pumpAndSettle();

    expect(find.text('No swap activity yet'), findsOneWidget);
    expect(find.text('other-account-txid'), findsNothing);
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        seedPrototypeFixtures: false,
        sessionStore: _FakeSwapSessionStore(),
        spendableBalance: BigInt.from(123450000),
        maxAmountEstimator: maxEstimator,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Available 1.2345 ZEC'), findsOneWidget);
    expect(find.text('Available 12.48 ZEC'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_max_amount_button')));
    await tester.pumpAndSettle();

    expect(maxEstimator.requests, ['account-1']);
    expect(_fieldText(tester, 'swap_amount_field'), '1.2339');
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
            routes: [
              GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
            ],
          ),
          seedPrototypeFixtures: false,
          spendableBalance: BigInt.from(100000000),
          swapProvider: swapProvider,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('swap_destination_field')),
        '0xrecipient',
      );
      await tester.pumpAndSettle();

      expect(find.text('Exceeds available 1 ZEC'), findsOneWidget);
      expect(find.text('Insufficient ZEC'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();

      expect(swapProvider.requests, isEmpty);
      expect(find.text('Swap review'), findsNothing);
    },
  );

  testWidgets('swap composer restores only the last attempted pair', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    final sessionStore = _FakeSwapSessionStore(
      initialDraft: const SwapDraftSnapshot(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.near,
        slippageBps: 125,
      ),
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        seedPrototypeFixtures: false,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(sessionStore.loadDraftCount, 1);
    expect(_fieldText(tester, 'swap_amount_field'), isEmpty);
    expect(_fieldText(tester, 'swap_destination_field'), isEmpty);
    expect(find.text('NEAR refund'), findsWidgets);
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
    final sessionStore = _FakeSwapSessionStore(
      initialDraft: SwapDraftSnapshot(
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        seedPrototypeFixtures: false,
        sessionStore: sessionStore,
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(sessionStore.loadDraftCount, 1);
    expect(find.text('Add Base USDC recipient'), findsOneWidget);
    expect(find.text('Add Ethereum USDC recipient'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('swap_external_asset_selector')).first,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_asset_group_usdc')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_asset_network_badge_usdc')),
        matching: find.text('Ethereum'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('swap_asset_network_badge_nep141:base-usdc.example'),
        ),
        matching: find.text('Base'),
      ),
      findsOneWidget,
    );
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
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
    expect(find.text('Bitcoin'), findsWidgets);
    expect(find.text('Bitcoin BTC'), findsNothing);
    expect(find.byKey(const ValueKey('swap_asset_row_sol')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_asset_row_btc')));
    await tester.pumpAndSettle();

    expect(find.text('Powered by NEAR Intents'), findsWidgets);
    expect(find.text('You receive'), findsOneWidget);
    expect(find.text('Bitcoin'), findsWidgets);
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
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

    expect(find.text('No supported asset found'), findsOneWidget);
  });

  testWidgets('swap asset selector has a click cursor and closes outside', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
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
    final sessionStore = _FakeSwapSessionStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        seedPrototypeFixtures: false,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_settings_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_settings_popover')), findsOneWidget);
    expect(find.text('Slippage tolerance'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('swap_slippage_200bps')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_settings_popover')), findsNothing);
    expect(find.text('2%'), findsWidgets);
    expect(sessionStore.savedDraft?.slippageBps, 200);

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
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
    final sessionStore = _FakeSwapSessionStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        seedPrototypeFixtures: false,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_settings_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_slippage_custom_field')),
      '1.25',
    );
    await tester.tap(find.byKey(const ValueKey('swap_slippage_custom_apply')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_settings_popover')), findsNothing);
    expect(find.text('1.25%'), findsWidgets);
    expect(sessionStore.savedDraft?.slippageBps, 125);

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.requests.single.slippageBps, 125);
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        seedPrototypeFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '0.01',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
    );
    await tester.pumpAndSettle();

    expect(swapProvider.pricingRequests, 1);
    expect(find.text('~5.41'), findsOneWidget);
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        seedPrototypeFixtures: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
    );
    await tester.pumpAndSettle();

    expect(find.text('~100.00'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('swap_direction_externalToZec')),
    );
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'swap_amount_field'), '100.00');
    expect(find.text('~1.0000'), findsOneWidget);
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        seedPrototypeFixtures: false,
        priceRefreshInterval: const Duration(seconds: 1),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
    );
    await tester.pumpAndSettle();

    expect(find.text('~100.00'), findsOneWidget);
    expect(find.text('1 ZEC = 100.00 USDC'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(swapProvider.pricingRequests, greaterThanOrEqualTo(2));
    expect(swapProvider.sawForcedRefresh, isTrue);
    expect(find.text('~200.00'), findsOneWidget);
    expect(find.text('1 ZEC = 200.00 USDC'), findsOneWidget);
  });

  testWidgets('price refresh keeps the review modal open and warns on drift', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _PricingSwapProvider(const [100, 200]);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        seedPrototypeFixtures: false,
        priceRefreshInterval: const Duration(seconds: 1),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_review_modal')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_review_amount_warning')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(swapProvider.sawForcedRefresh, isTrue);
    expect(find.byKey(const ValueKey('swap_review_modal')), findsOneWidget);
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_queue_title')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_queue_row_swap-8f29')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_queue_asset_pair_swap-8f29')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_active_summary_panel')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_activity_detail_modal')),
      findsNothing,
    );
    expect(find.text('Shielding in wallet'), findsOneWidget);
    expect(find.text('You pay'), findsNothing);
    expect(find.text('Privacy check'), findsNothing);

    await _openActivityDetail(tester, 'swap-8f29');

    expect(
      find.byKey(const ValueKey('swap_activity_detail_modal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_activity_detail_title')),
      findsOneWidget,
    );
    expect(find.text('Swap progress'), findsOneWidget);
    expect(find.text('Activity detail'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_activity_detail_asset_pair')),
      findsOneWidget,
    );
    final closeSize = tester.getSize(
      find.byKey(const ValueKey('swap_activity_detail_close_button')),
    );
    expect(closeSize.width, greaterThanOrEqualTo(132));
    expect(closeSize.height, greaterThanOrEqualTo(44));
    expect(
      find.byKey(const ValueKey('swap_active_summary_panel')),
      findsOneWidget,
    );
    expect(find.text('Current swap'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_activity_checked_label')),
      findsOneWidget,
    );
    expect(find.text('2.4000 ZEC'), findsOneWidget);
    expect(find.text('~168.42 USDC'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_activity_status_plan')),
      findsOneWidget,
    );
    expect(find.text('Making ZEC spendable'), findsOneWidget);
    expect(
      find.text('Shielding received ZEC into your spendable balance.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_activity_route_tracker')),
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
      const EdgeInsets.only(right: AppSpacing.s),
    );
    expect(
      find.byKey(const ValueKey('swap_activity_active_step_halo')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_activity_route_segment_blink_3')),
      findsOneWidget,
    );
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Send ZEC'), findsWidgets);
    expect(find.text('Confirm'), findsWidgets);
    expect(find.text('Swap'), findsWidgets);
    expect(find.text('Deliver'), findsWidgets);
    expect(find.byKey(const ValueKey('swap_queue_title')), findsOneWidget);
    expect(find.text('Technical details'), findsNothing);
    expect(find.text('Status timeline'), findsNothing);
    expect(find.text('Receipt'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_activity_copy_receipt_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_status_refresh_button')),
      findsOneWidget,
    );
    expect(find.text('Copy redacted receipt'), findsNothing);

    await tester.tapAt(const Offset(16, 16));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('swap_activity_detail_modal')),
      findsNothing,
    );
  });

  testWidgets('activity tab refreshes status from the activity surface', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_queue_title')), findsOneWidget);
    expect(find.text('Privacy check'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_queue_refresh_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.statusRequests, hasLength(1));
    expect(find.text('Swapping through provider'), findsWidgets);
  });

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
        receiveEstimateText: '~70.170000 USDC',
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
    final sessionStore = _FakeSwapSessionStore(
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        seedPrototypeFixtures: false,
        swapProvider: swapProvider,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
    await tester.pumpAndSettle();
    await _openActivityDetail(tester, 'jump-deposit');

    expect(
      find.byKey(const ValueKey('swap_activity_route_step_0_active')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('swap_status_refresh_button')));
    await tester.pump();
    expect(swapProvider.statusRequests, hasLength(1));

    swapProvider.completeStatus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      find.byKey(const ValueKey('swap_activity_route_step_1_active')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_activity_route_step_2_active')),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 430));
    expect(
      find.byKey(const ValueKey('swap_activity_route_step_2_active')),
      findsOneWidget,
    );
  });

  testWidgets('activity can manually remove a pending saved swap', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final releasedAddresses = <String>[];
    final sessionStore = _FakeSwapSessionStore(
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        seedPrototypeFixtures: false,
        sessionStore: sessionStore,
        releaseExchangeTransparentAddress:
            ({required accountUuid, required address, required dbPath}) async {
              releasedAddresses.add(address);
              return true;
            },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('swap_queue_row_oversized-pending')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_queue_row_keep-pending')),
      findsOneWidget,
    );

    await _openActivityDetail(tester, 'oversized-pending');

    await tester.tap(find.byKey(const ValueKey('swap_activity_remove_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('swap_remove_intent_modal')),
      findsOneWidget,
    );
    expect(find.text('Remove from activity?'), findsOneWidget);
    expect(
      find.textContaining('does not cancel the provider quote'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('swap_remove_intent_confirm_button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('swap_queue_row_oversized-pending')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_queue_row_keep-pending')),
      findsOneWidget,
    );
    expect(sessionStore.savedIntents.map((intent) => intent.id), [
      'keep-pending',
    ]);
    expect(releasedAddresses, ['t1oversized-staging']);
  });

  testWidgets('activity recovery bundle copies durable swap fields', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final clipboardWrites = <String>[];
    final clipboardWriteCompleted = Completer<void>();
    Future<Object?> handlePlatformCall(MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        clipboardWrites.add(args['text']! as String);
        await clipboardWriteCompleted.future;
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('swap_receipt_scope_panel')),
      findsNothing,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('swap_queue_row_swap-refund')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_queue_row_swap-refund')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('swap_support_details_section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_receipt_scope_panel')),
      findsNothing,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('swap_support_details_toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_support_details_toggle')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('swap_receipt_scope_panel')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_support_safe_summary_panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_support_bundle_panel')),
      findsOneWidget,
    );
    expect(find.text('Safe support summary'), findsOneWidget);
    expect(find.text('Reveal full bundle'), findsNothing);
    expect(find.text('Copy details'), findsOneWidget);
    expect(find.text('t1refund-zec-deposit'), findsWidgets);

    expect(find.text('Swap id'), findsNothing);
    final supportPanel = find.byKey(
      const ValueKey('swap_support_bundle_panel'),
    );
    expect(
      find.descendant(of: supportPanel, matching: find.text('Next action')),
      findsNothing,
    );
    expect(
      find.descendant(of: supportPanel, matching: find.text('Refund address')),
      findsNothing,
    );
    expect(
      find.descendant(of: supportPanel, matching: find.text('Refund to')),
      findsNothing,
    );
    expect(
      find.descendant(of: supportPanel, matching: find.text('Support bundle')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_copy_near_intents_explorer_button')),
      findsNothing,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('swap_copy_support_details_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('swap_copy_support_details_button')),
    );
    await tester.pump();

    expect(clipboardWrites, hasLength(1));
    expect(find.text('Support Details Copied'), findsNothing);

    clipboardWriteCompleted.complete();
    await tester.pumpAndSettle();

    expect(clipboardWrites.single, contains('Support details'));
    expect(clipboardWrites.single, isNot(contains('Swap id:')));
    expect(clipboardWrites.single, isNot(contains('Next action:')));
    expect(clipboardWrites.single, isNot(contains('Refund address:')));
    expect(clipboardWrites.single, isNot(contains('Refund to:')));
    expect(clipboardWrites.single, contains('Deposit address: t1refund'));
    expect(find.text('Support Details Copied'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_toast_overlay_host')),
        matching: find.text('Support Details Copied'),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('swap_copy_detail_deposit_address')).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('swap_copy_detail_deposit_address')).first,
    );
    await tester.pumpAndSettle();

    expect(clipboardWrites, hasLength(2));
    expect(clipboardWrites.last, 't1refund-zec-deposit');
    expect(find.text('Address Copied'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_toast_overlay_host')),
        matching: find.text('Address Copied'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('desktop shortcuts switch swap tabs and refresh status', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await _sendShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.digit2,
    );

    expect(find.byKey(const ValueKey('swap_queue_title')), findsOneWidget);
    expect(find.text('Privacy check'), findsNothing);

    await _sendShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyR,
    );

    expect(swapProvider.statusRequests, hasLength(1));
    expect(find.text('Swapping through provider'), findsWidgets);

    await _sendShortcut(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.digit3,
    );

    expect(find.text('Request inbox'), findsOneWidget);

    await _sendShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.digit1,
    );

    expect(find.text('You pay'), findsOneWidget);
  });

  testWidgets('command palette runs desktop swap actions', (tester) async {
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _sendShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyK,
    );

    expect(find.byKey(const ValueKey('swap_command_palette')), findsOneWidget);
    expect(find.text('Command palette'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('swap_command_palette_query')),
      'activity',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('swap_command_open_activity')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('swap_command_open_activity')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_command_palette')), findsNothing);
    expect(find.byKey(const ValueKey('swap_queue_title')), findsOneWidget);

    await _sendShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyK,
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_command_palette_query')),
      'receipt',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_command_copy_receipt')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_command_palette')), findsNothing);
    expect(clipboardWrites, hasLength(1));
    expect(
      clipboardWrites.single,
      contains('Receipt scope: redacted status evidence'),
    );
    expect(clipboardWrites.single, isNot(contains('Swap id:')));
    expect(clipboardWrites.single, isNot(contains('Shared fields:')));
    expect(clipboardWrites.single, contains('Pair:'));
    expect(find.text('Receipt Copied'), findsOneWidget);
  });

  testWidgets('command palette imports clipboard payment requests', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return {
            'text': 'zcash:u1clipboarddestination?amount=0.75&message=Desk',
          };
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _sendShortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyK,
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_command_palette_query')),
      'clipboard',
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('swap_command_import_clipboard_request')),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_command_palette')), findsNothing);
    expect(find.text('Request inbox'), findsOneWidget);
    expect(find.text('Zcash payment request'), findsWidgets);
    expect(find.text('Review payment of 0.75 ZEC'), findsWidgets);
  });

  testWidgets('requests tab renders inbox and isolates unsupported connectors', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openRequestsSurface(tester);

    expect(
      find.byKey(const ValueKey('swap_request_inbox_panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_request_list_panel')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('swap_page_tab_requests')), findsNothing);
    expect(find.text('Request inbox'), findsOneWidget);
    expect(find.text('Pasted request'), findsWidgets);
    expect(find.text('Stage 0.2500 ZEC for USDC delivery'), findsWidgets);
    expect(find.text('Receive ZEC from USDC'), findsWidgets);
    expect(find.text('Send ZEC request'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('swap_request_row_request-walletconnect')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pairing request'), findsWidgets);
    expect(find.text('Unsupported'), findsWidgets);
    expect(find.text('WalletConnect (blocked)'), findsOneWidget);
    expect(find.text('Connector disabled'), findsOneWidget);
    expect(
      find.text(
        'Swap does not open long-lived dapp sessions. Import explicit payment or swap requests instead.',
      ),
      findsOneWidget,
    );
    expect(find.text('Account reveal'), findsOneWidget);
    expect(find.text('blocked'), findsWidgets);
  });

  testWidgets('request inbox stages swap requests into the composer', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openRequestsSurface(tester);
    await tester.tap(find.byKey(const ValueKey('swap_request_primary_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('swap_request_inbox_panel')),
      findsNothing,
    );
    expect(find.text('ZEC -> USDC'), findsNothing);
    expect(_fieldText(tester, 'swap_amount_field'), '0.2500');
    expect(
      _fieldText(tester, 'swap_destination_field'),
      '0xrequest-usdc-recipient',
    );
    expect(find.text('Recipient'), findsOneWidget);

    await _openRequestsSurface(tester);

    expect(find.text('Accepted'), findsWidgets);
  });

  testWidgets('request inbox stages external asset requests into ZEC receive', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openRequestsSurface(tester);
    await tester.tap(
      find.byKey(const ValueKey('swap_request_row_request-receive-zec-usdc')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Receive ZEC request'), findsOneWidget);
    expect(
      find.text(
        'Stage the quote, then send USDC to a one-time source-chain address. ZEC lands on the wallet t-address, then prompts shielding.',
      ),
      findsOneWidget,
    );
    expect(find.text('Pay 140.35 USDC'), findsOneWidget);
    expect(find.text('Receive ZEC to wallet t-address'), findsOneWidget);
    expect(find.text('Refund 0xrequest-usdc-refund'), findsOneWidget);
    expect(find.text('Stage receive'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('swap_request_primary_button')));
    await tester.pumpAndSettle();

    expect(find.text('USDC -> ZEC'), findsNothing);
    expect(_fieldText(tester, 'swap_amount_field'), '140.35');
    expect(
      _fieldText(tester, 'swap_destination_field'),
      '0xrequest-usdc-refund',
    );
    expect(find.text('USDC refund'), findsWidgets);
  });

  testWidgets('request inbox imports ZIP-321 payment URIs', (tester) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openRequestsSurface(tester);
    await tester.enterText(
      find.byKey(const ValueKey('swap_request_import_field')),
      'zcash:u1zip321destination?amount=1.25&message=Invoice%2042',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_request_import_button')));
    await tester.pumpAndSettle();

    expect(find.text('Zcash payment request'), findsWidgets);
    expect(find.text('Review payment of 1.25 ZEC'), findsWidgets);
    expect(find.text('u1zip321destination'), findsOneWidget);
    expect(find.text('Invoice 42'), findsOneWidget);
    expect(find.text('Approval required'), findsOneWidget);
    expect(_fieldText(tester, 'swap_request_import_field'), isEmpty);
  });

  testWidgets('request inbox pastes ZIP-321 payment URIs from clipboard', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return {
            'text': 'zcash:u1clipboarddestination?amount=0.75&message=Desk',
          };
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openRequestsSurface(tester);
    await tester.tap(find.byKey(const ValueKey('swap_request_paste_button')));
    await tester.pumpAndSettle();

    expect(find.text('Zcash payment request'), findsWidgets);
    expect(find.text('Review payment of 0.75 ZEC'), findsWidgets);
    expect(find.text('Desk'), findsOneWidget);
    expect(_fieldText(tester, 'swap_request_import_field'), isEmpty);
  });

  testWidgets('request inbox opens parsed ZIP-321 payments in send handoff', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
            GoRoute(
              path: '/send',
              builder: (_, state) {
                final extra = state.extra;
                if (extra is! SendPrefillArgs) {
                  return const Text('send route');
                }
                return Text(
                  'send prefill ${extra.address} ${extra.amountText} ${extra.message}',
                );
              },
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openRequestsSurface(tester);
    await tester.enterText(
      find.byKey(const ValueKey('swap_request_import_field')),
      'zcash:u1zip321destination?amount=1.25&message=Invoice%2042',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_request_import_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_request_primary_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('send prefill u1zip321destination 1.25 Invoice 42'),
      findsOneWidget,
    );
  });

  testWidgets('request inbox rejects invalid ZIP-321 payment URIs', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openRequestsSurface(tester);
    await tester.enterText(
      find.byKey(const ValueKey('swap_request_import_field')),
      'zcash:u1zip321destination?amount=0.123456789',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_request_import_button')));
    await tester.pumpAndSettle();

    expect(find.text('Invalid ZIP-321 ZEC amount.'), findsOneWidget);
    expect(find.text('0.123456789 ZEC'), findsNothing);
  });

  testWidgets('activity queue groups swaps and selection updates detail', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('Shielding in wallet'), findsOneWidget);

    await _openActivityDetail(tester, 'swap-2a11');

    expect(find.text('Status timeline'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_activity_details_toggle')),
      findsNothing,
    );
    expect(find.text('Technical details'), findsNothing);
    expect(find.text('NEAR delivered'), findsWidgets);
    expect(find.text('The swap is complete.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_activity_route_step_3_done')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('swap_activity_copy_near_intents_explorer_button'),
      ),
      findsOneWidget,
    );
    expect(find.text('0.7500 ZEC'), findsOneWidget);
    expect(find.text('~37.8 NEAR'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_support_details_section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_copy_support_details_button')),
      findsNothing,
    );
    await _revealSupportBundle(tester);
    expect(find.text('Copy details'), findsWidgets);
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

  testWidgets('swap queue groups attention terminal swaps', (tester) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _themeHarness(
        SwapQueuePanel(
          intents: [
            _persistedIntent(
              id: 'failed-swap',
              txHash: 'failed-tx',
              status: SwapIntentStatus.failed,
              nextAction: 'Provider could not complete the swap',
            ),
            _persistedIntent(
              id: 'complete-swap',
              txHash: 'complete-tx',
              status: SwapIntentStatus.complete,
              nextAction: 'Receipt ready',
            ),
            _persistedIntent(
              id: 'expired-swap',
              txHash: 'expired-tx',
              status: SwapIntentStatus.expired,
              nextAction: 'Start a fresh quote',
            ),
            _persistedIntent(
              id: 'shielding-failed-swap',
              txHash: 'shielding-failed-tx',
              status: SwapIntentStatus.shieldingFailed,
              nextAction: 'Retry wallet shielding',
            ),
            _persistedIntent(
              id: 'unknown-status-swap',
              txHash: 'unknown-status-tx',
              status: SwapIntentStatus.providerStatusUnknown,
              nextAction: 'Check provider status',
            ),
            _persistedIntent(
              id: 'incomplete-swap',
              txHash: 'incomplete-tx',
              status: SwapIntentStatus.incompleteDeposit,
              nextAction: 'Check deposit amount',
            ),
            _persistedIntent(
              id: 'open-swap',
              txHash: 'open-tx',
              status: SwapIntentStatus.processing,
              nextAction: 'Processing',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_queue_group_open')), findsOneWidget);
    expect(find.text('Open 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_queue_group_completed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_queue_group_failed')),
      findsOneWidget,
    );
    expect(find.text('Attention'), findsOneWidget);
    expect(find.text('Attention 5'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_queue_row_failed-swap')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_queue_row_expired-swap')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_queue_row_shielding-failed-swap')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_queue_row_unknown-status-swap')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_queue_row_incomplete-swap')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('swap_queue_progress_segment_blink_processing_2'),
      ),
      findsOneWidget,
    );
    final colors = tester
        .element(
          find.byKey(const ValueKey('swap_queue_progress_segment_complete_0')),
        )
        .colors;
    for (var index = 0; index < 4; index++) {
      final segment = tester.widget<Container>(
        find.byKey(ValueKey('swap_queue_progress_segment_complete_$index')),
      );
      final decoration = segment.decoration! as BoxDecoration;
      expect(decoration.color, colors.text.success);
    }

    final processingStatusText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('swap_queue_row_open-swap')),
        matching: find.text('Swapping through provider'),
      ),
    );
    expect(processingStatusText.style?.color, colors.text.accent);
    expect(processingStatusText.style?.color, isNot(colors.text.warning));
  });

  testWidgets('swap queue progress stages skipped status transitions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themeHarness(
        SwapQueuePanel(
          intents: [
            _persistedIntent(
              id: 'jump-swap',
              txHash: '',
              status: SwapIntentStatus.awaitingDeposit,
              nextAction: 'Waiting for deposit',
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('swap_queue_live_pulse_jump-swap')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('swap_queue_progress_segment_blink_awaitingDeposit_0'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _themeHarness(
        SwapQueuePanel(
          intents: [
            _persistedIntent(
              id: 'jump-swap',
              txHash: 'jump-tx',
              status: SwapIntentStatus.shieldingPending,
              nextAction: 'Shielding in wallet',
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey('swap_queue_progress_segment_blink_shieldingPending_1'),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 430));
    expect(
      find.byKey(
        const ValueKey('swap_queue_progress_segment_blink_shieldingPending_2'),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 430));
    expect(
      find.byKey(
        const ValueKey('swap_queue_progress_segment_blink_shieldingPending_3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'swap queue shows deposit confirmation after wallet tx broadcast',
    (tester) async {
      await tester.pumpWidget(
        _themeHarness(
          SwapQueuePanel(
            intents: [
              _persistedIntent(
                id: 'confirming-deposit',
                txHash: 'zec-auto-txid',
                status: SwapIntentStatus.awaitingDeposit,
                nextAction: 'Waiting for deposit',
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Confirming deposit'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('swap_queue_progress_segment_blink_awaitingDeposit_1'),
        ),
        findsOneWidget,
      );
    },
  );

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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
    await tester.pumpAndSettle();

    expect(find.text('Check deposit amount'), findsWidgets);
    expect(
      find.byKey(const ValueKey('swap_queue_group_failed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_queue_row_swap-refund')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_queue_row_swap-failed')),
      findsOneWidget,
    );

    await _openActivityDetail(tester, 'swap-underpaid');

    expect(find.byKey(const ValueKey('swap_resolution_panel')), findsOneWidget);
    expect(find.text('Deposit needs attention'), findsOneWidget);
    expect(
      find.text('Top up the missing amount or wait for refund.'),
      findsOneWidget,
    );
    expect(find.text('Resolve incomplete deposit'), findsOneWidget);
    expect(find.text('Copy top-up details'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_resolution_copy_deposit_button')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Send only the missing amount with the same one-time deposit details, or wait for the refund path.',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('swap_resolution_copy_deposit_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('swap_resolution_copy_deposit_button')),
    );
    await tester.pumpAndSettle();

    expect(clipboardWrites, hasLength(1));
    expect(
      clipboardWrites.single,
      contains('Deposit address: 0xunderpaid-usdc-deposit'),
    );
    expect(clipboardWrites.single, contains('Deposit memo: memo-underpaid'));
    expect(find.text('Top-up Details Copied'), findsOneWidget);

    await _openActivityDetail(tester, 'swap-refund');

    expect(find.byKey(const ValueKey('swap_resolution_panel')), findsOneWidget);
    expect(find.text('Funds refunded'), findsOneWidget);
    expect(
      find.text('Check the refund transaction before retrying.'),
      findsOneWidget,
    );
    expect(find.text('Refund complete'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_resolution_review_again_button')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Check the origin-chain refund transaction before starting a fresh quote.',
      ),
      findsOneWidget,
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

    expect(
      clipboardWrites.last,
      'https://explorer.near-intents.org/transactions/t1refund-zec-deposit',
    );
    expect(find.text('Explorer Link Copied'), findsOneWidget);

    await _revealSupportBundle(tester);
    final refundSupportPanel = find.byKey(
      const ValueKey('swap_support_bundle_panel'),
    );
    expect(
      find.descendant(
        of: refundSupportPanel,
        matching: find.text('Refund tx submitted'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: refundSupportPanel,
        matching: find.text('Refunded to source address'),
      ),
      findsNothing,
    );

    await _openActivityDetail(tester, 'swap-failed');

    expect(find.byKey(const ValueKey('swap_resolution_panel')), findsOneWidget);
    expect(find.text('Swap failed'), findsOneWidget);
    expect(find.text('Start a fresh quote when ready.'), findsOneWidget);
    expect(find.text('Route failed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_resolution_review_again_button')),
      findsOneWidget,
    );
    expect(
      find.text(
        'No funds moved according to status. Review the receipt, then start a new quote.',
      ),
      findsOneWidget,
    );
    await _revealSupportBundle(tester);
    final failedSupportPanel = find.byKey(
      const ValueKey('swap_support_bundle_panel'),
    );
    expect(
      find.descendant(
        of: failedSupportPanel,
        matching: find.text('Swap route failed'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: failedSupportPanel,
        matching: find.text('No funds moved'),
      ),
      findsNothing,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('swap_resolution_review_again_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('swap_resolution_review_again_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('NEAR -> ZEC'), findsNothing);
    expect(_fieldText(tester, 'swap_amount_field'), '14.00');
    expect(_fieldText(tester, 'swap_destination_field'), 'rowan.near');
    expect(find.text('NEAR refund'), findsWidgets);
  });

  testWidgets('activity restores persisted swap sessions', (tester) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final sessionStore = _FakeSwapSessionStore(
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        sessionStore: sessionStore,
        liveFundsEnabled: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
    await tester.pumpAndSettle();

    expect(sessionStore.loadCount, 1);
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

    expect(find.text('persisted-deposit'), findsWidgets);
    expect(find.text('persisted-txid'), findsWidgets);
    expect(find.text('USDC delivery in progress'), findsWidgets);
  });

  testWidgets(
    'restored external-to-ZEC swap keeps staging address after status refresh',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _LongExternalStatusSwapProvider();
      final sessionStore = _FakeSwapSessionStore(
        initialIntents: [
          _persistedExternalToZecIntent(
            id: '0xpersisted-usdc-deposit',
            stagingAddress: 't1persistedrotatingstaging',
          ),
        ],
      );

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [
              GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
            ],
          ),
          swapProvider: swapProvider,
          sessionStore: sessionStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
      await tester.pumpAndSettle();

      expect(sessionStore.loadCount, 1);
      expect(swapProvider.statusRequests, hasLength(1));
      expect(
        swapProvider.statusRequests.single.depositAddress,
        '0xpersisted-usdc-deposit',
      );
      expect(
        sessionStore.savedIntents.single.oneClickRecipient,
        't1persistedrotatingstaging',
      );
      expect(
        sessionStore.savedIntents.single.oneClickRefundTo,
        '0xpersisted-refund',
      );

      await _openActivityDetail(tester, '0xpersisted-usdc-deposit');

      expect(find.text('t1persistedrotatingstaging'), findsWidgets);
      expect(find.text('Send USDC'), findsWidgets);
      expect(
        find.byKey(const ValueKey('swap_activity_deposit_qr_panel')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'external-to-ZEC provider success stays pending until shielding finishes',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _CompletingExternalStatusSwapProvider();
      final shieldingService = _FakeSwapShieldingService.notReady();
      final sessionStore = _FakeSwapSessionStore(
        initialIntents: [
          _persistedExternalToZecIntent(
            id: '0xcomplete',
            stagingAddress: 't1shieldingstillpending',
          ),
        ],
      );

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [
              GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
            ],
          ),
          swapProvider: swapProvider,
          shieldingService: shieldingService,
          sessionStore: sessionStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
      await tester.pumpAndSettle();

      expect(swapProvider.statusRequests, hasLength(1));
      expect(shieldingService.requests, hasLength(1));
      expect(shieldingService.requests.single.accountUuid, 'account-1');
      expect(
        shieldingService.requests.single.transparentAddress,
        't1shieldingstillpending',
      );
      expect(
        sessionStore.savedIntents.single.status,
        SwapIntentStatus.shieldingPending,
      );
      expect(find.text('Shielding in wallet'), findsOneWidget);
      expect(find.text('Complete'), findsNothing);

      await _openActivityDetail(tester, '0xcomplete');

      expect(find.text('Making ZEC spendable'), findsOneWidget);
      expect(find.text('Make spendable'), findsWidgets);
      expect(find.text('Technical details'), findsNothing);
    },
  );

  testWidgets(
    'hardware external-to-ZEC provider success waits for manual shield signing',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _CompletingExternalStatusSwapProvider();
      final shieldingService = _FakeSwapShieldingService.success(
        SwapShieldingResult(
          txids: 'should-not-auto-shield',
          feeZatoshi: BigInt.from(10000),
          shieldedZatoshi: BigInt.from(200000000),
        ),
      );
      final hardwareSigningService = _FakeSwapHardwareSigningService();
      final sessionStore = _FakeSwapSessionStore(
        initialIntents: [
          _persistedExternalToZecIntent(
            id: '0xhardwarecomplete',
            stagingAddress: 't1hardwarestaging',
          ),
        ],
      );

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [
              GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
            ],
          ),
          bootstrap: _hardwareBootstrap,
          swapProvider: swapProvider,
          shieldingService: shieldingService,
          hardwareSigningService: hardwareSigningService,
          sessionStore: sessionStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
      await tester.pumpAndSettle();

      expect(swapProvider.statusRequests, hasLength(1));
      expect(shieldingService.requests, isEmpty);
      expect(hardwareSigningService.shieldDrafts, isEmpty);
      expect(
        sessionStore.savedIntents.single.status,
        SwapIntentStatus.shieldingPending,
      );
      expect(
        sessionStore.savedIntents.single.nextAction,
        'Sign a shield transaction with Keystone to make ZEC spendable.',
      );

      await _openActivityDetail(tester, '0xhardwarecomplete');

      expect(
        find.byKey(const ValueKey('swap_hardware_shield_action_panel')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('swap_hardware_shield_button')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('swap_hardware_shield_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      expect(hardwareSigningService.shieldDrafts, ['t1hardwarestaging']);
      expect(find.text('Sign shield transaction on Keystone'), findsOneWidget);
      expect(shieldingService.requests, isEmpty);
    },
  );

  testWidgets(
    'external-to-ZEC provider success starts shield confirmation tracking',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _CompletingExternalStatusSwapProvider();
      final shieldingService = _FakeSwapShieldingService.success(
        SwapShieldingResult(
          txids: 'shield-txid-1',
          feeZatoshi: BigInt.from(10000),
          shieldedZatoshi: BigInt.from(200000000),
        ),
      );
      final sessionStore = _FakeSwapSessionStore(
        initialIntents: [
          _persistedExternalToZecIntent(
            id: '0xcomplete',
            stagingAddress: 't1shieldnowstaging',
          ),
        ],
      );

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [
              GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
            ],
          ),
          swapProvider: swapProvider,
          shieldingService: shieldingService,
          sessionStore: sessionStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
      await tester.pumpAndSettle();

      expect(swapProvider.statusRequests, hasLength(1));
      expect(shieldingService.requests, hasLength(1));
      expect(shieldingService.trackRequests, isEmpty);
      expect(
        shieldingService.requests.single.transparentAddress,
        't1shieldnowstaging',
      );
      expect(
        sessionStore.savedIntents.single.status,
        SwapIntentStatus.shieldingConfirming,
      );
      expect(
        sessionStore.savedIntents.single.nextAction,
        'Waiting for shield transaction confirmation.',
      );
      expect(sessionStore.savedIntents.single.shieldTxHash, 'shield-txid-1');
      expect(
        sessionStore.savedIntents.single.receipt
            .where((field) => field.label == 'Shield tx')
            .single
            .value,
        'shield-txid-1',
      );
      expect(
        sessionStore.savedIntents.single.receipt
            .where((field) => field.label == 'Shield fee')
            .single
            .value,
        '0.0001 ZEC',
      );
      expect(sessionStore.saveSnapshots, hasLength(greaterThanOrEqualTo(2)));
      expect(
        sessionStore.saveSnapshots.first.single.status,
        SwapIntentStatus.shieldingConfirming,
      );
      expect(
        sessionStore.saveSnapshots.first.single.shieldTxHash,
        'shield-txid-1',
      );
      expect(find.text('Shielding in wallet'), findsOneWidget);

      await _openActivityDetail(tester, '0xcomplete');

      expect(find.text('Confirming spendable ZEC'), findsOneWidget);
      expect(find.text('Make spendable'), findsWidgets);
      expect(find.text('Technical details'), findsNothing);
      await _revealSupportBundle(tester);
      expect(find.text('Shield fee'), findsWidgets);
      expect(find.text('0.0001 ZEC'), findsWidgets);

      shieldingService.trackRequests.clear();
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();

      expect(shieldingService.trackRequests, hasLength(1));
      expect(shieldingService.trackRequests.single.txHash, 'shield-txid-1');
    },
  );

  testWidgets('confirmed shield transaction completes external-to-ZEC intent', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _CompletingExternalStatusSwapProvider();
    final shieldingService = _FakeSwapShieldingService.success(
      SwapShieldingResult(
        txids: 'unused-broadcast-txid',
        feeZatoshi: BigInt.from(10000),
        shieldedZatoshi: BigInt.from(200000000),
      ),
      trackStatus: SwapShieldTxStatus.mined,
    );
    final sessionStore = _FakeSwapSessionStore(
      initialIntents: [
        _persistedShieldingConfirmingIntent(
          id: '0xconfirming',
          stagingAddress: 't1confirmingstaging',
          shieldTxHash: 'shield-txid-mined',
        ),
      ],
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        shieldingService: shieldingService,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
    await tester.pumpAndSettle();

    expect(swapProvider.statusRequests, isEmpty);
    expect(shieldingService.requests, isEmpty);
    expect(shieldingService.trackRequests, hasLength(1));
    expect(shieldingService.trackRequests.single.accountUuid, 'account-1');
    expect(shieldingService.trackRequests.single.txHash, 'shield-txid-mined');
    expect(sessionStore.savedIntents.single.status, SwapIntentStatus.complete);
    expect(
      sessionStore.savedIntents.single.nextAction,
      'Shield transaction confirmed.',
    );
    await _openActivityDetail(tester, '0xconfirming');

    expect(find.text('ZEC ready'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_status_refresh_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_queue_refresh_button')),
      findsNothing,
    );
    expect(swapProvider.statusRequests, isEmpty);
    expect(shieldingService.requests, isEmpty);
    expect(shieldingService.trackRequests, hasLength(1));
    expect(sessionStore.savedIntents.last.status, SwapIntentStatus.complete);
    expect(find.text('ZEC ready'), findsOneWidget);
    expect(find.text('Confirming spendable ZEC'), findsNothing);
    expect(find.text('Making ZEC spendable'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_activity_route_step_3_done')),
      findsOneWidget,
    );
  });

  testWidgets('expired shield transaction opens retry recovery', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _CompletingExternalStatusSwapProvider();
    final shieldingService = _FakeSwapShieldingService.success(
      SwapShieldingResult(
        txids: 'unused-broadcast-txid',
        feeZatoshi: BigInt.from(10000),
        shieldedZatoshi: BigInt.from(200000000),
      ),
      trackStatus: SwapShieldTxStatus.expired,
    );
    final sessionStore = _FakeSwapSessionStore(
      initialIntents: [
        _persistedShieldingConfirmingIntent(
          id: '0xexpiredshield',
          stagingAddress: 't1expiredshieldstaging',
          shieldTxHash: 'shield-txid-expired',
        ),
      ],
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        shieldingService: shieldingService,
        sessionStore: sessionStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
    await tester.pumpAndSettle();

    expect(swapProvider.statusRequests, isEmpty);
    expect(shieldingService.trackRequests.single.txHash, 'shield-txid-expired');
    expect(
      sessionStore.savedIntents.single.status,
      SwapIntentStatus.shieldingFailed,
    );
    expect(find.text('Shielding needs retry'), findsOneWidget);

    await _openActivityDetail(tester, '0xexpiredshield');

    expect(find.text('Retry shield'), findsOneWidget);
  });

  testWidgets(
    'external-to-ZEC shielding service failure opens retry recovery',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _CompletingExternalStatusSwapProvider();
      final shieldingService = _FakeSwapShieldingService.failure(
        StateError('shield broadcast failed'),
      );
      final sessionStore = _FakeSwapSessionStore(
        initialIntents: [
          _persistedExternalToZecIntent(
            id: '0xcomplete',
            stagingAddress: 't1shieldfailurestaging',
          ),
        ],
      );

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [
              GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
            ],
          ),
          swapProvider: swapProvider,
          shieldingService: shieldingService,
          sessionStore: sessionStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
      await tester.pumpAndSettle();

      expect(shieldingService.requests, hasLength(1));
      expect(
        shieldingService.requests.single.transparentAddress,
        't1shieldfailurestaging',
      );
      expect(
        sessionStore.savedIntents.single.status,
        SwapIntentStatus.shieldingFailed,
      );
      await _openActivityDetail(tester, '0xcomplete');

      expect(
        find.byKey(const ValueKey('swap_resolution_panel')),
        findsOneWidget,
      );
      expect(find.text('Retry shield'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('swap_deposit_submit_button')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'shielding failure exposes retry without re-sending external funds',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _ShieldingFailedStatusSwapProvider();
      final sessionStore = _FakeSwapSessionStore(
        initialIntents: [
          _persistedShieldingFailedIntent(
            id: '0xshieldfail',
            stagingAddress: 't1failedshieldstaging',
          ),
        ],
      );

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [
              GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
            ],
          ),
          swapProvider: swapProvider,
          sessionStore: sessionStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
      await tester.pumpAndSettle();

      expect(find.text('Shielding needs retry'), findsOneWidget);
      await _openActivityDetail(tester, '0xshieldfail');

      expect(
        find.byKey(const ValueKey('swap_resolution_panel')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Do not send the external deposit again. Retry shielding from the staging address or keep this recovery record open.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry shield'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('swap_resolution_retry_shield_button')),
        findsOneWidget,
      );
      expect(find.text('t1failedshieldstaging'), findsWidgets);
      expect(
        find.byKey(const ValueKey('swap_deposit_tx_hash_field')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('swap_deposit_submit_button')),
        findsNothing,
      );
      expect(find.text('Submit USDC deposit'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('swap_resolution_retry_shield_button')),
      );
      await tester.pumpAndSettle();

      expect(
        sessionStore.savedIntents.single.status,
        SwapIntentStatus.shieldingPending,
      );
      expect(find.text('Shielding in wallet'), findsOneWidget);
      expect(find.byKey(const ValueKey('swap_resolution_panel')), findsNothing);
      expect(
        find.byKey(const ValueKey('swap_deposit_submit_button')),
        findsNothing,
      );
    },
  );

  testWidgets('open swap sessions poll status after the configured interval', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final sessionStore = _FakeSwapSessionStore(
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
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
    final sessionStore = _FakeSwapSessionStore(
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        sessionStore: sessionStore,
        liveFundsEnabled: true,
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

  testWidgets('deposit transaction submit uses the stored deposit address', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final sessionStore = _FakeSwapSessionStore(
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        sessionStore: sessionStore,
        liveFundsEnabled: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
    await tester.pumpAndSettle();
    await _openActivityDetail(tester, 'swap-session-2');

    expect(
      find.byKey(const ValueKey('swap_support_details_section')),
      findsOneWidget,
    );
    await _revealSupportBundle(tester);
    expect(find.text('Provider quote'), findsWidgets);
    expect(find.text('quote-1'), findsWidgets);
    expect(find.text('Copy details'), findsWidgets);

    await _expandDepositTxHash(tester);
    await tester.enterText(
      find.byKey(const ValueKey('swap_deposit_tx_hash_field')),
      'external-txid',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('swap_deposit_submit_button')),
    );
    await tester.pumpAndSettle();
    await _tapDepositSubmit(tester);

    expect(swapProvider.submittedDeposits, hasLength(1));
    expect(
      swapProvider.submittedDeposits.single.depositAddress,
      '0xstored-deposit',
    );
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Powered by NEAR Intents'), findsWidgets);
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
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
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

    await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
    await tester.pumpAndSettle();

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
          title: 'USDC to ZEC',
          pair: 'USDC -> ZEC',
          sellAmount: '12345.678901 USDC',
          receiveEstimate: '~175.9421 ZEC',
          direction: SwapDirection.externalToZec,
          externalAsset: SwapAsset.usdc,
          depositMemo:
              'memo-with-a-long-routing-tag-and-provider-reference-9876543210',
          oneClickRefundTo:
              '0xrefund-address-with-a-very-long-source-chain-suffix-abcdef1234567890',
          exposure: const [
            SwapPrototypeField(
              label: 'USDC source deposit',
              value:
                  'one-time USDC address with source-chain routing metadata visible',
            ),
            SwapPrototypeField(
              label: 'Refund path',
              value:
                  'USDC refunds return to the long source-chain address entered during review',
            ),
          ],
          receipt: const [
            SwapPrototypeField(
              label: 'Swap id',
              value: 'swap-long-provider-data',
            ),
            SwapPrototypeField(
              label: 'Deposit',
              value:
                  '0xone-time-usdc-deposit-address-with-a-long-provider-suffix-abcdef1234567890',
            ),
            SwapPrototypeField(
              label: 'Memo',
              value:
                  'memo-with-a-long-routing-tag-and-provider-reference-9876543210',
            ),
          ],
        );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: _LongExternalStatusSwapProvider(),
        sessionStore: _FakeSwapSessionStore(initialIntents: [longIntent]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_page_tab_activity')));
    await tester.pumpAndSettle();
    await _openActivityDetail(tester, 'swap-long-provider-data');

    expect(tester.takeException(), isNull);
    expect(find.text('Send USDC from source chain'), findsWidgets);
    expect(
      find.text(
        '0xone-time-usdc-deposit-address-with-a-long-provider-suffix-abcdef1234567890',
      ),
      findsWidgets,
    );
    expect(
      find.byKey(const ValueKey('swap_deposit_tx_hash_disclosure')),
      findsOneWidget,
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
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
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrefund-address-with-a-very-long-source-chain-suffix-abcdef1234567890',
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
      find.byKey(const ValueKey('swap_review_status_badge')),
      findsOneWidget,
    );
    expect(find.text('Estimated fee'), findsOneWidget);
  });

  testWidgets('swap composer previews, reviews, and starts a preview intent', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
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
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xabc123',
    );
    await tester.pumpAndSettle();

    expect(find.text('~105.26'), findsOneWidget);
    expect(find.text('1 ZEC = 70.17 USDC'), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_rate_line')), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_address_summary')), findsOneWidget);
    expect(find.text('Recipient'), findsOneWidget);
    expect(find.text('0xabc123'), findsWidgets);
    expect(find.text('Ethereum'), findsWidgets);
    expect(find.text('Settlement path'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_review_panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_review_modal')), findsOneWidget);
    final reviewScrollbar = tester.widget<RawScrollbar>(
      find.byKey(const ValueKey('swap_review_scrollbar')),
    );
    expect(reviewScrollbar.thickness, 4);
    expect(reviewScrollbar.crossAxisMargin, AppSpacing.xxs);
    final scrollGutter = tester.widget<Padding>(
      find.byKey(const ValueKey('swap_review_scroll_gutter')),
    );
    expect(scrollGutter.padding, const EdgeInsets.only(right: AppSpacing.s));
    expect(
      tester.getSize(find.byKey(const ValueKey('swap_review_panel'))).height,
      greaterThan(900),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('swap_review_title')))
          .style!
          .fontSize,
      greaterThanOrEqualTo(26),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('swap_start_button'))).height,
      greaterThanOrEqualTo(54),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('swap_review_cancel_button')))
          .height,
      greaterThanOrEqualTo(54),
    );
    final startButtonWidth = tester
        .getSize(find.byKey(const ValueKey('swap_start_button')))
        .width;
    final cancelButtonWidth = tester
        .getSize(find.byKey(const ValueKey('swap_review_cancel_button')))
        .width;
    final actionsWidth = tester
        .getSize(find.byKey(const ValueKey('swap_review_actions')))
        .width;
    expect(startButtonWidth, closeTo(cancelButtonWidth, 1));
    expect(
      startButtonWidth + cancelButtonWidth + AppSpacing.s,
      closeTo(actionsWidth, 1),
    );
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
    expect(find.text('Swap review'), findsOneWidget);
    expect(find.text('Live quote'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_review_consent_panel')),
      findsOneWidget,
    );
    expect(find.text('Approval sends the ZEC deposit'), findsOneWidget);
    expect(find.text('1.5000 ZEC'), findsWidgets);
    expect(find.text('Estimated fee'), findsOneWidget);
    expect(find.text('Minimum receive'), findsOneWidget);
    expect(find.text('Swap fee'), findsOneWidget);
    expect(find.text('Price protection'), findsOneWidget);
    expect(find.text('Send ZEC deposit'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    expect(find.text('Swap created in Activity'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_toast_overlay_host')),
        matching: find.text('Swap created in Activity'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('swap_queue_title')), findsOneWidget);
    expect(find.text('Technical details'), findsNothing);
    await _closeActivityDetail(tester);
    await tester.tap(find.byKey(const ValueKey('swap_page_tab_swap')));
    await tester.pumpAndSettle();
    expect(_fieldText(tester, 'swap_amount_field'), isEmpty);
    expect(_fieldText(tester, 'swap_destination_field'), isEmpty);
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
            routes: [
              GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
            ],
          ),
          swapProvider: swapProvider,
          seedPrototypeFixtures: false,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '1.5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('swap_destination_field')),
        '0xrecipient',
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
      expect(request.destination, '0xrecipient');
      expect(request.refundAddress, 't1actualstaging');

      expect(find.byKey(const ValueKey('swap_review_panel')), findsOneWidget);
      expect(find.text('Live quote'), findsOneWidget);
      expect(find.text('Send ZEC deposit to'), findsOneWidget);
      expect(find.text('t1live-deposit'), findsOneWidget);
      expect(find.text('Memo memo-live'), findsOneWidget);
      expect(find.text('Minimum receive'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('swap_review_details_toggle')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Refund address'), findsOneWidget);
      expect(find.text('Receive address'), findsOneWidget);
      expect(find.text('Expires in'), findsNothing);
    },
  );

  testWidgets('review quote can be cancelled without clearing the draft', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(find.text('Swap review'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('swap_review_cancel_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_review_cancel_button')));
    await tester.pumpAndSettle();

    expect(find.text('Swap review'), findsNothing);
    expect(_fieldText(tester, 'swap_amount_field'), '1.5');
    expect(_fieldText(tester, 'swap_destination_field'), '0xrecipient');
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        liveFundsEnabled: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swap_rate_line')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pump();

    expect(find.text('Getting live quote'), findsNothing);
    expect(find.text('Getting quote'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_review_button')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.loader,
        ),
      ),
      findsOneWidget,
    );

    swapProvider.completeQuote();
    await tester.pumpAndSettle();

    expect(find.text('Getting live quote'), findsNothing);
    expect(find.byKey(const ValueKey('swap_rate_line')), findsOneWidget);
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        liveFundsEnabled: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    expect(swapProvider.requests, hasLength(1));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SwapScreen)),
    );
    container.read(swapPrototypeProvider.notifier).expireReviewQuote();
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('swap_review_status_badge')),
        matching: find.text('Quote expired'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('Quote expired. Review again for a fresh route.'),
      findsOneWidget,
    );
    expect(find.text('Review again required'), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.startedQuotes, isEmpty);

    await tester.tap(find.byKey(const ValueKey('swap_review_again_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.requests, hasLength(2));
    expect(
      find.text('Quote expired. Review again for a fresh route.'),
      findsNothing,
    );
    expect(find.text('Send ZEC deposit'), findsOneWidget);
  });

  testWidgets('quote failure shows an inline error and preserves the draft', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final releasedAddresses = <String>[];

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: _FailingQuoteSwapProvider(),
        releaseExchangeTransparentAddress:
            ({required accountUuid, required address, required dbPath}) async {
              releasedAddresses.add(address);
              return true;
            },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(find.text('Swap review'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_quote_error_banner')),
      findsOneWidget,
    );
    expect(find.text('Quote unavailable'), findsOneWidget);
    expect(
      find.textContaining('Could not load quote. Retry once.'),
      findsOneWidget,
    );
    expect(_fieldText(tester, 'swap_amount_field'), '1.5');
    expect(_fieldText(tester, 'swap_destination_field'), '0xrecipient');
    expect(releasedAddresses, ['t1actualstaging']);
  });

  testWidgets('start failure stays on review and shows an inline error', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FailingStartSwapProvider();
    final releasedAddresses = <String>[];

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        liveFundsEnabled: true,
        releaseExchangeTransparentAddress:
            ({required accountUuid, required address, required dbPath}) async {
              releasedAddresses.add(address);
              return true;
            },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
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
    expect(
      find.textContaining('Could not start swap. Retry once.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('swap_queue_title')), findsNothing);
    expect(releasedAddresses, ['t1actualstaging']);
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
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
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
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xexternal-refund',
    );
    await tester.pumpAndSettle();

    expect(find.text('USDC refund'), findsWidgets);
    expect(find.byKey(const ValueKey('swap_address_summary')), findsOneWidget);
    expect(find.text('Refund only'), findsWidgets);
    expect(find.text('ZEC delivery'), findsNothing);
    expect(find.text('t1wallet-shield-prompt-staging'), findsNothing);
    expect(
      find.text('ZEC lands on current wallet t-address; shield prompt follows'),
      findsNothing,
    );
    expect(find.text('USDC source deposit'), findsNothing);
    expect(find.text('ZEC staging'), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_settlement_shielding_note')),
      findsNothing,
    );
    expect(find.text('~2.0000'), findsWidgets);
    expect(find.text('1 USDC = 0.0143 ZEC'), findsOneWidget);
    expect(find.text('USDC -> ZEC'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(find.text('Swap review'), findsOneWidget);
    expect(find.text('Estimated fee'), findsOneWidget);
    expect(find.text('Swap fee'), findsOneWidget);
    expect(find.text('Send USDC to source-chain deposit'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_review_deposit_qr_panel')),
      findsOneWidget,
    );
    final reviewQr = tester.widget<SwapDepositQrPanel>(
      find.byKey(const ValueKey('swap_review_deposit_qr_panel')),
    );
    expect(reviewQr.qrData, '0xlive-deposit');
    expect(reviewQr.address, '0xlive-deposit');
    expect(
      find.byKey(const ValueKey('swap_deposit_qr_copy_memo')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('swap_deposit_qr_copy_memo')));
    await tester.pumpAndSettle();
    expect(find.text('Memo Copied'), findsOneWidget);
    expect(find.text('ZEC delivery'), findsNothing);
    expect(find.text('Approval locks deposit instructions'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('swap_review_details_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('USDC refund'), findsWidgets);
    expect(find.text('0xexternal-refund'), findsWidgets);

    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    expect(find.text('Send USDC'), findsWidgets);
    expect(
      find.byKey(const ValueKey('swap_activity_deposit_qr_panel')),
      findsOneWidget,
    );
    await _closeActivityDetail(tester);
    await tester.tap(find.byKey(const ValueKey('swap_page_tab_swap')));
    await tester.pumpAndSettle();
    expect(_fieldText(tester, 'swap_amount_field'), isEmpty);
    expect(_fieldText(tester, 'swap_destination_field'), isEmpty);
  });

  testWidgets('review quote blocks silent default t-address fallback', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1180, 720));
    final swapProvider = _FakeSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        reserveExchangeTransparentAddress:
            ({required accountUuid, required dbPath, required network}) async {
              throw Exception('ephemeral gap exhausted');
            },
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
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xexternal-refund',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.requests, isEmpty);
    expect(find.text('Swap review'), findsNothing);
    expect(
      find.textContaining('Could not reserve a fresh wallet t-address.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('review quote uses reserved rotating staging as ZEC recipient', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        reserveExchangeTransparentAddress:
            ({required accountUuid, required dbPath, required network}) async {
              expect(accountUuid, 'account-1');
              expect(dbPath, 'wallet.db');
              expect(network, 'main');
              return rust_wallet.ExchangeTransparentAddressResult(
                address: 't1rotatingstaging',
                transparentChildIndex: 7,
                exposedAtHeight: BigInt.from(2500000),
              );
            },
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
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xexternal-refund',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.requests, hasLength(1));
    expect(swapProvider.requests.single.direction, SwapDirection.externalToZec);
    expect(swapProvider.requests.single.destination, 't1rotatingstaging');
    expect(swapProvider.requests.single.refundAddress, '0xexternal-refund');
    expect(find.text('Swap review'), findsOneWidget);
    expect(
      find.text('rotating wallet t-address -> shield prompt'),
      findsNothing,
    );
  });

  testWidgets('started swap can refresh status from provider', (tester) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.startedQuotes, hasLength(1));
    expect(find.text('t1live-deposit'), findsWidgets);
    expect(find.text('Technical details'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_status_refresh_button')));
    await tester.pumpAndSettle();

    expect(swapProvider.statusRequests, hasLength(1));
    expect(swapProvider.statusRequests.single.depositAddress, 't1live-deposit');
    expect(swapProvider.statusRequests.single.depositMemo, 'memo-live');
    expect(find.text('USDC delivery in progress'), findsWidgets);
  });

  testWidgets('started swap can submit a deposit transaction hash', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        liveFundsEnabled: true,
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
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xexternal-refund',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    await _expandDepositTxHash(tester);
    await tester.enterText(
      find.byKey(const ValueKey('swap_deposit_tx_hash_field')),
      'zec-txid',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('swap_deposit_submit_button')),
    );
    await tester.pumpAndSettle();
    await _tapDepositSubmit(tester);

    expect(swapProvider.submittedDeposits, hasLength(1));
    expect(
      swapProvider.submittedDeposits.single.depositAddress,
      '0xlive-deposit',
    );
    expect(swapProvider.submittedDeposits.single.txHash, 'zec-txid');
    expect(swapProvider.submittedDeposits.single.depositMemo, 'memo-live');
    expect(find.text('ZEC deposit confirmed'), findsWidgets);
  });

  testWidgets(
    'activity shows direction-specific external deposit instructions',
    (tester) async {
      await _setDesktopViewport(tester);
      final sessionStore = _FakeSwapSessionStore();
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
            routes: [
              GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
            ],
          ),
          sessionStore: sessionStore,
          reserveExchangeTransparentAddress:
              ({
                required accountUuid,
                required dbPath,
                required network,
              }) async {
                return rust_wallet.ExchangeTransparentAddressResult(
                  address: 't1rotatingstaging',
                  transparentChildIndex: 8,
                  exposedAtHeight: BigInt.from(2500001),
                );
              },
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
      await tester.enterText(
        find.byKey(const ValueKey('swap_destination_field')),
        '0xexternal-refund',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start swap'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start swap'));
      await tester.pumpAndSettle();

      expect(find.text('Send USDC from source chain'), findsOneWidget);
      expect(find.text('0xlive-deposit'), findsWidgets);
      expect(
        find.byKey(const ValueKey('swap_activity_deposit_qr_panel')),
        findsOneWidget,
      );
      final activityQr = tester.widget<SwapDepositQrPanel>(
        find.byKey(const ValueKey('swap_activity_deposit_qr_panel')),
      );
      expect(activityQr.qrData, '0xlive-deposit');
      expect(activityQr.address, '0xlive-deposit');
      expect(find.text('USDC source deposit'), findsWidgets);
      expect(
        find.byKey(const ValueKey('swap_copy_usdc_source_deposit')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('swap_copy_usdc_source_deposit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('swap_copy_usdc_source_deposit')),
      );
      await tester.pumpAndSettle();
      expect(clipboardWrites.last, '0xlive-deposit');
      expect(find.text('Address Copied'), findsOneWidget);
      expect(find.text('Memo'), findsWidgets);
      expect(find.text('memo-live'), findsWidgets);
      expect(find.byKey(const ValueKey('swap_copy_memo')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('swap_copy_memo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('swap_copy_memo')));
      await tester.pumpAndSettle();
      expect(clipboardWrites.last, 'memo-live');
      expect(find.text('Memo Copied'), findsOneWidget);
      expect(find.text('Receive address'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('swap_copy_receive_address')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('swap_copy_receive_address')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('swap_copy_receive_address')));
      await tester.pumpAndSettle();
      expect(clipboardWrites.last, 't1rotatingstaging');
      expect(find.text('Address Copied'), findsOneWidget);
      expect(find.text('t1rotatingstaging'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('swap_open_receive_staging_button')),
        findsNothing,
      );
      expect(
        find.text('wallet receive address; shield prompt follows'),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('swap_deposit_tx_hash_disclosure')),
        findsOneWidget,
      );
      expect(find.text('Add tx hash'), findsOneWidget);
      expect(
        find.textContaining(
          'Add the deposit transaction hash to speed up status checks.',
        ),
        findsOneWidget,
      );
      expect(find.text('Live submit disabled'), findsNothing);
      expect(sessionStore.savedIntents, hasLength(1));
      expect(sessionStore.savedIntents.single.id, '0xlive-deposit');
      expect(sessionStore.savedIntents.single.depositAddress, '0xlive-deposit');
      expect(sessionStore.savedIntents.single.depositMemo, 'memo-live');
      expect(sessionStore.savedIntents.single.providerQuoteId, 'quote-live');
      expect(sessionStore.savedIntents.single.providerSignature, 'sig-live');
      expect(
        sessionStore.savedIntents.single.oneClickRecipient,
        't1rotatingstaging',
      );
      expect(
        sessionStore.savedIntents.single.oneClickRefundTo,
        '0xexternal-refund',
      );
    },
  );

  testWidgets('live-funds gate can disable ZEC auto deposit broadcast', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final depositSender = _FakeSwapDepositSender();
    final sessionStore = _FakeSwapSessionStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        depositSender: depositSender,
        sessionStore: sessionStore,
        liveFundsEnabled: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();

    expect(depositSender.requests, isEmpty);
    expect(swapProvider.submittedDeposits, isEmpty);
    expect(sessionStore.savedIntents, hasLength(1));
    expect(
      find.textContaining('Live ZEC deposit is disabled in this build'),
      findsOneWidget,
    );
    expect(find.text('Live submit disabled'), findsOneWidget);
  });

  testWidgets('starting a ZEC swap sends and submits the deposit tx', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final depositSender = _FakeSwapDepositSender();
    final sessionStore = _FakeSwapSessionStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        depositSender: depositSender,
        sessionStore: sessionStore,
        liveFundsEnabled: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
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
    expect(sessionStore.savedIntents.single.providerSignature, 'sig-live');
    expect(
      sessionStore.savedIntents.single.direction,
      SwapDirection.zecToExternal,
    );
    expect(sessionStore.savedIntents.single.oneClickRecipient, '0xrecipient');
    expect(
      sessionStore.savedIntents.single.oneClickRefundTo,
      't1actualstaging',
    );
    expect(find.text('Send ZEC'), findsWidgets);
    expect(find.text('t1live-deposit'), findsWidgets);
    expect(find.text('ZEC deposit tx hash'), findsOneWidget);
    expect(find.text('Submit ZEC deposit'), findsOneWidget);
    expect(find.text('ZEC deposit confirmed'), findsWidgets);
    expect(find.text('zec-auto-txid'), findsWidgets);
  });

  testWidgets('ZEC swap opens activity before deposit broadcast finishes', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _AwaitingSubmitSwapProvider();
    final depositSender = _DelayedSwapDepositSender();
    final sessionStore = _FakeSwapSessionStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        depositSender: depositSender,
        sessionStore: sessionStore,
        liveFundsEnabled: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
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
    expect(find.byKey(const ValueKey('swap_queue_title')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_activity_detail_modal')),
      findsOneWidget,
    );
    expect(find.text('Swap created in Activity'), findsOneWidget);
    expect(depositSender.requests, hasLength(1));
    expect(swapProvider.submittedDeposits, isEmpty);
    expect(sessionStore.savedIntents, hasLength(1));
    expect(sessionStore.savedIntents.single.depositTxHash, isNull);

    depositSender.completeSend();
    await tester.pumpAndSettle();

    expect(swapProvider.submittedDeposits, hasLength(1));
    expect(sessionStore.savedIntents.last.depositTxHash, 'zec-auto-txid');
    expect(find.text('Confirming deposit'), findsOneWidget);
  });

  testWidgets('ZEC deposit tx hash is checkpointed when submit fails', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider(
      submitDepositError: Exception('submit temporarily unavailable'),
    );
    final depositSender = _FakeSwapDepositSender();
    final sessionStore = _FakeSwapSessionStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        depositSender: depositSender,
        sessionStore: sessionStore,
        liveFundsEnabled: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
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
    expect(
      sessionStore.savedIntents.single.receipt
          .where((field) => field.label == 'Deposit tx')
          .single
          .value,
      'zec-auto-txid',
    );
    expect(find.text('zec-auto-txid'), findsWidgets);
    expect(find.textContaining('Could not send ZEC deposit'), findsOneWidget);
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
    final sessionStore = _FakeSwapSessionStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        depositSender: depositSender,
        sessionStore: sessionStore,
        liveFundsEnabled: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '0.002',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
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
      find.textContaining('Could not send ZEC deposit. Retry once.'),
      findsOneWidget,
    );
    expect(find.textContaining('Insufficient balance'), findsOneWidget);
  });

  testWidgets(
    'hardware ZEC swaps start and wait for Keystone deposit signing',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _FakeSwapProvider();
      final depositSender = _FakeSwapDepositSender();
      final hardwareSigningService = _FakeSwapHardwareSigningService();
      final sessionStore = _FakeSwapSessionStore();

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [
              GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
            ],
          ),
          bootstrap: _hardwareBootstrap,
          swapProvider: swapProvider,
          depositSender: depositSender,
          hardwareSigningService: hardwareSigningService,
          sessionStore: sessionStore,
          liveFundsEnabled: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '0.003',
      );
      await tester.enterText(
        find.byKey(const ValueKey('swap_destination_field')),
        '0xrecipient',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('swap_start_button')),
      );
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
      expect(hardwareSigningService.depositDrafts, ['t1live-deposit']);
      expect(find.byKey(const ValueKey('swap_review_panel')), findsNothing);
      expect(
        find.byKey(const ValueKey('swap_hardware_deposit_action_panel')),
        findsOneWidget,
      );
      expect(find.text('Sign ZEC deposit on Keystone'), findsOneWidget);
    },
  );

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
      final sessionStore = _FakeSwapSessionStore();

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [
              GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
            ],
          ),
          bootstrap: _hardwareBootstrap,
          swapProvider: swapProvider,
          depositSender: depositSender,
          hardwareSigningService: hardwareSigningService,
          sessionStore: sessionStore,
          liveFundsEnabled: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '0.003',
      );
      await tester.enterText(
        find.byKey(const ValueKey('swap_destination_field')),
        '0xrecipient',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('swap_start_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('swap_start_button')));
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
      expect(find.text('Get Signature'), findsNothing);

      proofCompleter.complete(const [7, 8, 9]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Get Signature'), findsOneWidget);
    },
  );

  testWidgets(
    'hardware ZEC signing cancel removes auto-created unsent activity',
    (tester) async {
      await _setDesktopViewport(tester);
      final swapProvider = _FakeSwapProvider();
      final depositSender = _FakeSwapDepositSender();
      final hardwareSigningService = _FakeSwapHardwareSigningService();
      final sessionStore = _FakeSwapSessionStore();

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [
              GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
            ],
          ),
          bootstrap: _hardwareBootstrap,
          swapProvider: swapProvider,
          depositSender: depositSender,
          hardwareSigningService: hardwareSigningService,
          sessionStore: sessionStore,
          liveFundsEnabled: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '0.003',
      );
      await tester.enterText(
        find.byKey(const ValueKey('swap_destination_field')),
        '0xrecipient',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('swap_start_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('swap_start_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(sessionStore.savedIntents, hasLength(1));
      expect(hardwareSigningService.depositDrafts, ['t1live-deposit']);

      await tester.tap(find.text('Reject'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(sessionStore.savedIntents, isEmpty);
      expect(find.text('Sign ZEC deposit on Keystone'), findsNothing);
    },
  );

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
      final sessionStore = _FakeSwapSessionStore();

      await tester.pumpWidget(
        _routerHarness(
          GoRouter(
            initialLocation: '/swap',
            routes: [
              GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
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
          liveFundsEnabled: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '0.003',
      );
      await tester.enterText(
        find.byKey(const ValueKey('swap_destination_field')),
        '0xrecipient',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('swap_review_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('swap_start_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('swap_start_button')));
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

      await tester.tap(find.text('Get Signature'));
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
      expect(find.text('ZEC Deposit Checking'), findsOneWidget);
      expect(
        sessionStore.savedIntents.single.statusError,
        'local storage failed after broadcast',
      );
      expect(
        sessionStore.savedIntents.single.receipt.any(
          (field) =>
              field.label == 'Broadcast status' &&
              field.value == 'local storage failed after broadcast',
        ),
        isTrue,
      );
      expect(find.text('Sign ZEC deposit on Keystone'), findsNothing);
    },
  );

  testWidgets('hardware receive-ZEC swaps start without automatic signing', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final swapProvider = _FakeSwapProvider();
    final depositSender = _FakeSwapDepositSender();
    final hardwareSigningService = _FakeSwapHardwareSigningService();
    final sessionStore = _FakeSwapSessionStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        bootstrap: _hardwareBootstrap,
        swapProvider: swapProvider,
        depositSender: depositSender,
        hardwareSigningService: hardwareSigningService,
        sessionStore: sessionStore,
        liveFundsEnabled: true,
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
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xexternal-refund',
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
    expect(swapProvider.startedQuotes, hasLength(1));
    expect(swapProvider.submittedDeposits, isEmpty);
    expect(sessionStore.savedIntents, hasLength(1));
    expect(
      sessionStore.savedIntents.single.status,
      SwapIntentStatus.awaitingExternalDeposit,
    );
    expect(hardwareSigningService.depositDrafts, isEmpty);
    expect(hardwareSigningService.shieldDrafts, isEmpty);
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
    final sessionStore = _FakeSwapSessionStore();

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/swap',
          routes: [
            GoRoute(path: '/swap', builder: (_, _) => const SwapScreen()),
          ],
        ),
        swapProvider: swapProvider,
        depositSender: depositSender,
        sessionStore: sessionStore,
        liveFundsEnabled: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0xrecipient',
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

Widget _routerHarness(
  GoRouter router, {
  SwapProvider? swapProvider,
  SwapDepositSender? depositSender,
  SwapMaxAmountEstimator? maxAmountEstimator,
  SwapShieldingService? shieldingService,
  SwapHardwareSigningService? hardwareSigningService,
  SwapSessionStore? sessionStore,
  BigInt? spendableBalance,
  Duration? statusPollInterval,
  Duration? shieldStatusPollInterval,
  Duration? priceRefreshInterval,
  ReserveExchangeTransparentAddress? reserveExchangeTransparentAddress,
  ReleaseExchangeTransparentAddress? releaseExchangeTransparentAddress,
  ReleaseUnusedExchangeTransparentAddresses?
  releaseUnusedExchangeTransparentAddresses,
  bool seedPrototypeFixtures = true,
  bool liveFundsEnabled = true,
  AppBootstrapState? bootstrap,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(bootstrap ?? _bootstrap),
      syncProvider.overrideWith(
        () =>
            _FakeSwapSyncNotifier(spendableBalance ?? BigInt.from(10000000000)),
      ),
      receiveAddressServiceProvider.overrideWith(
        _FakeReceiveAddressService.new,
      ),
      swapZecStagingAddressServiceProvider.overrideWith(
        (ref) => SwapZecStagingAddressService(
          loadWalletDbPath: () async => 'wallet.db',
          readNetwork: () => 'main',
          reserveExchangeTransparentAddress:
              reserveExchangeTransparentAddress ??
              ({
                required accountUuid,
                required dbPath,
                required network,
              }) async {
                return rust_wallet.ExchangeTransparentAddressResult(
                  address: 't1actualstaging',
                  transparentChildIndex: 7,
                  exposedAtHeight: BigInt.from(2500000),
                );
              },
          releaseExchangeTransparentAddress:
              releaseExchangeTransparentAddress ??
              ({
                required accountUuid,
                required address,
                required dbPath,
              }) async {
                return false;
              },
          releaseUnusedExchangeTransparentAddresses:
              releaseUnusedExchangeTransparentAddresses ??
              ({required accountUuid, required dbPath}) async {
                return 0;
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
      swapShieldingServiceProvider.overrideWithValue(
        shieldingService ?? _FakeSwapShieldingService.notReady(),
      ),
      swapHardwareSigningServiceProvider.overrideWithValue(
        hardwareSigningService ?? _FakeSwapHardwareSigningService(),
      ),
      swapSessionStoreProvider.overrideWithValue(
        sessionStore ?? _FakeSwapSessionStore(),
      ),
      if (seedPrototypeFixtures) ...[
        swapInitialIntentsProvider.overrideWithValue(previewSwapIntents),
        swapInitialExternalRequestsProvider.overrideWithValue(
          previewExternalRequests,
        ),
      ],
      swapLiveFundsEnabledProvider.overrideWithValue(liveFundsEnabled),
      if (priceRefreshInterval != null)
        swapPriceRefreshIntervalProvider.overrideWithValue(
          priceRefreshInterval,
        ),
      if (statusPollInterval != null)
        swapStatusPollIntervalProvider.overrideWithValue(statusPollInterval),
      if (shieldStatusPollInterval != null)
        swapShieldStatusPollIntervalProvider.overrideWithValue(
          shieldStatusPollInterval,
        ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

Widget _themeHarness(Widget child) {
  return AppTheme(
    data: AppThemeData.light,
    child: Directionality(textDirection: TextDirection.ltr, child: child),
  );
}

class _FakeReceiveAddressService extends ReceiveAddressService {
  _FakeReceiveAddressService(super.ref);

  @override
  Future<String> loadTransparentAddress({required String accountUuid}) async {
    return 't1actualstaging';
  }
}

class _FakeSwapSyncNotifier extends SyncNotifier {
  _FakeSwapSyncNotifier(this.spendableBalance);

  final BigInt spendableBalance;

  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'account-1',
    hasAccountScopedData: true,
    spendableBalance: spendableBalance,
    totalBalance: spendableBalance,
  );
}

class _FakeSwapMaxAmountEstimator implements SwapMaxAmountEstimator {
  _FakeSwapMaxAmountEstimator({BigInt? maxZatoshi})
    : maxZatoshi = maxZatoshi ?? BigInt.zero;

  final BigInt maxZatoshi;
  final requests = <String>[];

  @override
  Future<BigInt> estimateMaxZecSellAmount({required String accountUuid}) async {
    requests.add(accountUuid);
    return maxZatoshi;
  }
}

class _FakeSwapProvider implements SwapProvider {
  _FakeSwapProvider({List<SwapAsset>? supportedAssets, this.submitDepositError})
    : supportedAssets = supportedAssets ?? swapExternalAssets;

  final requests = <SwapQuoteRequest>[];
  final startedQuotes = <SwapQuote>[];
  final statusRequests = <_StatusRequest>[];
  final submittedDeposits = <_SubmittedDeposit>[];
  final List<SwapAsset> supportedAssets;
  final Object? submitDepositError;

  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async {
    return supportedAssets;
  }

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    requests.add(request);
    final estimate = SwapQuote.estimate(
      direction: request.direction,
      externalAsset: request.externalAsset,
      sellAmount: request.sellAmount,
      slippageBps: request.slippageBps ?? 50,
    );
    return SwapQuote(
      direction: estimate.direction,
      sellAsset: estimate.sellAsset,
      receiveAsset: estimate.receiveAsset,
      externalAsset: estimate.externalAsset,
      sellAmount: estimate.sellAmount,
      receiveAmount: estimate.receiveAmount,
      minimumReceiveAmount: estimate.minimumReceiveAmount,
      providerLabel: estimate.providerLabel,
      feeLabel: estimate.feeLabel,
      expiryLabel: estimate.expiryLabel,
      providerQuoteId: 'quote-live',
      providerSignature: 'sig-live',
      depositInstruction: SwapDepositInstruction(
        asset: estimate.sellAsset,
        address: request.direction == SwapDirection.zecToExternal
            ? 't1live-deposit'
            : '0xlive-deposit',
        expiresInLabel: '07:12',
        reuseWarning: 'Do not reuse this address',
        memo: 'memo-live',
      ),
    );
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) async {
    startedQuotes.add(quote);
    return SwapIntentSnapshot.fromQuote(
      quote,
      id: quote.depositInstruction.address,
    );
  }

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    statusRequests.add(
      _StatusRequest(depositAddress: intentId, depositMemo: depositMemo),
    );
    final statusQuote = await quote(
      const SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: 1.5,
        destination: '0xrecipient',
        refundAddress: 't1actualstaging',
      ),
    );
    final base = SwapIntentSnapshot.fromQuote(statusQuote, id: intentId);
    final depositInstruction = statusQuote.depositInstruction;
    return SwapIntentSnapshot(
      id: base.id,
      providerLabel: base.providerLabel,
      pairText: base.pairText,
      sellAmountText: base.sellAmountText,
      receiveEstimateText: base.receiveEstimateText,
      status: SwapIntentStatus.processing,
      nextAction: 'Swap is processing',
      depositInstruction: SwapDepositInstruction(
        asset: depositInstruction.asset,
        address: depositInstruction.address,
        expiresInLabel: depositInstruction.expiresInLabel,
        reuseWarning: depositInstruction.reuseWarning,
        memo: depositMemo ?? depositInstruction.memo,
      ),
    );
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) async {
    submittedDeposits.add(
      _SubmittedDeposit(
        depositAddress: depositAddress,
        txHash: txHash,
        depositMemo: depositMemo,
      ),
    );
    final error = submitDepositError;
    if (error != null) throw error;
    final statusQuote = await quote(
      const SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: 1.5,
        destination: '0xrecipient',
        refundAddress: 't1actualstaging',
      ),
    );
    final base = SwapIntentSnapshot.fromQuote(statusQuote, id: depositAddress);
    return SwapIntentSnapshot(
      id: base.id,
      providerLabel: base.providerLabel,
      pairText: base.pairText,
      sellAmountText: base.sellAmountText,
      receiveEstimateText: base.receiveEstimateText,
      status: SwapIntentStatus.depositObserved,
      nextAction: 'Deposit detected',
      depositInstruction: base.depositInstruction,
    );
  }
}

class _AwaitingSubmitSwapProvider extends _FakeSwapProvider {
  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) async {
    submittedDeposits.add(
      _SubmittedDeposit(
        depositAddress: depositAddress,
        txHash: txHash,
        depositMemo: depositMemo,
      ),
    );
    final statusQuote = await quote(
      const SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: 1.5,
        destination: '0xrecipient',
        refundAddress: 't1actualstaging',
      ),
    );
    final base = SwapIntentSnapshot.fromQuote(statusQuote, id: depositAddress);
    return SwapIntentSnapshot(
      id: base.id,
      providerLabel: base.providerLabel,
      pairText: base.pairText,
      sellAmountText: base.sellAmountText,
      receiveEstimateText: base.receiveEstimateText,
      status: SwapIntentStatus.awaitingDeposit,
      nextAction: 'Waiting for deposit',
      depositInstruction: base.depositInstruction,
    );
  }
}

class _PricingSwapProvider extends _FakeSwapProvider
    implements SwapPricingProvider {
  _PricingSwapProvider(this._rates);

  final List<double> _rates;
  var pricingRequests = 0;
  var sawForcedRefresh = false;

  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({
    bool forceRefresh = false,
  }) async {
    pricingRequests += 1;
    sawForcedRefresh = sawForcedRefresh || forceRefresh;
    final index = pricingRequests - 1;
    final rate = _rates[index < _rates.length ? index : _rates.length - 1];
    return SwapPricingSnapshot(
      usdPrices: {SwapAsset.zec: rate, SwapAsset.usdc: 1},
    );
  }
}

class _FailingQuoteSwapProvider extends _FakeSwapProvider {
  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    requests.add(request);
    throw StateError('provider unavailable');
  }
}

class _DeferredStatusSwapProvider extends _FakeSwapProvider {
  _DeferredStatusSwapProvider(this.snapshot);

  final SwapIntentSnapshot snapshot;
  final statusCompleter = Completer<SwapIntentSnapshot>();

  void completeStatus() {
    if (!statusCompleter.isCompleted) {
      statusCompleter.complete(snapshot);
    }
  }

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    statusRequests.add(
      _StatusRequest(depositAddress: intentId, depositMemo: depositMemo),
    );
    return statusCompleter.future;
  }
}

class _DelayedQuoteSwapProvider extends _FakeSwapProvider {
  final _quoteGate = Completer<void>();

  void completeQuote() {
    if (!_quoteGate.isCompleted) {
      _quoteGate.complete();
    }
  }

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    await _quoteGate.future;
    return super.quote(request);
  }
}

class _FailingStartSwapProvider extends _FakeSwapProvider {
  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) async {
    startedQuotes.add(quote);
    throw StateError('provider rejected start');
  }
}

class _DelayedStartSwapProvider extends _FakeSwapProvider {
  final _startGate = Completer<void>();

  void completeStart() {
    if (!_startGate.isCompleted) {
      _startGate.complete();
    }
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) async {
    startedQuotes.add(quote);
    await _startGate.future;
    return SwapIntentSnapshot.fromQuote(
      quote,
      id: quote.depositInstruction.address,
    );
  }
}

class _LongQuoteSwapProvider extends _FakeSwapProvider {
  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    final estimate = await super.quote(request);
    return SwapQuote(
      direction: estimate.direction,
      sellAsset: estimate.sellAsset,
      receiveAsset: estimate.receiveAsset,
      externalAsset: estimate.externalAsset,
      sellAmount: estimate.sellAmount,
      receiveAmount: estimate.receiveAmount,
      minimumReceiveAmount: estimate.minimumReceiveAmount,
      providerLabel: estimate.providerLabel,
      feeLabel: 'Included in shown rate',
      expiryLabel: estimate.expiryLabel,
      providerQuoteId: 'quote-long-provider-reference',
      providerSignature: 'signature-long-provider-reference',
      sellAmountTextOverride: '12345.678901 ${estimate.sellAsset.symbol}',
      receiveEstimateTextOverride:
          '~175.942100 ${estimate.receiveAsset.symbol}',
      minimumReceiveTextOverride: '174.812300 ${estimate.receiveAsset.symbol}',
      depositInstruction: SwapDepositInstruction(
        asset: estimate.sellAsset,
        address:
            '0xprovider-deposit-address-with-very-long-tail-abcdef1234567890',
        expiresInLabel: estimate.expiryLabel,
        reuseWarning: 'Do not reuse this address',
        memo: 'memo-with-very-long-routing-tag-abcdef1234567890',
      ),
    );
  }
}

class _LongExternalStatusSwapProvider extends _LongQuoteSwapProvider {
  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    statusRequests.add(
      _StatusRequest(depositAddress: intentId, depositMemo: depositMemo),
    );
    final statusQuote = await quote(
      const SwapQuoteRequest(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        sellAmount: 12345.678901,
        destination: 'u1wallet-transparent-staging-shield-prompt-target',
        refundAddress:
            '0xrefund-address-with-a-very-long-source-chain-suffix-abcdef1234567890',
      ),
    );
    return SwapIntentSnapshot(
      id: intentId,
      providerLabel: statusQuote.providerLabel,
      pairText: statusQuote.pairText,
      sellAmountText: statusQuote.sellAmountText,
      receiveEstimateText: statusQuote.receiveEstimateText,
      status: SwapIntentStatus.awaitingExternalDeposit,
      nextAction:
          'Send the external deposit, then submit the source-chain transaction hash after confirmation.',
      depositInstruction: SwapDepositInstruction(
        asset: statusQuote.sellAsset,
        address: intentId,
        expiresInLabel: statusQuote.expiryLabel,
        reuseWarning: 'Do not reuse this address',
        memo:
            depositMemo ??
            'memo-with-a-long-routing-tag-and-provider-reference-9876543210',
      ),
    );
  }
}

class _CompletingExternalStatusSwapProvider
    extends _LongExternalStatusSwapProvider {
  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    final base = await super.getStatus(intentId, depositMemo: depositMemo);
    return SwapIntentSnapshot(
      id: base.id,
      providerLabel: base.providerLabel,
      pairText: base.pairText,
      sellAmountText: base.sellAmountText,
      receiveEstimateText: base.receiveEstimateText,
      status: SwapIntentStatus.complete,
      nextAction: 'Provider reports destination settlement complete',
      depositInstruction: base.depositInstruction,
    );
  }
}

class _ShieldingFailedStatusSwapProvider
    extends _LongExternalStatusSwapProvider {
  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    final base = await super.getStatus(intentId, depositMemo: depositMemo);
    return SwapIntentSnapshot(
      id: base.id,
      providerLabel: base.providerLabel,
      pairText: base.pairText,
      sellAmountText: base.sellAmountText,
      receiveEstimateText: base.receiveEstimateText,
      status: SwapIntentStatus.shieldingFailed,
      nextAction: 'Retry shielding from the staging address',
      depositInstruction: base.depositInstruction,
    );
  }
}

class _StatusRequest {
  const _StatusRequest({required this.depositAddress, this.depositMemo});

  final String depositAddress;
  final String? depositMemo;
}

class _SubmittedDeposit {
  const _SubmittedDeposit({
    required this.depositAddress,
    required this.txHash,
    this.depositMemo,
  });

  final String depositAddress;
  final String txHash;
  final String? depositMemo;
}

class _FakeSwapDepositSender implements SwapDepositSender {
  _FakeSwapDepositSender({this.preflightError});

  final Object? preflightError;
  final preflightRequests = <_DepositSendRequest>[];
  final requests = <_DepositSendRequest>[];

  @override
  Future<BigInt> estimateZecDepositFee({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    preflightRequests.add(
      _DepositSendRequest(
        accountUuid: accountUuid,
        depositAddress: quote.depositInstruction.address,
        sellAmountText: quote.sellAmountText,
      ),
    );
    final error = preflightError;
    if (error != null) throw error;
    return BigInt.from(10000);
  }

  @override
  Future<String> sendZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    requests.add(
      _DepositSendRequest(
        accountUuid: accountUuid,
        depositAddress: quote.depositInstruction.address,
        sellAmountText: quote.sellAmountText,
      ),
    );
    return 'zec-auto-txid';
  }
}

class _DelayedSwapDepositSender extends _FakeSwapDepositSender {
  final _sendGate = Completer<String>();

  void completeSend([String txid = 'zec-auto-txid']) {
    if (!_sendGate.isCompleted) {
      _sendGate.complete(txid);
    }
  }

  @override
  Future<String> sendZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    requests.add(
      _DepositSendRequest(
        accountUuid: accountUuid,
        depositAddress: quote.depositInstruction.address,
        sellAmountText: quote.sellAmountText,
      ),
    );
    return _sendGate.future;
  }
}

class _FakeSwapShieldingService implements SwapShieldingService {
  _FakeSwapShieldingService.notReady()
    : result = null,
      error = const SwapShieldingNotReadyException('not scanned yet'),
      trackStatus = SwapShieldTxStatus.unknown;

  _FakeSwapShieldingService.success(
    this.result, {
    this.trackStatus = SwapShieldTxStatus.pending,
  }) : error = null;

  _FakeSwapShieldingService.failure(this.error)
    : result = null,
      trackStatus = SwapShieldTxStatus.unknown;

  final SwapShieldingResult? result;
  final Object? error;
  final SwapShieldTxStatus trackStatus;
  final requests = <_ShieldingRequest>[];
  final trackRequests = <_ShieldTxRequest>[];

  @override
  Future<SwapShieldingResult> shieldStagingAddress({
    required String accountUuid,
    required String transparentAddress,
  }) async {
    requests.add(
      _ShieldingRequest(
        accountUuid: accountUuid,
        transparentAddress: transparentAddress,
      ),
    );
    final error = this.error;
    if (error != null) throw error;
    return result!;
  }

  @override
  Future<SwapShieldTxState> trackShieldTransaction({
    required String accountUuid,
    required String txHash,
  }) async {
    trackRequests.add(
      _ShieldTxRequest(accountUuid: accountUuid, txHash: txHash),
    );
    return SwapShieldTxState(status: trackStatus);
  }
}

class _FakeSwapHardwareSigningService implements SwapHardwareSigningService {
  _FakeSwapHardwareSigningService({
    this.broadcastStatus = 'broadcasted',
    this.broadcastMessage,
    this.proofCompleter,
  });

  final String broadcastStatus;
  final String? broadcastMessage;
  final Completer<List<int>>? proofCompleter;
  final depositDrafts = <String>[];
  final shieldDrafts = <String>[];
  final proofDrafts = <List<int>>[];
  final broadcasts = <_HardwareBroadcastRequest>[];

  @override
  Future<SwapHardwarePcztDraft> createZecDepositPczt({
    required String accountUuid,
    required SwapPrototypeIntent intent,
  }) async {
    depositDrafts.add(intent.id);
    return SwapHardwarePcztDraft(
      pcztBytes: const [1, 2, 3],
      needsSaplingParams: false,
      feeZatoshi: BigInt.from(10000),
    );
  }

  @override
  Future<SwapHardwarePcztDraft> createShieldPczt({
    required String accountUuid,
    required String transparentAddress,
  }) async {
    shieldDrafts.add(transparentAddress);
    return SwapHardwarePcztDraft(
      pcztBytes: const [4, 5, 6],
      needsSaplingParams: false,
      feeZatoshi: BigInt.from(15000),
      shieldedZatoshi: BigInt.from(200000000),
    );
  }

  @override
  Future<List<String>> encodeSigningUrParts({
    required SwapHardwarePcztDraft draft,
  }) async {
    return const ['ur:zcash-pczt/test'];
  }

  @override
  Future<List<int>> addProofsForSigning({
    required SwapHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    proofDrafts.add(draft.pcztBytes);
    final pending = proofCompleter;
    if (pending != null) return pending.future;
    return const [7, 8, 9];
  }

  @override
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    broadcasts.add(
      _HardwareBroadcastRequest(
        proofs: pcztWithProofsBytes,
        signatures: pcztWithSignaturesBytes,
      ),
    );
    return rust_sync.ExtractAndBroadcastPcztResult(
      txid: 'hardware-broadcast-txid',
      status: broadcastStatus,
      message: broadcastMessage,
    );
  }
}

class _HardwareBroadcastRequest {
  const _HardwareBroadcastRequest({
    required this.proofs,
    required this.signatures,
  });

  final List<int> proofs;
  final List<int> signatures;
}

class _FakeKeystoneScanScreen extends StatelessWidget {
  const _FakeKeystoneScanScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const ValueKey('fake_keystone_signature_done'),
          onPressed: () => Navigator.of(context).pop(<int>[10, 11, 12]),
          child: const Text('Return signature'),
        ),
      ),
    );
  }
}

class _FakeSwapSessionStore implements SwapSessionStore {
  _FakeSwapSessionStore({
    List<SwapPrototypeIntent> initialIntents = const [],
    SwapDraftSnapshot? initialDraft,
  }) : savedIntents = [...initialIntents],
       savedDraft = initialDraft;

  var loadCount = 0;
  var loadDraftCount = 0;
  final saveSnapshots = <List<SwapPrototypeIntent>>[];
  final loadedAccounts = <String>[];
  final savedAccounts = <String>[];
  List<SwapPrototypeIntent> savedIntents;
  SwapDraftSnapshot? savedDraft;

  @override
  Future<List<SwapPrototypeIntent>> loadIntents({
    required String accountUuid,
  }) async {
    loadCount++;
    loadedAccounts.add(accountUuid);
    return [
      for (final intent in savedIntents)
        if (intent.accountUuid == null || intent.accountUuid == accountUuid)
          intent.copyWith(accountUuid: accountUuid),
    ];
  }

  @override
  Future<void> saveIntents({
    required String accountUuid,
    required List<SwapPrototypeIntent> intents,
  }) async {
    savedAccounts.add(accountUuid);
    savedIntents = [
      for (final intent in intents) intent.copyWith(accountUuid: accountUuid),
    ];
    saveSnapshots.add(savedIntents);
  }

  @override
  Future<SwapDraftSnapshot?> loadDraft() async {
    loadDraftCount++;
    return savedDraft;
  }

  @override
  Future<void> saveDraft(SwapDraftSnapshot draft) async {
    savedDraft = draft;
  }
}

SwapPrototypeIntent _persistedIntent({
  required String id,
  required String txHash,
  String? depositAddress,
  SwapIntentStatus status = SwapIntentStatus.processing,
  String? nextAction,
  String accountUuid = 'account-1',
}) {
  final effectiveNextAction = nextAction ?? status.label;
  return SwapPrototypeIntent(
    id: id,
    title: 'ZEC to USDC',
    pair: 'ZEC -> USDC',
    sellAmount: '1.5000 ZEC',
    receiveEstimate: '~105.25 USDC',
    provider: 'NEAR Intents',
    status: status,
    nextAction: effectiveNextAction,
    steps: [
      SwapPrototypeStep(
        label: status.label,
        state: SwapPrototypeStepState.active,
        evidence: effectiveNextAction,
      ),
    ],
    exposure: const [
      SwapPrototypeField(label: 'Deposit address', value: 'persisted-deposit'),
    ],
    receipt: [
      SwapPrototypeField(label: 'Swap id', value: id),
      SwapPrototypeField(label: 'Deposit tx', value: txHash),
    ],
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: depositAddress ?? id,
    depositMemo: 'memo-7',
    depositTxHash: txHash,
    providerQuoteId: 'quote-1',
    providerSignature: 'quote-signature',
    oneClickRecipient: '0xrecipient',
    oneClickRefundTo: 't1refund',
    accountUuid: accountUuid,
  );
}

SwapPrototypeIntent _persistedExternalToZecIntent({
  required String id,
  required String stagingAddress,
}) {
  return SwapPrototypeIntent(
    id: id,
    title: 'USDC to ZEC',
    pair: 'USDC -> ZEC',
    sellAmount: '140.350000 USDC',
    receiveEstimate: '~2.0000 ZEC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.awaitingExternalDeposit,
    nextAction: 'Waiting for the stored source-chain deposit',
    steps: const [
      SwapPrototypeStep(
        label: 'Awaiting external deposit',
        state: SwapPrototypeStepState.active,
        evidence: 'Waiting for the stored source-chain deposit',
      ),
    ],
    exposure: [
      SwapPrototypeField(label: 'ZEC destination', value: stagingAddress),
    ],
    receipt: [
      SwapPrototypeField(label: 'Swap id', value: id),
      SwapPrototypeField(label: 'Receive address', value: stagingAddress),
    ],
    direction: SwapDirection.externalToZec,
    externalAsset: SwapAsset.usdc,
    depositAddress: id,
    depositMemo: 'memo-7',
    providerQuoteId: 'quote-1',
    providerSignature: 'quote-signature',
    oneClickRecipient: stagingAddress,
    oneClickRefundTo: '0xpersisted-refund',
  );
}

SwapPrototypeIntent _persistedShieldingConfirmingIntent({
  required String id,
  required String stagingAddress,
  required String shieldTxHash,
}) {
  return SwapPrototypeIntent(
    id: id,
    title: 'USDC to ZEC',
    pair: 'USDC -> ZEC',
    sellAmount: '140.350000 USDC',
    receiveEstimate: '~2.0000 ZEC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.shieldingConfirming,
    nextAction: 'Waiting for shield transaction confirmation.',
    steps: const [
      SwapPrototypeStep(
        label: 'Quote locked',
        state: SwapPrototypeStepState.done,
        evidence: 'Stored locally',
      ),
      SwapPrototypeStep(
        label: 'External deposit observed',
        state: SwapPrototypeStepState.done,
        evidence: 'Provider delivery observed',
      ),
      SwapPrototypeStep(
        label: 'Shielding confirming',
        state: SwapPrototypeStepState.active,
        evidence: 'Waiting for shield transaction confirmation.',
      ),
    ],
    exposure: [
      SwapPrototypeField(label: 'ZEC destination', value: stagingAddress),
    ],
    receipt: [
      SwapPrototypeField(label: 'Swap id', value: id),
      SwapPrototypeField(label: 'Receive address', value: stagingAddress),
      SwapPrototypeField(label: 'Shield tx', value: shieldTxHash),
    ],
    direction: SwapDirection.externalToZec,
    externalAsset: SwapAsset.usdc,
    depositAddress: id,
    depositMemo: 'memo-7',
    shieldTxHash: shieldTxHash,
    providerQuoteId: 'quote-1',
    providerSignature: 'quote-signature',
    oneClickRecipient: stagingAddress,
    oneClickRefundTo: '0xpersisted-refund',
  );
}

SwapPrototypeIntent _persistedShieldingFailedIntent({
  required String id,
  required String stagingAddress,
}) {
  return SwapPrototypeIntent(
    id: id,
    title: 'USDC to ZEC',
    pair: 'USDC -> ZEC',
    sellAmount: '140.350000 USDC',
    receiveEstimate: '~2.0000 ZEC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.shieldingFailed,
    nextAction: 'Retry shielding from the staging address',
    steps: const [
      SwapPrototypeStep(
        label: 'Quote locked',
        state: SwapPrototypeStepState.done,
        evidence: 'Stored locally',
      ),
      SwapPrototypeStep(
        label: 'External deposit observed',
        state: SwapPrototypeStepState.done,
        evidence: 'Provider delivery observed',
      ),
      SwapPrototypeStep(
        label: 'Shielding failed',
        state: SwapPrototypeStepState.warning,
        evidence: 'Retry wallet shielding',
      ),
    ],
    exposure: [
      SwapPrototypeField(label: 'ZEC destination', value: stagingAddress),
      const SwapPrototypeField(
        label: 'Recovery',
        value: 'retry shield; do not resend external deposit',
      ),
    ],
    receipt: [
      SwapPrototypeField(label: 'Swap id', value: id),
      SwapPrototypeField(label: 'Receive address', value: stagingAddress),
      const SwapPrototypeField(label: 'Status', value: 'shielding failed'),
    ],
    direction: SwapDirection.externalToZec,
    externalAsset: SwapAsset.usdc,
    depositAddress: id,
    depositMemo: 'memo-7',
    providerQuoteId: 'quote-1',
    providerSignature: 'quote-signature',
    oneClickRecipient: stagingAddress,
    oneClickRefundTo: '0xpersisted-refund',
  );
}

class _DepositSendRequest {
  const _DepositSendRequest({
    required this.accountUuid,
    required this.depositAddress,
    required this.sellAmountText,
  });

  final String accountUuid;
  final String depositAddress;
  final String sellAmountText;
}

class _ShieldingRequest {
  const _ShieldingRequest({
    required this.accountUuid,
    required this.transparentAddress,
  });

  final String accountUuid;
  final String transparentAddress;
}

class _ShieldTxRequest {
  const _ShieldTxRequest({required this.accountUuid, required this.txHash});

  final String accountUuid;
  final String txHash;
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
  await tester.pumpAndSettle();
}

Future<void> _openRequestsSurface(WidgetTester tester) async {
  await _sendShortcut(
    tester,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.digit3,
  );
}

Future<void> _openActivityDetail(WidgetTester tester, String intentId) async {
  await _closeActivityDetail(tester);
  final row = find.byKey(ValueKey('swap_queue_row_$intentId'));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row, warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> _closeActivityDetail(WidgetTester tester) async {
  final modal = find.byKey(const ValueKey('swap_activity_detail_modal'));
  if (modal.evaluate().isEmpty) return;
  await tester.tap(
    find.byKey(const ValueKey('swap_activity_detail_close_button')),
    warnIfMissed: false,
  );
  await tester.pumpAndSettle();
}

Future<void> _expandDepositTxHash(WidgetTester tester) async {
  final field = find.byKey(const ValueKey('swap_deposit_tx_hash_field'));
  if (field.evaluate().isNotEmpty) return;
  await tester.ensureVisible(
    find.byKey(const ValueKey('swap_deposit_tx_hash_toggle')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('swap_deposit_tx_hash_toggle')));
  await tester.pumpAndSettle();
}

Future<void> _expandSupportDetails(WidgetTester tester) async {
  final receipt = find.byKey(const ValueKey('swap_receipt_scope_panel'));
  if (receipt.evaluate().isNotEmpty) return;
  final summary = find.byKey(const ValueKey('swap_support_safe_summary_panel'));
  if (summary.evaluate().isNotEmpty) return;
  final bundle = find.byKey(const ValueKey('swap_support_bundle_panel'));
  if (bundle.evaluate().isNotEmpty) return;
  await tester.ensureVisible(
    find.byKey(const ValueKey('swap_support_details_toggle')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('swap_support_details_toggle')));
  await tester.pumpAndSettle();
}

Future<void> _revealSupportBundle(WidgetTester tester) async {
  final bundle = find.byKey(const ValueKey('swap_support_bundle_panel'));
  if (bundle.evaluate().isNotEmpty) return;
  await _expandSupportDetails(tester);
}

Future<void> _tapDepositSubmit(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('swap_deposit_submit_button'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  final modalScroll = find.descendant(
    of: find.byKey(const ValueKey('swap_activity_detail_modal')),
    matching: find.byType(SingleChildScrollView),
  );
  final scroll = modalScroll.evaluate().isNotEmpty
      ? modalScroll.first
      : find.byType(SingleChildScrollView).first;
  await tester.drag(scroll, const Offset(0, -180));
  await tester.pumpAndSettle();
  await tester.tap(button);
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
    activeAddress: 'u1swapprototypeaddress',
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
    activeAddress: 'u1swapprototypeaddress',
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

String _fieldText(WidgetTester tester, String keyValue) {
  final editable = tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(ValueKey(keyValue)),
      matching: find.byType(EditableText),
    ),
  );
  return editable.controller.text;
}
