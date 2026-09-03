@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_keystone_sign_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../support/payment_uri_busy_surface_expectations.dart';

/// The mobile ZEC-deposit signing screen is one session end to end: the
/// deposit QR the Keystone camera reads, then the signed result scanned back.
void main() {
  testWidgets('the mobile swap signing screen holds the payment-URI busy '
      'latch', (tester) async {
    final container = _container();
    await expectPaymentUriBusySurfaceHeldWhileMounted(
      tester,
      container: container,
      host: _host(container),
      surface: MobileSwapKeystoneSignScreen(
        args: MobileSwapKeystoneSignArgs(intent: _hardwareIntent),
      ),
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

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account1',
      order: 0,
      isHardware: true,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1mobileswap',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/swap/keystone-sign',
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
