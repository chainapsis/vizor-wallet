@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoRouteTransitionMixin;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_shell.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_routes.dart';
import 'package:zcash_wallet/src/features/home/services/pay_introduction_badge_store.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_activity_screen.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_home_screen.dart';
import 'package:zcash_wallet/src/features/pay/screens/mobile/mobile_pay_screen.dart';
import 'package:zcash_wallet/src/features/pay/screens/mobile/mobile_pay_submitted_screen.dart';
import 'package:zcash_wallet/src/features/receive/screens/mobile/mobile_receive_screen.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_navigation.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/pay_selected_asset_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_keystone_sign_screen.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';
import '../../features/swap/support/static_near_intents_swap_provider.dart';

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account1',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1routeraddress',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

GoRouter _router() => GoRouter(
  initialLocation: '/home',
  routes: buildMobileRoutes(entryRoutes: const []),
);

Widget _app(
  GoRouter router, {
  bool swapFeatureEnabled = true,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(_bootstrap()),
    swapFeatureEnabledProvider.overrideWithValue(swapFeatureEnabled),
    // The coin bob loops forever, which would break pumpAndSettle here;
    // motion itself is covered by pay_floating_badge_test.
    payIntroductionBadgeMotionEnabledProvider.overrideWithValue(false),
    // Funded so the home tab shows the Send action used by the push
    // test.
    syncProvider.overrideWith(
      () => FakeSyncNotifier(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(100000000),
        ),
      ),
    ),
    ...overrides,
  ],
  child: MaterialApp.router(
    routerConfig: router,
    builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
  ),
);

void main() {
  testWidgets('tab shell renders all four tabs and switches branches', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_router()));
    await tester.pumpAndSettle();

    expect(find.byType(MobileHomeScreen), findsOneWidget);
    final shellRoute = ModalRoute.of(
      tester.element(find.byType(AppMobileShell)),
    );
    expect(shellRoute, isA<CupertinoRouteTransitionMixin<dynamic>>());
    for (final label in ['Home', 'Swap', 'Activity', 'Settings']) {
      expect(find.bySemanticsLabel(label), findsWidgets);
    }

    await tester.tap(find.bySemanticsLabel('Activity').last);
    await tester.pumpAndSettle();
    expect(find.byType(MobileActivityScreen), findsOneWidget);
    expect(find.byType(MobileHomeScreen), findsNothing);

    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapScreen), findsOneWidget);
  });

  testWidgets('swap tab is hidden when the swap feature is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_router(), swapFeatureEnabled: false));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Swap'), findsNothing);
    for (final label in ['Home', 'Activity', 'Settings']) {
      expect(find.bySemanticsLabel(label), findsWidgets);
    }
  });

  testWidgets('send pushes over the shell with a swipe-back capable page', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_router()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.byType(MobileSendScreen), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.byType(MobileSendScreen)));
    expect(route, isA<CupertinoRouteTransitionMixin<dynamic>>());

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSendScreen), findsNothing);
    expect(find.byType(MobileHomeScreen), findsOneWidget);
  });

  testWidgets('send amount and review routes push Cupertino pages', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    unawaited(
      router.push<void>(
        '/send/amount',
        extra: const MobileSendAmountArgs(
          sendFlowId: 'flow-1',
          recipient: 'u1routeraddress',
          addressType: 'unified',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(MobileSendAmountScreen), findsOneWidget);
    var route = ModalRoute.of(
      tester.element(find.byType(MobileSendAmountScreen)),
    );
    expect(route, isA<CupertinoRouteTransitionMixin<dynamic>>());

    unawaited(
      router.push<void>(
        '/send/review',
        extra: MobileSendReviewDraftArgs(
          sendFlowId: 'flow-1',
          recipient: 'u1routeraddress',
          addressType: 'unified',
          amountText: '0.25',
          feeZatoshi: BigInt.from(10000),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(MobileSendReviewScreen), findsOneWidget);
    route = ModalRoute.of(tester.element(find.byType(MobileSendReviewScreen)));
    expect(route, isA<CupertinoRouteTransitionMixin<dynamic>>());
  });

  testWidgets('swap Keystone signing route pushes a Cupertino page', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(
      _app(
        router,
        overrides: [
          swapHardwareSigningServiceProvider.overrideWithValue(
            const _FakeSwapHardwareSigningService(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    unawaited(
      router.push<void>(
        '/swap/keystone-sign',
        extra: MobileSwapKeystoneSignArgs(intent: _hardwareSwapIntent),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MobileSwapKeystoneSignScreen), findsOneWidget);
    final route = ModalRoute.of(
      tester.element(find.byType(MobileSwapKeystoneSignScreen)),
    );
    expect(route, isA<CupertinoRouteTransitionMixin<dynamic>>());
    expect(route?.opaque, isTrue);
  });

  testWidgets('receive pushes over a Cupertino shell page', (tester) async {
    await tester.pumpWidget(_app(_router()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Receive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(MobileReceiveScreen), findsOneWidget);
    final route = ModalRoute.of(
      tester.element(find.byType(MobileReceiveScreen)),
    );
    expect(route, isA<CupertinoRouteTransitionMixin<dynamic>>());

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(MobileReceiveScreen), findsNothing);
    expect(find.byType(MobileHomeScreen), findsOneWidget);
  });

  testWidgets('payment submitted route pushes a Cupertino page', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    unawaited(router.push<void>('/pay/submitted/intent-123'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(MobilePaySubmittedScreen), findsOneWidget);
    final screen = tester.widget<MobilePaySubmittedScreen>(
      find.byType(MobilePaySubmittedScreen),
    );
    expect(screen.intentId, 'intent-123');
    final route = ModalRoute.of(
      tester.element(find.byType(MobilePaySubmittedScreen)),
    );
    expect(route, isA<CupertinoRouteTransitionMixin<dynamic>>());
  });

  testWidgets('pay route forwards prepared-composer navigation state', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    unawaited(
      router.push<void>(
        '/pay',
        extra: const PayComposerNavigationArgs(preservePreparedComposer: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final screen = tester.widget<MobilePayScreen>(find.byType(MobilePayScreen));
    expect(screen.preservePreparedComposer, isTrue);
  });

  testWidgets('home Pay waits only for its saved live asset', (tester) async {
    final router = _router();
    final savedAsset = SwapAsset.live(
      assetId: 'base-usdc',
      symbol: 'USDC',
      blockchain: 'base',
      decimals: 6,
    );
    final payAssetStore = _DeferredPaySelectedAssetStore(savedAsset);
    final swapProvider = _DeferredSupportedAssetsSwapProvider();
    await tester.pumpWidget(
      _app(
        router,
        overrides: [
          paySelectedAssetStoreProvider.overrideWithValue(payAssetStore),
          swapIntentProvider.overrideWithValue(swapProvider),
          payIntroductionBadgePersistenceEnabledProvider.overrideWithValue(
            false,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_home_pay')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(payAssetStore.loadStarted, isTrue);
    expect(payAssetStore.loadCount, 1);
    expect(swapProvider.loadStarted, isTrue);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    expect(find.byType(MobilePayScreen), findsNothing);

    payAssetStore.completeLoad();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MobileHomeScreen)),
      listen: false,
    );
    expect(container.read(paySelectedAssetProvider), savedAsset);
    expect(container.read(swapStateProvider).payMode, isTrue);
    expect(container.read(swapStateProvider).externalAsset, savedAsset);
    expect(container.read(swapStateProvider).pricingLoading, isTrue);
    expect(find.byType(MobilePayScreen), findsOneWidget);
    final assetSelector = find.byKey(
      const ValueKey('mobile_pay_asset_selector'),
    );
    expect(
      find.descendant(of: assetSelector, matching: find.text('Base')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: assetSelector, matching: find.text('Ethereum')),
      findsNothing,
    );

    await tester.pump();
    expect(container.read(swapStateProvider).externalAsset, savedAsset);
    expect(payAssetStore.loadCount, 1);

    swapProvider.completeSupportedAssets([savedAsset]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(swapStateProvider).pricingLoading, isFalse);
    expect(container.read(swapStateProvider).externalAsset, savedAsset);
  });

  testWidgets(
    'home Pay does not treat a periodic catalog refresh as initial loading',
    (tester) async {
      final router = _router();
      final savedAsset = SwapAsset.live(
        assetId: 'removed-base-usdc',
        symbol: 'USDC',
        blockchain: 'base',
        decimals: 6,
      );
      final payAssetStore = _DeferredPaySelectedAssetStore(savedAsset);
      final swapProvider = _DeferredRefreshSupportedAssetsSwapProvider(const [
        SwapAsset.usdc,
      ]);
      await tester.pumpWidget(
        _app(
          router,
          overrides: [
            paySelectedAssetStoreProvider.overrideWithValue(payAssetStore),
            swapIntentProvider.overrideWithValue(swapProvider),
            swapPriceRefreshIntervalProvider.overrideWithValue(
              const Duration(seconds: 5),
            ),
            payIntroductionBadgePersistenceEnabledProvider.overrideWithValue(
              false,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('mobile_home_pay')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(swapProvider.loadCount, 1);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await tester.pump();
      expect(swapProvider.loadCount, 2);

      payAssetStore.completeLoad();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MobileHomeScreen)),
        listen: false,
      );
      expect(container.read(swapStateProvider).pricingLoading, isTrue);
      expect(container.read(swapStateProvider).externalAsset, SwapAsset.usdc);
      final assetSelector = find.byKey(
        const ValueKey('mobile_pay_asset_selector'),
      );
      expect(
        find.descendant(of: assetSelector, matching: find.text('Ethereum')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: assetSelector, matching: find.text('Base')),
        findsNothing,
      );

      swapProvider.completeRefresh(const [SwapAsset.usdc]);
      await tester.pump();
    },
  );

  testWidgets('home Pay restore does not navigate after leaving Home', (
    tester,
  ) async {
    final router = _router();
    final payAssetStore = _DeferredPaySelectedAssetStore(SwapAsset.sol);
    await tester.pumpWidget(
      _app(
        router,
        overrides: [
          paySelectedAssetStoreProvider.overrideWithValue(payAssetStore),
          payIntroductionBadgePersistenceEnabledProvider.overrideWithValue(
            false,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_home_pay')));
    await tester.pump();
    expect(payAssetStore.loadStarted, isTrue);

    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Home').last);
    await tester.pumpAndSettle();
    expect(find.byType(MobileHomeScreen), findsOneWidget);

    payAssetStore.completeLoad();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(MobileHomeScreen), findsOneWidget);
    expect(find.byType(MobilePayScreen), findsNothing);
  });
}

final _hardwareSwapIntent = SwapIntent(
  id: 'swap-route-hardware',
  pair: 'ZEC -> USDC',
  sellAmount: '0.003 ZEC',
  receiveEstimate: '0.21 USDC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.awaitingDeposit,
  nextAction: 'Deposit ZEC',
  sellAmountBaseUnits: BigInt.from(300000),
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  depositAddress: 't1route-deposit',
  accountUuid: 'account-1',
);

class _FakeSwapHardwareSigningService implements SwapHardwareSigningService {
  const _FakeSwapHardwareSigningService();

  @override
  Future<SwapHardwarePcztDraft> createZecDepositPczt({
    required String accountUuid,
    required SwapIntent intent,
  }) async {
    return SwapHardwarePcztDraft(
      pcztBytes: const [1, 2, 3],
      needsSaplingParams: false,
      feeZatoshi: BigInt.zero,
    );
  }

  @override
  Future<List<String>> encodeSigningUrParts({
    required SwapHardwarePcztDraft draft,
  }) async {
    return const ['ur:zcash-pczt/route-test'];
  }

  @override
  Future<List<int>> addProofsForSigning({
    required SwapHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    return const [4, 5, 6];
  }

  @override
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) {
    throw UnimplementedError();
  }
}

class _DeferredPaySelectedAssetStore implements PaySelectedAssetStore {
  _DeferredPaySelectedAssetStore(this.asset);

  final SwapAsset? asset;
  final _loadCompleter = Completer<void>();
  int loadCount = 0;

  bool get loadStarted => loadCount > 0;

  void completeLoad() => _loadCompleter.complete();

  @override
  Future<SwapAsset?> loadSelectedAsset({required String accountUuid}) async {
    loadCount += 1;
    await _loadCompleter.future;
    return asset;
  }

  @override
  Future<void> saveSelectedAsset({
    required String accountUuid,
    required SwapAsset asset,
  }) async {}
}

class _DeferredSupportedAssetsSwapProvider
    extends StaticNearIntentsSwapProvider {
  final _supportedAssetsCompleter = Completer<List<SwapAsset>>();
  var loadCount = 0;

  bool get loadStarted => loadCount > 0;

  void completeSupportedAssets(List<SwapAsset> assets) {
    _supportedAssetsCompleter.complete(assets);
  }

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() {
    loadCount += 1;
    return _supportedAssetsCompleter.future;
  }
}

class _DeferredRefreshSupportedAssetsSwapProvider
    extends StaticNearIntentsSwapProvider {
  _DeferredRefreshSupportedAssetsSwapProvider(this.initialAssets);

  final List<SwapAsset> initialAssets;
  final _refreshCompleter = Completer<List<SwapAsset>>();
  var loadCount = 0;

  void completeRefresh(List<SwapAsset> assets) {
    _refreshCompleter.complete(assets);
  }

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() {
    loadCount += 1;
    if (loadCount == 1) return Future.value(initialAssets);
    return _refreshCompleter.future;
  }
}
