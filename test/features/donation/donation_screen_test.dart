import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/donation/screens/donation_screen.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/send/services/send_proving_key_warmup.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';

void main() {
  testWidgets('balance changes revalidate an existing donation amount', (
    tester,
  ) async {
    final syncNotifier = _MutableSyncNotifier(BigInt.from(100000000));

    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_harness(syncNotifier));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('donation_amount_field')),
      '2',
    );
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
    expect(find.text('Insufficient shielded balance'), findsOneWidget);

    syncNotifier.setBalance(BigInt.from(300000000));
    await tester.pump();
    await tester.pump();

    expect(find.text('Insufficient shielded balance'), findsNothing);
    expect(_continueButton(tester).onPressed, isNotNull);
  });

  testWidgets('USD price changes revalidate a USD donation amount', (
    tester,
  ) async {
    final syncNotifier = _MutableSyncNotifier(BigInt.from(1500000));

    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_harness(syncNotifier));
    await tester.pumpAndSettle();

    await tester.tap(find.text(r'$ 0'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('donation_amount_field')),
      '2',
    );
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
    expect(find.text('Insufficient shielded balance'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DonationScreen)),
    );
    container.read(_testPriceProvider.notifier).setPrice(200);
    await tester.pump();
    await tester.pump();

    expect(find.text('Insufficient shielded balance'), findsNothing);
    expect(_continueButton(tester).onPressed, isNotNull);
  });
}

Widget _harness(_MutableSyncNotifier syncNotifier) {
  final router = GoRouter(
    initialLocation: '/donation',
    routes: [
      GoRoute(path: '/donation', builder: (_, _) => const DonationScreen()),
      GoRoute(path: '/home', builder: (_, _) => const SizedBox.shrink()),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      sendProvingKeyWarmupProvider.overrideWithValue(() {}),
      ironwoodHomeMigrationCtaProvider.overrideWithValue(
        const AsyncValue.data(IronwoodHomeMigrationCtaState.hidden()),
      ),
      zecLiveUsdUnitPriceProvider.overrideWith(
        (ref) => ref.watch(_testPriceProvider),
      ),
      syncProvider.overrideWith(() => syncNotifier),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

AppButton _continueButton(WidgetTester tester) {
  return tester.widget<AppButton>(
    find.byKey(const ValueKey('donation_continue_button')),
  );
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/donation',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1activeaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: kZcashDefaultNetworkName,
  rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _MutableSyncNotifier extends SyncNotifier {
  _MutableSyncNotifier(this.initialBalance);

  final BigInt initialBalance;

  @override
  Future<SyncState> build() async => _stateFor(initialBalance);

  void setBalance(BigInt balance) {
    state = AsyncValue.data(_stateFor(balance));
  }

  SyncState _stateFor(BigInt balance) => SyncState(
    accountUuid: 'account-1',
    hasAccountScopedData: true,
    spendableBalance: balance,
    displaySpendableBalance: balance,
    displaySpendableFreshness: SpendableBalanceFreshness.lastCompletedSync,
  );
}

final _testPriceProvider = NotifierProvider<_TestPriceNotifier, double?>(
  _TestPriceNotifier.new,
);

class _TestPriceNotifier extends Notifier<double?> {
  @override
  double? build() => 100;

  void setPrice(double price) => state = price;
}
