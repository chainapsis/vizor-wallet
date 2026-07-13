import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_screen.dart';
import 'package:zcash_wallet/src/features/home/services/pay_introduction_badge_store.dart';
import 'package:zcash_wallet/src/features/home/widgets/pay_floating_badge.dart';
import 'package:zcash_wallet/src/features/pay/screens/pay_screen.dart';
import 'package:zcash_wallet/src/features/receive/screens/receive_screen.dart';
import 'package:zcash_wallet/src/features/send/screens/send_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/pay_selected_asset_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

void main() {
  // Render with the real app fonts instead of the square-glyph test font.
  // The test font is much wider than Geist/Young Serif, which overflows the
  // balance row in ways the running app does not.
  setUpAll(() async {
    final fonts = <String, List<String>>{
      'Geist': [
        'assets/fonts/Geist-Regular.ttf',
        'assets/fonts/Geist-Medium.ttf',
        'assets/fonts/Geist-SemiBold.ttf',
        'assets/fonts/Geist-Bold.ttf',
      ],
      'Young Serif': ['assets/fonts/YoungSerif-Regular.ttf'],
    };
    for (final entry in fonts.entries) {
      final loader = FontLoader(entry.key);
      for (final asset in entry.value) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
  });
  testWidgets(
    'home privacy mode masks desktop balance without duplicate ticker',
    (tester) async {
      await tester.pumpWidget(
        _appHarness(
          '/home',
          privacyModeEnabled: true,
          syncState: SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            orchardBalance: BigInt.from(14_312_000_000),
            spendableBalance: BigInt.from(14_312_000_000),
            totalBalance: BigInt.from(14_312_000_000),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('******'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('home_desktop_balance_fiat_text')),
        findsOneWidget,
      );
      expect(find.text('ZEC'), findsOneWidget);
      expect(find.text('****** ZEC ZEC'), findsNothing);
    },
  );

  testWidgets('home desktop shows fiat balance when pricing is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home_desktop_balance_fiat_text')),
      findsOneWidget,
    );
    expect(find.text(r'$10.02K'), findsOneWidget);

    final colors = AppThemeData.light.colors;
    final fiatText = tester.widget<Text>(
      find.byKey(const ValueKey('home_desktop_balance_fiat_text')),
    );
    expect(fiatText.style?.color, colors.text.homeCard);
    expect(fiatText.style?.fontSize, 14);

    final shieldIcon = tester.widget<AppIcon>(
      find.byKey(const ValueKey('home_desktop_shielded_balance_icon')),
    );
    expect(shieldIcon.color, colors.text.homeCard);

    expect(
      find.byKey(const ValueKey('home_desktop_balance_price_change_text')),
      findsNothing,
    );
  });

  testWidgets('home desktop shows a green positive 24h price change', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        priceChange24hPct: 1.253,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+ 1.25% (24h)'), findsOneWidget);
    final changeText = tester.widget<Text>(
      find.byKey(const ValueKey('home_desktop_balance_price_change_text')),
    );
    expect(
      changeText.style?.color,
      AppThemeData.light.colors.text.positiveStrong,
    );
  });

  testWidgets('home desktop shows a destructive negative 24h price change', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        priceChange24hPct: -0.25852,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('- 0.26% (24h)'), findsOneWidget);
    final changeText = tester.widget<Text>(
      find.byKey(const ValueKey('home_desktop_balance_price_change_text')),
    );
    expect(changeText.style?.color, AppThemeData.light.colors.text.destructive);
  });

  testWidgets('home desktop content tracks pane center on scaled screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 864);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _appHarness(
        '/home',
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final contentFinder = find.byKey(const ValueKey('home_desktop_content'));
    final contentCenter = tester.getCenter(contentFinder).dx;
    final contentTop = tester.getTopLeft(contentFinder).dy;
    const shellPadding = 8.0;
    const sidebarWidth = 256.0;
    const sidebarGap = 8.0;
    const viewportWidth = 1400.0;
    const viewportHeight = 864.0;
    const paneLeft = shellPadding + sidebarWidth + sidebarGap;
    const paneWidth =
        viewportWidth - (shellPadding * 2) - sidebarWidth - sidebarGap;
    const paneCenter = paneLeft + (paneWidth / 2);
    const paneHeight = viewportHeight - (shellPadding * 2);
    const referencePaneHeight = 704.0;
    const referenceContentTop = 48.0;
    const expectedContentTop =
        shellPadding +
        referenceContentTop +
        ((paneHeight - referencePaneHeight) / 2);

    expect(contentCenter, moreOrLessEquals(paneCenter, epsilon: 0.1));
    expect(contentTop, moreOrLessEquals(expectedContentTop, epsilon: 0.1));
  });

  testWidgets('home desktop send action opens send screen', (tester) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home_desktop_send_button')));
    await _pumpUntilPresent(tester, find.byType(SendScreen));

    expect(find.byType(SendScreen), findsOneWidget);
  });

  testWidgets('home desktop send hover uses dark primary label hover color', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        themeMode: ThemeMode.dark,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sendButton = find.byKey(const ValueKey('home_desktop_send_button'));
    final sendText = find.descendant(
      of: sendButton,
      matching: find.text('Send'),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(sendButton));
    await tester.pump();

    final textWidget = tester.widget<Text>(sendText);
    expect(
      textWidget.style?.color,
      AppThemeData.dark.colors.button.primary.labelHover,
    );
  });

  testWidgets('home desktop receive action opens receive screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home_desktop_receive_button')));
    await _pumpUntilPresent(tester, find.byType(ReceiveScreen));

    expect(find.byType(ReceiveScreen), findsOneWidget);
  });

  testWidgets('home desktop pay action opens exact-output pay screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sendRect = tester.getRect(
      find.byKey(const ValueKey('home_desktop_send_button')),
    );
    final receiveRect = tester.getRect(
      find.byKey(const ValueKey('home_desktop_receive_button')),
    );
    final payRect = tester.getRect(
      find.byKey(const ValueKey('home_desktop_pay_button')),
    );
    final payIcon = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('home_desktop_pay_button')),
        matching: find.byType(AppIcon),
      ),
    );
    // Icon-only 60px pay entry per Figma 5407:152492.
    expect(payIcon.size, 20);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('home_desktop_pay_button')),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
    );
    expect(payRect.width, moreOrLessEquals(60, epsilon: 0.1));
    expect(payRect.top, moreOrLessEquals(sendRect.top, epsilon: 0.1));
    expect(payRect.bottom, moreOrLessEquals(sendRect.bottom, epsilon: 0.1));
    expect(receiveRect.left, greaterThan(sendRect.right));
    expect(payRect.left, greaterThan(receiveRect.right));
    expect(find.byType(PayIntroductionBadgeTarget), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home_desktop_pay_button')));
    await _pumpUntilPresent(tester, find.byType(PayScreen));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PayScreen)),
    );
    final state = container.read(swapStateProvider);
    expect(find.byType(PayScreen), findsOneWidget);
    // The wizard opens on the amount-first step.
    expect(find.byKey(const ValueKey('pay_wizard_title')), findsOneWidget);
    expect(find.byKey(const ValueKey('pay_amount_step')), findsOneWidget);
    expect(find.byKey(const ValueKey('pay_amount_input')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pay_recipient_search_field')),
      findsNothing,
    );
    expect(state.direction, SwapDirection.zecToExternal);
    expect(state.quoteMode, SwapQuoteMode.exactOutput);
    expect(state.payMode, isTrue);
    expect(state.amountText, isEmpty);
    expect(state.receiveAmountText, isEmpty);
    expect(state.destinationText, isEmpty);
  });

  testWidgets('home desktop hides pay when swap is disabled', (tester) async {
    final badgeStore = _FakePayIntroductionBadgeStore();
    await tester.pumpWidget(
      _appHarness(
        '/home',
        swapEnabled: false,
        payIntroductionBadgeStore: badgeStore,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home_desktop_pay_button')), findsNothing);
    expect(find.byType(PayIntroductionBadgeTarget), findsNothing);
    expect(badgeStore.markCount, 0);
  });

  testWidgets('home does not consume the treatment without a Pay button', (
    tester,
  ) async {
    final badgeStore = _FakePayIntroductionBadgeStore();
    await tester.pumpWidget(
      _appHarness(
        '/home',
        payIntroductionBadgeStore: badgeStore,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home_desktop_pay_button')), findsNothing);
    expect(find.byType(PayIntroductionBadgeTarget), findsNothing);
    expect(badgeStore.markCount, 0);
  });

  testWidgets('home shows the treatment once and keeps it hidden after Pay', (
    tester,
  ) async {
    final badgeStore = _FakePayIntroductionBadgeStore();
    await tester.pumpWidget(
      _appHarness(
        '/home',
        payIntroductionBadgeStore: badgeStore,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
      ),
    );
    await _pumpUntilPresent(tester, find.text('NEW'));

    expect(find.byType(PayFloatingBadge), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);
    expect(badgeStore.clicked, isTrue);
    expect(badgeStore.markCount, 1);

    await tester.tap(find.byKey(const ValueKey('home_desktop_pay_button')));
    await _pumpUntilPresent(tester, find.byType(PayScreen));
    expect(badgeStore.markCount, 1);
    await tester.tap(find.byKey(const ValueKey('pay_wizard_back_link')));
    for (
      var i = 0;
      i < 20 && find.byType(PayScreen).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(PayScreen), findsNothing);
    expect(find.byType(PayFloatingBadge), findsNothing);
    expect(find.text('Pay in USDC'), findsNothing);
    expect(find.text('NEW'), findsNothing);
    expect(badgeStore.markCount, 1);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('home_desktop_pay_button'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.byType(PayFloatingBadge), findsNothing);
    expect(find.byKey(const ValueKey('pay_floating_badge_glow')), findsNothing);
    expect(find.byKey(const ValueKey('pay_floating_badge_coin')), findsNothing);
    expect(find.text('Pay in USDC'), findsNothing);
    expect(find.text('NEW'), findsNothing);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 121));
    await tester.pump();

    expect(find.byType(PayFloatingBadge), findsNothing);
    expect(find.text('Pay in USDC'), findsNothing);
    expect(find.text('NEW'), findsNothing);
  });

  testWidgets('home keeps the treatment hidden after visiting another page', (
    tester,
  ) async {
    final badgeStore = _FakePayIntroductionBadgeStore();
    await tester.pumpWidget(
      _appHarness(
        '/home',
        payIntroductionBadgeStore: badgeStore,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
      ),
    );
    await _pumpUntilPresent(tester, find.text('NEW'));

    expect(find.byType(PayFloatingBadge), findsOneWidget);
    expect(badgeStore.markCount, 1);

    await tester.tap(find.byKey(const ValueKey('home_desktop_send_button')));
    await _pumpUntilPresent(tester, find.byType(SendScreen));
    await tester.tap(find.byKey(const ValueKey('send_pane_back_button')));
    for (
      var i = 0;
      i < 20 && find.byType(SendScreen).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(SendScreen), findsNothing);
    expect(find.byType(PayFloatingBadge), findsNothing);
    expect(find.text('Pay in USDC'), findsNothing);
    expect(find.text('NEW'), findsNothing);
    expect(badgeStore.markCount, 1);
  });

  testWidgets('home desktop see all action opens activity screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        swapEnabled: true,
        swapActivityStore: _FakeSwapActivityStore([
          _swapActivityRecord(id: 'swap-see-all'),
        ]),
      ),
    );
    await _pumpUntilPresent(tester, find.text('Swapping...'));

    await tester.tap(
      find.byKey(const ValueKey('home_desktop_activity_see_all_button')),
    );
    await _pumpUntilPresent(tester, find.byType(ActivityScreen));

    expect(find.byType(ActivityScreen), findsOneWidget);
  });

  testWidgets('home recent activity keeps untimed pending receives visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        swapEnabled: false,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          recentTransactions: [
            for (var i = 0; i < 5; i++)
              _receivedZecTx(
                txidHex: 'confirmed-$i',
                amountZatoshi: (i + 1) * 10_000_000,
                blockTime: 1_700_000_000 + i,
              ),
            _pendingReceivingTx(txidHex: 'pending-receive'),
          ],
        ),
      ),
    );
    await _pumpUntilPresent(tester, find.text('Receiving ...'));

    expect(find.text('Receiving ...'), findsOneWidget);
    expect(find.text('Received'), findsNWidgets(4));
  });

  testWidgets('home recent activity suppresses the swap-leg Sent duplicate', (
    tester,
  ) async {
    const depositDisplayOrder =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final depositWalletOrder = swapChainTxidToWalletTxidHex(
      depositDisplayOrder,
    )!;

    await tester.pumpWidget(
      _appHarness(
        '/home',
        swapEnabled: true,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          recentTransactions: [_sentZecTx(txidHex: depositWalletOrder)],
        ),
        swapActivityStore: _FakeSwapActivityStore([
          _swapActivityRecord(
            id: 'swap-home-dedupe',
            depositTxHash: depositDisplayOrder,
          ),
        ]),
      ),
    );
    await _pumpUntilPresent(tester, find.text('Swapping...'));

    // The in-flight swap row already carries the signed outgoing amount, so
    // Home hides the standalone Sent broadcast row like the Activity screen.
    expect(find.text('Sent'), findsNothing);
  });

  testWidgets('home recent activity keeps the Sent row for refunded swaps', (
    tester,
  ) async {
    const depositDisplayOrder =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final depositWalletOrder = swapChainTxidToWalletTxidHex(
      depositDisplayOrder,
    )!;

    await tester.pumpWidget(
      _appHarness(
        '/home',
        swapEnabled: true,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          recentTransactions: [_sentZecTx(txidHex: depositWalletOrder)],
        ),
        swapActivityStore: _FakeSwapActivityStore([
          _swapActivityRecord(
            id: 'swap-home-refunded',
            status: SwapIntentStatus.refunded,
            depositTxHash: depositDisplayOrder,
          ),
        ]),
      ),
    );
    await _pumpUntilPresent(tester, find.text('Swap failed'));

    // Refunded rows render unsigned, so the standalone Sent row stays.
    expect(find.text('Sent'), findsOneWidget);
  });

  testWidgets('home desktop shows transparent balance shield action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          transparentBalance: BigInt.from(242_000_000),
          canShieldTransparentBalance: true,
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_554_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home_desktop_transparent_balance_strip')),
      findsOneWidget,
    );
    expect(find.text('Transparent: 2.42 ZEC'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home_shield_balance_button')),
      findsOneWidget,
    );
    expect(find.text('Shield now'), findsOneWidget);
  });

  testWidgets('home desktop keeps recovery notice visible', (tester) async {
    await tester.pumpWidget(
      _appHarness('/home', passwordRotationRecoveryFailed: true),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home_notice_card')), findsOneWidget);
    expect(
      find.text(
        "We couldn't verify the previous password change. Try again or restart Vizor.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('home desktop keeps sync failure notice visible', (tester) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          failure: const SyncFailure(
            kind: SyncFailureKind.network,
            rawMessage: 'network failed',
            userMessage: 'Network connection lost.',
            showSettingsAction: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home_notice_card')), findsOneWidget);
    expect(find.text('Network connection lost.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('home desktop scrolls notice and activity together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 520);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _appHarness(
        '/home',
        swapEnabled: true,
        passwordRotationRecoveryFailed: true,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
        swapActivityStore: _FakeSwapActivityStore([
          for (var index = 0; index < 5; index++)
            _swapActivityRecord(id: 'swap-scroll-$index'),
        ]),
      ),
    );
    await _pumpUntilPresent(tester, find.text('Swapping...'));

    final scrollViewFinder = find.byKey(
      const ValueKey('home_desktop_scroll_view'),
    );
    final scrollableFinder = find.descendant(
      of: scrollViewFinder,
      matching: find.byType(Scrollable),
    );
    final scrollableState = tester.state<ScrollableState>(scrollableFinder);

    expect(tester.getSize(scrollViewFinder).width, greaterThan(420));
    expect(find.byKey(const ValueKey('home_notice_card')), findsOneWidget);
    expect(scrollableState.position.maxScrollExtent, greaterThan(0));

    await tester.drag(scrollViewFinder, const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(scrollableState.position.pixels, greaterThan(0));
  });
}

SwapIntentRecord _swapActivityRecord({
  required String id,
  SwapIntentStatus status = SwapIntentStatus.processing,
  String? depositTxHash,
}) {
  return SwapIntentRecord(
    id: id,
    providerLabel: 'NEAR Intents',
    pairText: 'ZEC -> USDC',
    sellAmountText: '1.0000 ZEC',
    receiveEstimateText: '70.170000 USDC',
    status: status,
    nextAction: status.label,
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: 't1home-deposit',
    depositTxHash: depositTxHash,
    providerQuoteId: 'quote-$id',
    accountUuid: 'account-1',
    createdAt: DateTime.utc(2026, 5, 22, 10),
    updatedAt: DateTime.utc(2026, 5, 22, 10),
  );
}

rust_sync.TransactionInfo _sentZecTx({required String txidHex}) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: BigInt.from(2000000),
    expiredUnmined: false,
    accountBalanceDelta: -100000000,
    fee: BigInt.from(15000),
    blockTime: BigInt.from(1800000000),
    isTransparent: false,
    txKind: 'sent',
    displayAmount: BigInt.from(100000000),
    displayPool: 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}

rust_sync.TransactionInfo _receivedZecTx({
  required String txidHex,
  required int amountZatoshi,
  required int blockTime,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: BigInt.from(2000000),
    expiredUnmined: false,
    accountBalanceDelta: amountZatoshi,
    fee: BigInt.zero,
    blockTime: BigInt.from(blockTime),
    isTransparent: false,
    txKind: 'received',
    displayAmount: BigInt.from(amountZatoshi),
    displayPool: 'shielded',
    createdTime: BigInt.from(blockTime),
  );
}

rust_sync.TransactionInfo _pendingReceivingTx({required String txidHex}) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: BigInt.zero,
    expiredUnmined: false,
    accountBalanceDelta: 123450000,
    fee: BigInt.zero,
    blockTime: BigInt.zero,
    isTransparent: false,
    txKind: 'receiving',
    displayAmount: BigInt.from(123450000),
    displayPool: 'shielded',
    createdTime: BigInt.zero,
  );
}

Widget _appHarness(
  String initialLocation, {
  bool? swapEnabled,
  bool privacyModeEnabled = false,
  bool passwordRotationRecoveryFailed = false,
  double? priceChange24hPct,
  SyncState? syncState,
  SwapActivityStore? swapActivityStore,
  PayIntroductionBadgeStore payIntroductionBadgeStore =
      const _ClickedPayIntroductionBadgeStore(),
  bool payIntroductionBadgePersistenceEnabled = true,
  ThemeMode themeMode = ThemeMode.system,
}) {
  return ProviderScope(
    overrides: [
      zecMarketDataSourceProvider.overrideWithValue(
        _FakeMarketDataSource(priceChange24hPct),
      ),
      appBootstrapProvider.overrideWithValue(
        _bootstrap(
          initialLocation,
          privacyModeEnabled: privacyModeEnabled,
          passwordRotationRecoveryFailed: passwordRotationRecoveryFailed,
          themeMode: themeMode,
        ),
      ),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(syncState ?? _syncedSyncState),
      ),
      payIntroductionBadgeStoreProvider.overrideWithValue(
        payIntroductionBadgeStore,
      ),
      payIntroductionBadgePersistenceEnabledProvider.overrideWithValue(
        payIntroductionBadgePersistenceEnabled,
      ),
      paySelectedAssetStoreProvider.overrideWithValue(
        const _FakePaySelectedAssetStore(),
      ),
      // The coin bob loops forever, which would break pumpAndSettle here;
      // motion itself is covered by pay_floating_badge_test.
      payIntroductionBadgeMotionEnabledProvider.overrideWithValue(false),
      if (swapEnabled != null)
        swapFeatureEnabledProvider.overrideWithValue(swapEnabled),
      swapIntentProvider.overrideWithValue(const _FakeSwapProvider()),
      if (swapActivityStore != null)
        swapActivityStoreProvider.overrideWithValue(swapActivityStore),
    ],
    child: const ZcashWalletApp(),
  );
}

Future<void> _pumpUntilPresent(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

AppBootstrapState _bootstrap(
  String initialLocation, {
  required bool privacyModeEnabled,
  required bool passwordRotationRecoveryFailed,
  required ThemeMode themeMode,
}) {
  return AppBootstrapState(
    initialLocation: initialLocation,
    initialAccountState: const AccountState(
      accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
      activeAccountUuid: 'account-1',
      activeAddress: 'u1testaddress',
    ),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: themeMode,
    privacyModeEnabled: privacyModeEnabled,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: passwordRotationRecoveryFailed,
  );
}

final _syncedSyncState = SyncState(
  accountUuid: 'account-1',
  hasAccountScopedData: true,
);

class _FakeMarketDataSource implements ZecMarketDataSource {
  const _FakeMarketDataSource(this.change24hPct);

  final double? change24hPct;

  @override
  Future<ZecMarketData?> fetchMarketData() async {
    return ZecMarketData(usdPrice: 70, change24hPct: change24hPct);
  }
}

class _ClickedPayIntroductionBadgeStore implements PayIntroductionBadgeStore {
  const _ClickedPayIntroductionBadgeStore();

  @override
  Future<bool> hasClickedPay() async => true;

  @override
  Future<void> markPayClicked() async {}
}

class _FakePaySelectedAssetStore implements PaySelectedAssetStore {
  const _FakePaySelectedAssetStore();

  @override
  Future<SwapAsset?> loadSelectedAsset({required String accountUuid}) async {
    return null;
  }

  @override
  Future<void> saveSelectedAsset({
    required String accountUuid,
    required SwapAsset asset,
  }) async {}
}

class _FakePayIntroductionBadgeStore implements PayIntroductionBadgeStore {
  bool clicked = false;
  int markCount = 0;

  @override
  Future<bool> hasClickedPay() async => clicked;

  @override
  Future<void> markPayClicked() async {
    clicked = true;
    markCount += 1;
  }
}

class _FakeSwapActivityStore implements SwapActivityStore {
  const _FakeSwapActivityStore(this.records);

  final List<SwapIntentRecord> records;

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    return [
      for (final record in records)
        if (record.accountUuid == accountUuid) record,
    ];
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {}

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {}
}

class _FakeSwapProvider implements SwapProvider, SwapPricingProvider {
  const _FakeSwapProvider();

  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async {
    return const [SwapAsset.usdc];
  }

  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({
    bool forceRefresh = false,
  }) async {
    return SwapPricingSnapshot(
      usdPrices: {SwapAsset.zec: 70, SwapAsset.usdc: 1},
    );
  }

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> getStatus(String intentId, {String? depositMemo}) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) {
    throw UnimplementedError();
  }
}
