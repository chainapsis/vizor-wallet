// Scenario tests for when Settings offers NEAR swap privacy, which both the
// desktop and mobile settings rows read through
// `nearSwapPrivacySettingAvailableProvider`.
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';

/// A bootstrap on `network` with both privacy settings saved as on.
AppBootstrapState _bootstrap(String network) => AppBootstrapState(
  initialLocation: '/settings',
  initialAccountState: const AccountState(),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: network,
  rpcEndpointConfig: defaultRpcEndpointConfig(network),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
  enhancePirEnabled: true,
  nearSwapPrivacyEnabled: true,
);

/// A container for `network`, with the swap and service gates overridden
/// when given.
ProviderContainer _container(String network, {bool? swaps, bool? service}) {
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(network)),
      if (swaps != null) swapFeatureEnabledProvider.overrideWithValue(swaps),
      if (service != null)
        enhancePirAvailableProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  /// The row needs both swaps and the private service.
  for (final (swaps, service, shown) in [
    (true, true, true),
    (true, false, false),
    (false, true, false),
    (false, false, false),
  ]) {
    test('swaps $swaps and service $service: row shown $shown', () {
      final container = _container('main', swaps: swaps, service: service);
      expect(container.read(nearSwapPrivacySettingAvailableProvider), shown);
    });
  }

  /// Off mainnet there are no swaps and no private service, so a saved opt-in
  /// neither shows the row nor turns the feature on.
  test('testnet hides the row and keeps a saved opt-in off', () {
    final container = _container('test');
    expect(container.read(nearSwapPrivacySettingAvailableProvider), isFalse);
    expect(container.read(nearSwapPrivacyProvider), isFalse);
  });
}
