import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

void main() {
  test('loads upgrade status for the current connected endpoint', () async {
    const endpoint = RpcEndpointConfig(
      networkName: 'main',
      lightwalletdUrl: 'https://zec.example:443',
      presetId: kCustomRpcEndpointPresetId,
    );
    final calls = <String>[];
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap(endpoint)),
        chainUpgradeStatusGetterProvider.overrideWithValue(({
          required lightwalletdUrl,
          required network,
        }) async {
          calls.add('$network $lightwalletdUrl');
          return rust_wallet.ChainUpgradeStatus(
            network: network,
            lightwalletdChainName: network,
            tipHeight: BigInt.from(3_500_000),
            lightwalletdReportedHeight: BigInt.from(3_500_000),
            lightwalletdEstimatedHeight: BigInt.from(3_500_000),
            lightwalletdConsensusBranchId: '37a5165b',
            lightwalletdUpgradeName: '',
            lightwalletdUpgradeHeight: BigInt.zero,
            nu63ActivationHeight: BigInt.from(3_428_143),
            ironwoodActiveAtTip: true,
            endpointMatchesNetwork: true,
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    final status = await container.read(chainUpgradeStatusProvider.future);

    expect(calls, ['main https://zec.example:443']);
    expect(status.ironwoodActiveAtTip, isTrue);
    expect(status.endpointMatchesNetwork, isTrue);
  });
}

AppBootstrapState _bootstrap(RpcEndpointConfig endpoint) {
  return AppBootstrapState(
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
  );
}
