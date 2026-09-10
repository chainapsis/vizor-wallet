import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_keystone_signing_overlay.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../support/payment_uri_busy_surface_expectations.dart';

/// The desktop ZEC-deposit signing overlay is the swap counterpart of the home
/// shield overlay: it drives a device approval over an animated PCZT QR while
/// `matchedLocation` never leaves the swap pane, so only the hold can tell the
/// payment-URI drain that this surface is mid-session.
void main() {
  testWidgets('the desktop swap signing overlay holds the payment-URI busy '
      'latch', (tester) async {
    final container = _container();
    await expectPaymentUriBusySurfaceHeldWhileMounted(
      tester,
      container: container,
      host: _host(container),
      surface: SwapKeystoneSigningOverlay(
        intent: _hardwareIntent,
        onCancel: () {},
        onDepositBroadcast: (_) async {},
      ),
      drainExceptions: true,
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
  id: 'swap-desktop-hardware',
  pair: 'ZEC -> USDC',
  sellAmount: '0.0030 ZEC',
  receiveEstimate: '0.21 USDC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.awaitingDeposit,
  nextAction: 'Sign and send the ZEC deposit with Keystone.',
  sellAmountBaseUnits: BigInt.from(300000),
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  depositAddress: 't1desktop-deposit',
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
  activeAddress: 'u1swapoverlay',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/swap',
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
