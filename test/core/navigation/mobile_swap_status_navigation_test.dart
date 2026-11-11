@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_shell.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_destinations.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_exit_back_guard.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_routes.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_activity_screen.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_swap_activity_detail_screen.dart';
import 'package:zcash_wallet/src/features/pay/screens/mobile/mobile_pay_submitted_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_navigation.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_review_screen.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

void main() {
  for (final direction in SwapDirection.values) {
    for (final back in ['button', 'swipe', 'system']) {
      testWidgets(
        'started ${direction.name} swap returns to composer by $back',
        (tester) async {
          final router = _router('/swap');
          await _pumpApp(tester, router, _SwapNotifier(direction: direction));
          unawaited(router.push<void>('/swap/review'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('swap_start_button')));
          await tester.pumpAndSettle();

          final screen = find.byType(MobileSwapActivityDetailScreen);
          expect(screen, findsOneWidget);
          expect(mobileVisiblePath(router), '/activity/swap/navigation-intent');
          final route = ModalRoute.of(tester.element(screen))!;
          expect(route.popGestureEnabled, isTrue);
          expect(router.canPop(), isTrue);
          expect(
            find.byType(AppMobileShell, skipOffstage: false),
            findsOneWidget,
          );
          expect(
            find.byType(MobileSwapReviewScreen, skipOffstage: false),
            findsNothing,
          );

          if (back == 'button') {
            await tester.tap(find.bySemanticsLabel('Back'));
          } else if (back == 'swipe') {
            // A cancelled gesture must leave the same receipt and stack intact.
            final gesture = await tester.startGesture(const Offset(1, 400));
            await gesture.moveBy(const Offset(35, 0));
            await tester.pump(const Duration(milliseconds: 100));
            await gesture.cancel();
            await tester.pumpAndSettle();
            expect(screen, findsOneWidget);
            expect(router.canPop(), isTrue);
            await tester.dragFrom(const Offset(1, 400), const Offset(360, 0));
          } else {
            await tester.binding.handlePopRoute();
          }
          await tester.pumpAndSettle();
          expect(find.byType(MobileSwapScreen), findsOneWidget);
          expect(router.canPop(), isFalse);
          expect(mobileVisiblePath(router), '/swap');
          expect(
            find.byKey(const ValueKey('mobile_exit_back_hint_text')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('Pay replaces review and submitted before returning to Pay', (
    tester,
  ) async {
    final router = _router('/pay');
    await _pumpApp(tester, router, _SwapNotifier(payMode: true));
    unawaited(router.push<void>('/pay/review'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_review_confirm_button')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MobilePaySubmittedScreen), findsOneWidget);
    expect(
      find.byType(MobileSwapReviewScreen, skipOffstage: false),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('pay_submitted_activity')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapActivityDetailScreen), findsOneWidget);
    expect(
      find.byType(MobilePaySubmittedScreen, skipOffstage: false),
      findsNothing,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(mobileVisiblePath(router), '/pay');
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final origin in ['/home', '/activity']) {
    testWidgets('existing activity receipt returns to $origin', (tester) async {
      final router = _router(origin);
      await _pumpApp(tester, router, _SwapNotifier());
      unawaited(
        router.push<void>(
          swapActivityDetailUri(
            intentId: 'navigation-intent',
            returnTarget: origin == '/home'
                ? SwapActivityReturnTarget.home
                : SwapActivityReturnTarget.activity,
          ).toString(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(1, 400), const Offset(360, 0));
      await tester.pumpAndSettle();
      expect(mobileVisiblePath(router), origin);
      expect(router.canPop(), isFalse);
      if (origin == '/activity') {
        expect(find.byType(MobileActivityScreen), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final target in SwapActivityReturnTarget.values) {
    for (final systemBack in [false, true]) {
      testWidgets('root receipt returns to ${target.name} '
          '(${systemBack ? "system" : "button"})', (tester) async {
        final router = _router(
          swapActivityDetailUri(
            intentId: 'navigation-intent',
            returnTarget: target,
          ).toString(),
        );
        await _pumpApp(tester, router, _SwapNotifier());
        expect(router.canPop(), isFalse);
        if (systemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.bySemanticsLabel('Back'));
        }
        await tester.pumpAndSettle();
        expect(mobileVisiblePath(router), target.path);
        expect(find.byType(MobileSwapActivityDetailScreen), findsNothing);
        expect(
          find.byKey(const ValueKey('mobile_exit_back_hint_text')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}

GoRouter _router(String initialLocation) {
  final router = GoRouter(
    initialLocation: initialLocation,
    initialExtra: initialLocation == '/pay'
        ? const PayComposerNavigationArgs(preservePreparedComposer: true)
        : null,
    routes: buildMobileRoutes(entryRoutes: const []),
  );
  addTearDown(router.dispose);
  return router;
}

Future<void> _pumpApp(
  WidgetTester tester,
  GoRouter router,
  _SwapNotifier notifier,
) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dispatcher = MobileExitBackDispatcher(
    exitBackGuard: MobileExitBackGuard(platform: TargetPlatform.android),
    navigatorKey: router.routerDelegate.navigatorKey,
    canPop: router.canPop,
    currentLocation: () => mobileVisiblePath(router),
  );
  addTearDown(dispatcher.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap),
        swapFeatureEnabledProvider.overrideWithValue(true),
        swapStateProvider.overrideWith(() => notifier),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            SyncState(
              accountUuid: 'account-1',
              hasAccountScopedData: true,
              orchardBalance: BigInt.from(100000000),
              spendableBalance: BigInt.from(100000000),
            ),
          ),
        ),
      ],
      child: MaterialApp.router(
        localizationsDelegates: appLocalizationsDelegates,
        routeInformationProvider: router.routeInformationProvider,
        routeInformationParser: router.routeInformationParser,
        routerDelegate: router.routerDelegate,
        backButtonDispatcher: dispatcher,
        onNavigationNotification: dispatcher.handleNavigationNotification,
        builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/swap',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Account1',
        order: 0,
        profilePictureId: kDefaultProfilePictureId,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1navigation',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _SwapNotifier extends SwapNotifier {
  _SwapNotifier({
    this.direction = SwapDirection.zecToExternal,
    this.payMode = false,
  });
  final SwapDirection direction;
  final bool payMode;

  @override
  SwapState build() => SwapState(
    direction: direction,
    amountText: '0.003',
    receiveAmountText: '',
    destinationText: '0xrecipient',
    externalAsset: SwapAsset.usdc,
    reviewVisible: true,
    intents: [_intent],
    payMode: payMode,
    reviewQuote: SwapQuote.estimate(
      direction: direction,
      externalAsset: SwapAsset.usdc,
      sellAmount: 0.003,
      providerLabel: 'NEAR Intents',
    ),
    reviewAddressPlan: SwapAddressPlan(
      direction: direction,
      externalAsset: SwapAsset.usdc,
      userExternalAddress: '0xrecipient',
      walletZecAddress: 'u1navigation',
      oneClickRecipient: '0xrecipient',
      oneClickRefundTo: 'u1navigation',
    ),
    reviewAccountUuid: 'account-1',
  );

  SwapIntent get _intent => SwapIntent(
    id: 'navigation-intent',
    pair: 'ZEC -> USDC',
    sellAmount: '0.003 ZEC',
    receiveEstimate: '0.21 USDC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.complete,
    nextAction: 'Swap completed.',
    direction: direction,
    externalAsset: SwapAsset.usdc,
    accountUuid: 'account-1',
    depositTxHash: 'deposit-txid',
    payMode: payMode,
  );

  @override
  Future<SwapStartResult?> startIntent() async {
    state = state.copyWith(reviewVisible: false, clearReview: true);
    return const SwapStartedActivity('navigation-intent');
  }

  @override
  void selectIntent(String intentId) {
    state = state.copyWith(selectedIntentId: intentId);
  }

  @override
  Future<void> refreshSelectedIntentStatus() async {}
}
