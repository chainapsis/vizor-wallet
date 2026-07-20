import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_screen.dart';
import 'package:zcash_wallet/src/features/activity/screens/swap_activity_detail_screen.dart';
import 'package:zcash_wallet/src/features/home/screens/home_screen.dart';
import 'package:zcash_wallet/src/features/home/services/pay_introduction_badge_store.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/send/screens/send_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_provider_config.dart';
import 'package:zcash_wallet/src/features/swap/screens/swap_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import 'fakes/fake_sync_notifier.dart';

final _swapFeatureToggleProvider =
    NotifierProvider<_SwapFeatureToggleNotifier, bool>(
      _SwapFeatureToggleNotifier.new,
    );
final _migrationFlowData = IronwoodMigrationFlowData(
  amountZatoshi: BigInt.from(10_000_000),
  accountName: 'Account 1',
  profilePictureId: 'pfp-03',
);

void main() {
  for (final location in [
    '/send',
    '/send/review',
    '/send/keystone/scan',
    '/send/status',
    '/receive',
    '/pay',
    '/pay/review',
    '/swap',
    '/swap/review',
  ]) {
    testWidgets(
      'Ironwood migration lock redirects $location to migration intro',
      (tester) async {
        await tester.pumpWidget(
          _appHarness(
            location,
            ironwoodPostMigrationState:
                const IronwoodPostMigrationState.required(
                  network: 'main',
                  accountUuid: 'account-1',
                ),
            ironwoodHomeMigrationCtaState:
                const IronwoodHomeMigrationCtaState.start(
                  network: 'main',
                  accountUuid: 'account-1',
                ),
            ironwoodMigrationFlowData: _migrationFlowData,
          ),
        );

        await tester.pumpAndSettle();

        expect(find.byType(IronwoodMigrationFlowScreen), findsOneWidget);
        expect(find.byType(SendScreen), findsNothing);
        expect(find.byType(SwapScreen), findsNothing);
        expect(find.byType(HomeScreen), findsNothing);
      },
    );
  }

  testWidgets('completed Ironwood migration leaves swap route accessible', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/swap',
        ironwoodPostMigrationState: const IronwoodPostMigrationState.complete(
          network: 'main',
          accountUuid: 'account-1',
        ),
      ),
    );

    await _pumpUntilPresent(tester, find.byType(SwapScreen));

    expect(find.byType(SwapScreen), findsOneWidget);
    expect(find.byType(IronwoodMigrationFlowScreen), findsNothing);
  });

  testWidgets('disabled swap route redirects to home', (tester) async {
    await tester.pumpWidget(_appHarness('/swap', swapEnabled: false));
    await tester.pumpAndSettle();

    expect(find.byType(SwapScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('disabled swap activity detail redirects to home', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/activity/swap/swap-disabled',
        swapEnabled: false,
        swapActivityStore: _FakeSwapActivityStore([
          _swapActivityRecord(id: 'swap-disabled'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SwapActivityDetailScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('enabling swap preserves the current route', (tester) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        swapFeatureOverride: swapFeatureEnabledProvider.overrideWith(
          (ref) => ref.watch(_swapFeatureToggleProvider),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Activity').first);
    await tester.pumpAndSettle();
    expect(find.byType(ActivityScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ZcashWalletApp)),
      listen: false,
    );
    container.read(_swapFeatureToggleProvider.notifier).setEnabled(true);
    await tester.pumpAndSettle();

    expect(find.byType(ActivityScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('disabled swap hides home swap activity surface', (tester) async {
    final store = _CountingSwapActivityStore([
      _swapActivityRecord(id: 'swap-hidden-home'),
    ]);

    await tester.pumpWidget(
      _appHarness('/home', swapEnabled: false, swapActivityStore: store),
    );
    await tester.pumpAndSettle();

    expect(store.loadCount, 0);
    expect(find.text('Swapping...'), findsNothing);
  });

  testWidgets('disabled swap hides activity swap surface', (tester) async {
    final store = _CountingSwapActivityStore([
      _swapActivityRecord(id: 'swap-hidden-activity'),
    ]);

    await tester.pumpWidget(
      _appHarness('/activity', swapEnabled: false, swapActivityStore: store),
    );
    await tester.pumpAndSettle();

    expect(store.loadCount, 0);
    expect(find.text('Swapping...'), findsNothing);
  });

  testWidgets('testnet wallet disables swap route and activity loading', (
    tester,
  ) async {
    final store = _CountingSwapActivityStore([
      _swapActivityRecord(id: 'swap-hidden-testnet'),
    ]);

    await tester.pumpWidget(
      _appHarness(
        '/activity/swap/swap-hidden-testnet',
        network: 'test',
        swapActivityStore: store,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SwapActivityDetailScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(store.loadCount, 0);
  });

  testWidgets('home recent activity includes persisted swap activity', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        swapEnabled: true,
        swapActivityStore: _FakeSwapActivityStore([
          _swapActivityRecord(id: 'swap-home-1'),
        ]),
      ),
    );
    await _pumpUntilPresent(tester, find.text('Swapping...'));

    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('Swapping...'), findsOneWidget);
    expect(find.text('-1.0000 ZEC'), findsOneWidget);

    await tester.tap(find.text('Swapping...'));
    await _pumpUntilPresent(tester, find.byType(SwapActivityDetailScreen));

    expect(
      find.byKey(const ValueKey('swap_activity_detail_page')),
      findsOneWidget,
    );
    expect(find.text('Swap in progress...'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back to Home'));
    await _pumpUntilAbsent(tester, find.byType(SwapActivityDetailScreen));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(SwapActivityDetailScreen), findsNothing);
  });

  testWidgets('activity swap detail back returns to activity', (tester) async {
    await tester.pumpWidget(
      _appHarness(
        '/activity',
        swapEnabled: true,
        swapActivityStore: _FakeSwapActivityStore([
          _swapActivityRecord(id: 'swap-activity-1'),
        ]),
      ),
    );
    await _pumpUntilPresent(tester, find.text('Swapping...'));

    await tester.tap(find.text('Swapping...'));
    await _pumpUntilPresent(tester, find.byType(SwapActivityDetailScreen));

    await tester.tap(find.bySemanticsLabel('Back to Activity'));
    await _pumpUntilAbsent(tester, find.byType(SwapActivityDetailScreen));

    expect(find.byType(ActivityScreen), findsOneWidget);
    expect(find.byType(SwapActivityDetailScreen), findsNothing);
  });
}

SwapIntentRecord _swapActivityRecord({required String id}) {
  return SwapIntentRecord(
    id: id,
    providerLabel: 'NEAR Intents',
    pairText: 'ZEC -> USDC',
    sellAmountText: '1.0000 ZEC',
    receiveEstimateText: '70.170000 USDC',
    status: SwapIntentStatus.processing,
    nextAction: 'Swap is processing',
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: 't1home-deposit',
    providerQuoteId: 'quote-$id',
    accountUuid: 'account-1',
    createdAt: DateTime.utc(2026, 5, 22, 10),
    updatedAt: DateTime.utc(2026, 5, 22, 10),
  );
}

Widget _appHarness(
  String initialLocation, {
  bool? swapEnabled,
  Override? swapFeatureOverride,
  String network = 'main',
  SwapActivityStore? swapActivityStore,
  IronwoodHomeMigrationCtaState ironwoodHomeMigrationCtaState =
      const IronwoodHomeMigrationCtaState.hidden(),
  IronwoodPostMigrationState ironwoodPostMigrationState =
      const IronwoodPostMigrationState.inactive(),
  IronwoodMigrationFlowData? ironwoodMigrationFlowData,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrap(initialLocation, network: network),
      ),
      syncProvider.overrideWith(() => FakeSyncNotifier(_syncedSyncState)),
      // The coin bob loops forever, which would break pumpAndSettle here;
      // motion itself is covered by pay_floating_badge_test.
      payIntroductionBadgeMotionEnabledProvider.overrideWithValue(false),
      if (swapFeatureOverride != null)
        swapFeatureOverride
      else if (swapEnabled != null)
        swapFeatureEnabledProvider.overrideWithValue(swapEnabled),
      swapIntentProvider.overrideWithValue(const _FakeSwapProvider()),
      if (swapActivityStore != null)
        swapActivityStoreProvider.overrideWithValue(swapActivityStore),
      ironwoodHomeMigrationCtaProvider.overrideWith((ref) {
        return ironwoodHomeMigrationCtaState;
      }),
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(
        ironwoodHomeMigrationCtaState,
      ),
      ironwoodMigrationRouteCtaProvider.overrideWith((ref) {
        return ironwoodHomeMigrationCtaState;
      }),
      ironwoodPostMigrationStateProvider.overrideWith((ref) {
        return ironwoodPostMigrationState;
      }),
      if (ironwoodMigrationFlowData != null)
        ironwoodMigrationFlowDataProvider.overrideWith((ref) {
          return ironwoodMigrationFlowData;
        }),
    ],
    child: const ZcashWalletApp(),
  );
}

class _SwapFeatureToggleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool enabled) {
    state = enabled;
  }
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

AppBootstrapState _bootstrap(
  String initialLocation, {
  required String network,
}) {
  return AppBootstrapState(
    initialLocation: initialLocation,
    initialAccountState: const AccountState(
      accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
      activeAccountUuid: 'account-1',
      activeAddress: 'u1testaddress',
    ),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: network,
    rpcEndpointConfig: defaultRpcEndpointConfig(network),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

final _syncedSyncState = SyncState(
  accountUuid: 'account-1',
  hasAccountScopedData: true,
);

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

class _CountingSwapActivityStore extends _FakeSwapActivityStore {
  _CountingSwapActivityStore(super.records);

  int loadCount = 0;

  @override
  Future<List<SwapIntentRecord>> loadRecords({required String accountUuid}) {
    loadCount++;
    return super.loadRecords(accountUuid: accountUuid);
  }
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
