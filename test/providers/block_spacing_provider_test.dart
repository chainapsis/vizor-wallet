import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/zcash/block_spacing.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/block_spacing_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

void main() {
  test('reads the current network schedule from Rust', () {
    final networks = <String>[];
    final container = _container(({required network}) {
      networks.add(network);
      return rust_wallet.BlockSpacingSchedule(
        nu7ActivationHeight: BigInt.from(3_543_405),
        preNu7BlockSeconds: 75,
        nu7BlockSeconds: 25,
      );
    });
    addTearDown(container.dispose);

    final spacing = container.read(blockSpacingProvider);

    expect(networks, ['main']);
    expect(spacing.nu7ActivationHeight, 3_543_405);
    expect(spacing.preNu7BlockSeconds, 75);
    expect(spacing.nu7BlockSeconds, 25);
  });

  test('keeps pre-NU7 spacing when the schedule is unavailable', () {
    final container = _container(
      ({required network}) => throw StateError('bridge unavailable'),
    );
    addTearDown(container.dispose);

    final spacing = container.read(blockSpacingProvider);

    expect(spacing.nu7ActivationHeight, isNull);
    expect(spacing.preNu7BlockSeconds, BlockSpacing.preNu7.preNu7BlockSeconds);
  });
}

ProviderContainer _container(BlockSpacingScheduleGetter getter) {
  const endpoint = RpcEndpointConfig(
    networkName: 'main',
    lightwalletdUrl: 'https://zec.example:443',
    presetId: kCustomRpcEndpointPresetId,
  );
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        AppBootstrapState(
          initialLocation: '/welcome',
          initialAccountState: const AccountState(),
          initialSyncSnapshot: AppSyncSnapshot.empty,
          network: endpoint.networkName,
          rpcEndpointConfig: endpoint,
          themeMode: ThemeMode.system,
          privacyModeEnabled: false,
          isPasswordConfigured: false,
          isUnlocked: false,
          passwordRotationRecoveryFailed: false,
        ),
      ),
      blockSpacingScheduleGetterProvider.overrideWithValue(getter),
    ],
  );
}
