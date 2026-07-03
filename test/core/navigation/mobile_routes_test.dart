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
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_activity_screen.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_home_screen.dart';
import 'package:zcash_wallet/src/features/receive/screens/mobile/mobile_receive_screen.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_keystone_sign_screen.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

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
