import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/send/screens/keystone_send_scan_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/keystone_voting_scan_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../support/payment_uri_busy_surface_expectations.dart';

/// Both desktop scan screens point a camera at a QR the Keystone is holding on
/// its own screen. A payment-request card over that is exactly the
/// interruption `paymentUriBusySurfaceProvider` exists to park.
void main() {
  testWidgets('the send scan screen holds the payment-URI busy latch', (
    tester,
  ) async {
    final container = _container();
    await expectPaymentUriBusySurfaceHeldWhileMounted(
      tester,
      container: container,
      host: _host(container),
      surface: const KeystoneSendScanScreen(),
      drainExceptions: true,
    );
  });

  testWidgets('the voting scan screen holds the payment-URI busy latch', (
    tester,
  ) async {
    final container = _container();
    await expectPaymentUriBusySurfaceHeldWhileMounted(
      tester,
      container: container,
      host: _host(container),
      surface: const KeystoneVotingScanScreen(),
      drainExceptions: true,
    );
  });
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      // The desktop shell around the scan pane reads sync state, and the real
      // notifier calls into Rust when the container is disposed.
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
  accounts: [AccountInfo(uuid: 'account-1', name: 'Account1', order: 0)],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1scanscreen',
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
