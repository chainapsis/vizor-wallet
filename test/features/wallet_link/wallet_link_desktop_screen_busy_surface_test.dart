import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/wallet_link/models/wallet_link_models.dart';
import 'package:zcash_wallet/src/features/wallet_link/screens/wallet_link_desktop_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../support/payment_uri_busy_surface_expectations.dart';

/// The pairing QR here is live in the same sense a Keystone signing QR is: a
/// phone's camera is reading it while the transfer runs. A payment-request
/// card would scrim it mid-pairing, so the screen holds the latch for its
/// whole lifetime rather than for one phase of it.
void main() {
  testWidgets('the desktop wallet-link screen holds the payment-URI busy '
      'latch', (tester) async {
    final container = _container();
    await expectPaymentUriBusySurfaceHeldWhileMounted(
      tester,
      container: container,
      host: _host(container),
      // A ready pairing session — the state in which the QR is on screen and
      // a phone is scanning it.
      surface: const WalletLinkDesktopScreen(
        previewState: WalletLinkState(
          phase: WalletLinkPhase.ready,
          qrPayload: 'vizor-link-preview-payload',
          remaining: Duration(minutes: 4),
        ),
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

const _accountState = AccountState(
  accounts: [AccountInfo(uuid: 'account-1', name: 'Account1', order: 0)],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1walletlink',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/settings/link-mobile',
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
