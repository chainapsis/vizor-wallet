@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_keystone_shield_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_keystone_sign_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../support/payment_uri_busy_surface_expectations.dart';

/// The other two mobile hardware-signing routes hold the latch for their whole
/// lifetime, like `/send/keystone-sign`: a card's Review or Edit would `go()`
/// away and dispose the signing screen mid-round.
void main() {
  testWidgets('the mobile swap signing screen holds the payment-URI busy '
      'latch', (tester) async {
    final container = _container();
    await expectPaymentUriBusySurfaceHeldWhileMounted(
      tester,
      container: container,
      host: _host(container),
      surface: MobileSwapKeystoneSignScreen(
        args: MobileSwapKeystoneSignArgs(intent: _hardwareSwapIntent),
      ),
      drainExceptions: true,
      postUnmountSettle: const Duration(seconds: 2),
    );
  });

  testWidgets('the mobile shield signing screen holds the payment-URI busy '
      'latch', (tester) async {
    final container = _container();
    await expectPaymentUriBusySurfaceHeldWhileMounted(
      tester,
      container: container,
      host: _host(container),
      surface: const MobileKeystoneShieldScreen(),
      drainExceptions: true,
      postUnmountSettle: const Duration(seconds: 2),
    );
  });
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(FakeSyncNotifier.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget Function(Widget) _host(ProviderContainer container) =>
    (child) => UncontrolledProviderScope(
      container: container,
      child: AppTheme(
        data: AppThemeData.dark,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Keystone',
      order: 0,
      isHardware: true,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1keystonemobile',
);

final _hardwareSwapIntent = SwapIntent(
  id: 'swap-mobile-hardware',
  pair: 'ZEC -> USDC',
  sellAmount: '0.003 ZEC',
  receiveEstimate: '0.21 USDC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.awaitingDeposit,
  nextAction: 'Deposit ZEC',
  sellAmountBaseUnits: BigInt.from(300000),
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  depositAddress: 't1mobile-deposit',
  accountUuid: 'account-1',
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
