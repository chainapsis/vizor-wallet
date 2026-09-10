import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/home/widgets/keystone_shield_signing_overlay.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_keystone_signing_overlay.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../support/payment_uri_busy_surface_expectations.dart';

/// The two desktop Keystone signing sessions that own no route of their own:
/// transparent shielding signs over `/home`, a hardware swap deposit over the
/// swap activity pane. Both show the animated signing QR the device is
/// reading, so a payment-request card landing on top would scrim it — and
/// answering the card navigates away and disposes the signing flow. The
/// overlays hold the latch for their whole mounted lifetime, like the
/// route-owning scan screens do.
void main() {
  testWidgets('the shield signing overlay holds the payment-URI busy latch', (
    tester,
  ) async {
    final container = _container();
    await expectPaymentUriBusySurfaceHeldWhileMounted(
      tester,
      container: container,
      host: _host(container),
      surface: KeystoneShieldSigningOverlay(onCancel: () {}, onComplete: () {}),
      // Preparing the PCZT calls into Rust, which is not running here; the
      // failure lands in the overlay's own error state and says nothing about
      // the latch.
      drainExceptions: true,
    );
  });

  testWidgets('the swap signing overlay holds the payment-URI busy latch', (
    tester,
  ) async {
    final container = _container();
    await expectPaymentUriBusySurfaceHeldWhileMounted(
      tester,
      container: container,
      host: _host(container),
      surface: SwapKeystoneSigningOverlay(
        intent: _hardwareSwapIntent,
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
      // Both overlays read sync state, and the real notifier calls into Rust
      // when the container is disposed.
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
  activeAddress: 'u1keystoneoverlay',
);

final _hardwareSwapIntent = SwapIntent(
  id: 'swap-overlay-hardware',
  pair: 'ZEC -> USDC',
  sellAmount: '0.003 ZEC',
  receiveEstimate: '0.21 USDC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.awaitingDeposit,
  nextAction: 'Deposit ZEC',
  sellAmountBaseUnits: BigInt.from(300000),
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  depositAddress: 't1overlay-deposit',
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
