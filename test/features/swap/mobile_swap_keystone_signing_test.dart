@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_navigation.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_composer_preferences_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_keystone_sign_screen.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_activity_panel.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

final _hardwareIntent = SwapIntent(
  id: 'swap-mobile-hardware',
  pair: 'ZEC -> USDC',
  sellAmount: '0.0030 ZEC',
  receiveEstimate: '0.21 USDC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.awaitingDeposit,
  nextAction: 'Sign and send the ZEC deposit with Keystone.',
  sellAmountBaseUnits: BigInt.from(300000),
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  depositAddress: 't1mobile-deposit',
  accountUuid: 'account-1',
);

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('hardware ZEC deposit opens mobile Keystone signing route', (
    tester,
  ) async {
    Object? capturedExtra;
    final router = GoRouter(
      initialLocation: '/activity/swap/${_hardwareIntent.id}',
      routes: [
        GoRoute(
          path: '/activity/swap/:swapId',
          builder: (_, state) => SwapActivityDetailSurface(
            intentId: state.pathParameters['swapId'] ?? '',
            returnTarget: SwapActivityReturnTarget.activity,
            layout: SwapActivityDetailLayout.mobile,
          ),
        ),
        GoRoute(
          path: '/swap/keystone-sign',
          builder: (_, state) {
            capturedExtra = state.extra;
            return const SizedBox(
              key: ValueKey('mobile_swap_keystone_sign_route'),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    expect(find.text('Deposit ZEC'), findsOneWidget);
    expect(find.text('Get signature'), findsNothing);

    await tester.tap(find.text('Deposit ZEC'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_swap_keystone_sign_route')),
      findsOneWidget,
    );
    expect(capturedExtra, isA<MobileSwapKeystoneSignArgs>());
    final args = capturedExtra! as MobileSwapKeystoneSignArgs;
    expect(args.intent.id, _hardwareIntent.id);
  });

  testWidgets('mobile Keystone broadcast failure shows toast without submit', (
    tester,
  ) async {
    const failureMessage = 'Keystone signature could not be applied.';
    final swapProvider = _FakeSwapProvider();
    final router = GoRouter(
      initialLocation: '/activity/swap/${_hardwareIntent.id}',
      routes: [
        GoRoute(
          path: '/activity/swap/:swapId',
          builder: (_, state) => SwapActivityDetailSurface(
            intentId: state.pathParameters['swapId'] ?? '',
            returnTarget: SwapActivityReturnTarget.activity,
            layout: SwapActivityDetailLayout.mobile,
          ),
        ),
        GoRoute(
          path: '/swap/keystone-sign',
          builder: (context, _) => Center(
            child: TextButton(
              key: const ValueKey('fail_mobile_swap_keystone_signing'),
              onPressed: () => context.pop(
                const MobileSwapKeystoneSignFailure(failureMessage),
              ),
              child: const Text('Fail signing'),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(_app(router, swapProvider: swapProvider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deposit ZEC'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('fail_mobile_swap_keystone_signing')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(failureMessage), findsOneWidget);
    expect(swapProvider.submitDepositTransactionCalls, 0);
  });
}

Widget _app(GoRouter router, {_FakeSwapProvider? swapProvider}) {
  final activityStore = _FakeSwapActivityStore([_hardwareIntent]);
  final preferencesStore = _FakeSwapComposerPreferencesStore();
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      swapFeatureEnabledProvider.overrideWithValue(true),
      swapInitialIntentsProvider.overrideWithValue([_hardwareIntent]),
      swapActivityStoreProvider.overrideWithValue(activityStore),
      swapComposerPreferencesStoreProvider.overrideWithValue(preferencesStore),
      swapIntentProvider.overrideWithValue(swapProvider ?? _FakeSwapProvider()),
      swapStatusPollIntervalProvider.overrideWithValue(
        const Duration(hours: 1),
      ),
      swapPriceRefreshIntervalProvider.overrideWithValue(
        const Duration(hours: 1),
      ),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            spendableBalance: BigInt.from(100000000),
            totalBalance: BigInt.from(100000000),
          ),
        ),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/activity/swap/${_hardwareIntent.id}',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Keystone',
        order: 0,
        profilePictureId: kDefaultProfilePictureId,
        isHardware: true,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1mobilehardware',
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

class _FakeSwapProvider implements SwapProvider {
  int submitDepositTransactionCalls = 0;

  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async {
    return const [SwapAsset.usdc];
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
  }) async {
    submitDepositTransactionCalls += 1;
    return SwapIntentSnapshot(
      id: _hardwareIntent.id,
      providerLabel: providerLabel,
      pairText: _hardwareIntent.pair,
      sellAmountText: _hardwareIntent.sellAmount,
      receiveEstimateText: _hardwareIntent.receiveEstimate,
      status: SwapIntentStatus.depositObserved,
      nextAction: 'Waiting for swap provider confirmation.',
      originChainTxHash: txHash,
      depositInstruction: const SwapDepositInstruction(
        asset: SwapAsset.zec,
        address: 't1mobile-deposit',
        expiresInLabel: '1 hour',
        reuseWarning: 'Use this deposit address only once.',
      ),
    );
  }
}

class _FakeSwapActivityStore implements SwapActivityStore {
  _FakeSwapActivityStore(List<SwapIntent> initialIntents)
    : _records = [
        for (final intent in initialIntents)
          SwapIntentRecord.fromIntent(intent),
      ];

  List<SwapIntentRecord> _records;

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    return _records;
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {
    _records = records;
  }

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    _records = [];
  }
}

class _FakeSwapComposerPreferencesStore
    implements SwapComposerPreferencesStore {
  @override
  Future<SwapComposerPreferences?> loadPreferences({
    required String accountUuid,
  }) async {
    return null;
  }

  @override
  Future<void> savePreferences({
    required String accountUuid,
    required SwapComposerPreferences preferences,
  }) async {}
}
