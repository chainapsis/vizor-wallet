import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/features/activity/screens/swap_activity_detail_screen.dart';
import 'package:zcash_wallet/src/features/home/screens/home_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_prototype_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_provider_config.dart';
import 'package:zcash_wallet/src/features/swap/screens/swap_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import 'fakes/fake_sync_notifier.dart';

void main() {
  testWidgets('disabled swap route redirects to home', (tester) async {
    await tester.pumpWidget(_appHarness('/swap', swapEnabled: false));
    await tester.pumpAndSettle();

    expect(find.byType(SwapScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('home recent activity includes persisted swap activity', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        swapEnabled: true,
        swapActivityStore: _FakeSwapActivityStore([
          SwapIntentRecord(
            id: 'swap-home-1',
            providerLabel: 'NEAR Intents',
            pairText: 'ZEC -> USDC',
            sellAmountText: '1.0000 ZEC',
            receiveEstimateText: '70.170000 USDC',
            status: SwapIntentStatus.processing,
            nextAction: 'Swap is processing',
            direction: SwapDirection.zecToExternal,
            externalAsset: SwapAsset.usdc,
            depositAddress: 't1home-deposit',
            providerQuoteId: 'quote-home-1',
            accountUuid: 'account-1',
            createdAt: DateTime.utc(2026, 5, 22, 10),
            updatedAt: DateTime.utc(2026, 5, 22, 10),
          ),
        ]),
      ),
    );
    await _pumpUntilPresent(tester, find.text('Swap ZEC to USDC'));

    expect(find.text('Recent Activity'), findsOneWidget);
    expect(find.text('Swap ZEC to USDC'), findsOneWidget);
    expect(find.text('-1.0000 ZEC'), findsOneWidget);

    await tester.tap(find.text('Swap ZEC to USDC'));
    await _pumpUntilPresent(tester, find.byType(SwapActivityDetailScreen));

    expect(find.text('Swap progress'), findsOneWidget);
  });
}

Widget _appHarness(
  String initialLocation, {
  required bool swapEnabled,
  SwapActivityStore? swapActivityStore,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(initialLocation)),
      syncProvider.overrideWith(FakeSyncNotifier.new),
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

AppBootstrapState _bootstrap(String initialLocation) {
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
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
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
}

class _FakeSwapProvider implements SwapProvider {
  const _FakeSwapProvider();

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
  }) {
    throw UnimplementedError();
  }
}
