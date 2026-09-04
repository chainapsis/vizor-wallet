import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_busy_surface_provider.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/home/widgets/keystone_shield_signing_overlay.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';

/// The desktop shield overlay lives on `/home`, so the location-based rules in
/// `payment_uri_drain_policy.dart` cannot see it. Its hold on
/// `paymentUriBusySurfaceProvider` is the only thing stopping an inbound
/// `zcash:` link from disposing it — and the prepared PCZT with it.
void main() {
  testWidgets('holds the payment-URI busy latch while it is mounted', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [appBootstrapProvider.overrideWithValue(_bootstrap())],
    );
    addTearDown(container.dispose);

    expect(container.read(paymentUriBusySurfaceProvider), 0);

    await tester.pumpWidget(_host(container, mountOverlay: true));
    await tester.pump();

    expect(
      container.read(paymentUriBusySurfaceProvider),
      1,
      reason: 'a mounted shield overlay makes the payment-URI drain busy',
    );

    await tester.pumpWidget(_host(container, mountOverlay: false));
    // The release is deferred to a microtask because `dispose` is one of the
    // places Riverpod forbids a synchronous provider write.
    await tester.pump();

    expect(container.read(paymentUriBusySurfaceProvider), 0);
  });
}

Widget _host(ProviderContainer container, {required bool mountOverlay}) {
  return UncontrolledProviderScope(
    container: container,
    child: AppTheme(
      data: AppThemeData.dark,
      child: MaterialApp(
        home: Scaffold(
          body: mountOverlay
              ? KeystoneShieldSigningOverlay(onCancel: () {}, onComplete: () {})
              : const SizedBox.shrink(),
        ),
      ),
    ),
  );
}

const _accountState = AccountState(
  accounts: [AccountInfo(uuid: 'account-1', name: 'Account1', order: 0)],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1shieldoverlay',
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
