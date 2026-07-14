import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loads upgrade status for the current connected endpoint', () async {
    const endpoint = RpcEndpointConfig(
      networkName: 'main',
      lightwalletdUrl: 'https://zec.example:443',
      presetId: kCustomRpcEndpointPresetId,
    );
    final calls = <String>[];
    final container = _container(
      endpoint: endpoint,
      getChainUpgradeStatus:
          ({required lightwalletdUrl, required network}) async {
            calls.add('$network $lightwalletdUrl');
            return _fullStatus(
              network: network,
              lightwalletdUrl: lightwalletdUrl,
              tipHeight: 3_500_000,
              ironwoodActive: true,
            );
          },
    );
    addTearDown(container.dispose);

    final status = await container.read(chainUpgradeStatusProvider.future);

    expect(calls, ['main https://zec.example:443']);
    expect(status.endpointUrl, 'https://zec.example:443');
    expect(status.ironwoodActiveAtTip, isTrue);
    expect(status.endpointMatchesNetwork, isTrue);
    expect(status.hasLightwalletdMetadata, isTrue);
  });

  test('cached active status skips the full lightwalletd fetch', () async {
    const endpoint = RpcEndpointConfig(
      networkName: 'main',
      lightwalletdUrl: 'https://zec.example:443',
      presetId: kCustomRpcEndpointPresetId,
    );
    final store = _FakeIronwoodActivationStore({'main'});
    var fullFetches = 0;
    final container = _container(
      endpoint: endpoint,
      store: store,
      getChainUpgradeStatus:
          ({required lightwalletdUrl, required network}) async {
            fullFetches += 1;
            return _fullStatus(
              network: network,
              lightwalletdUrl: lightwalletdUrl,
              tipHeight: 3_500_000,
              ironwoodActive: true,
            );
          },
    );
    addTearDown(container.dispose);

    final status = await container.read(chainUpgradeStatusProvider.future);

    expect(fullFetches, 0);
    expect(status.ironwoodActiveAtTip, isTrue);
    expect(status.tipHeight, BigInt.zero);
    expect(status.hasLightwalletdMetadata, isFalse);
  });

  test(
    'refreshAtTip updates activation status without a full refetch',
    () async {
      const endpoint = RpcEndpointConfig(
        networkName: 'main',
        lightwalletdUrl: 'https://zec.example:443',
        presetId: kCustomRpcEndpointPresetId,
      );
      var fullFetches = 0;
      final tipRefreshes = <BigInt>[];
      final store = _FakeIronwoodActivationStore();
      final container = _container(
        endpoint: endpoint,
        store: store,
        getChainUpgradeStatus:
            ({required lightwalletdUrl, required network}) async {
              fullFetches += 1;
              return _fullStatus(
                network: network,
                lightwalletdUrl: lightwalletdUrl,
                tipHeight: 3_400_000,
                ironwoodActive: false,
              );
            },
        getChainUpgradeStatusAtHeight:
            ({required network, required tipHeight}) async {
              tipRefreshes.add(tipHeight);
              return _activationStatus(
                network: network,
                tipHeight: tipHeight,
                ironwoodActive: true,
              );
            },
      );
      addTearDown(container.dispose);

      final initial = await container.read(chainUpgradeStatusProvider.future);
      expect(initial.ironwoodActiveAtTip, isFalse);

      await container
          .read(chainUpgradeStatusProvider.notifier)
          .refreshAtTip(BigInt.from(3_500_000));
      final refreshed = container.read(chainUpgradeStatusProvider).value!;

      expect(fullFetches, 1);
      expect(tipRefreshes, [BigInt.from(3_500_000)]);
      expect(store.activeNetworks, contains('main'));
      expect(refreshed.tipHeight, BigInt.from(3_500_000));
      expect(refreshed.ironwoodActiveAtTip, isTrue);
      expect(refreshed.hasLightwalletdMetadata, isTrue);
    },
  );

  test('cached active refreshAtTip skips the Rust activation check', () async {
    const endpoint = RpcEndpointConfig(
      networkName: 'main',
      lightwalletdUrl: 'https://zec.example:443',
      presetId: kCustomRpcEndpointPresetId,
    );
    final store = _FakeIronwoodActivationStore({'main'});
    var tipRefreshes = 0;
    final container = _container(
      endpoint: endpoint,
      store: store,
      getChainUpgradeStatus:
          ({required lightwalletdUrl, required network}) async {
            throw StateError('full fetch should not run');
          },
      getChainUpgradeStatusAtHeight:
          ({required network, required tipHeight}) async {
            tipRefreshes += 1;
            return _activationStatus(
              network: network,
              tipHeight: tipHeight,
              ironwoodActive: false,
            );
          },
    );
    addTearDown(container.dispose);

    final initial = await container.read(chainUpgradeStatusProvider.future);
    expect(initial.ironwoodActiveAtTip, isTrue);

    await container
        .read(chainUpgradeStatusProvider.notifier)
        .refreshAtTip(BigInt.from(3_600_000));
    final refreshed = container.read(chainUpgradeStatusProvider).value!;

    expect(tipRefreshes, 0);
    expect(refreshed.tipHeight, BigInt.from(3_600_000));
    expect(refreshed.ironwoodActiveAtTip, isTrue);
  });

  test('full fetch active status is cached for the network', () async {
    const endpoint = RpcEndpointConfig(
      networkName: 'main',
      lightwalletdUrl: 'https://zec.example:443',
      presetId: kCustomRpcEndpointPresetId,
    );
    final store = _FakeIronwoodActivationStore();
    final container = _container(
      endpoint: endpoint,
      store: store,
      getChainUpgradeStatus:
          ({required lightwalletdUrl, required network}) async {
            return _fullStatus(
              network: network,
              lightwalletdUrl: lightwalletdUrl,
              tipHeight: 3_500_000,
              ironwoodActive: true,
            );
          },
    );
    addTearDown(container.dispose);

    await container.read(chainUpgradeStatusProvider.future);

    expect(store.activeNetworks, contains('main'));
  });

  test(
    'same-endpoint tip refresh does not downgrade observed activation',
    () async {
      const endpoint = RpcEndpointConfig(
        networkName: 'main',
        lightwalletdUrl: 'https://zec.example:443',
        presetId: kCustomRpcEndpointPresetId,
      );
      final container = _container(
        endpoint: endpoint,
        getChainUpgradeStatus:
            ({required lightwalletdUrl, required network}) async {
              return _fullStatus(
                network: network,
                lightwalletdUrl: lightwalletdUrl,
                tipHeight: 3_500_000,
                ironwoodActive: true,
              );
            },
        getChainUpgradeStatusAtHeight:
            ({required network, required tipHeight}) async {
              return _activationStatus(
                network: network,
                tipHeight: tipHeight,
                ironwoodActive: false,
              );
            },
      );
      addTearDown(container.dispose);

      final initial = await container.read(chainUpgradeStatusProvider.future);
      expect(initial.ironwoodActiveAtTip, isTrue);

      await container
          .read(chainUpgradeStatusProvider.notifier)
          .refreshAtTip(BigInt.from(3_400_000));
      final refreshed = container.read(chainUpgradeStatusProvider).value!;

      expect(refreshed.tipHeight, BigInt.from(3_400_000));
      expect(refreshed.ironwoodActiveAtTip, isTrue);
    },
  );

  test(
    'SharedPreferences store keeps active flags separated by network',
    () async {
      const store = SharedPreferencesIronwoodActivationStore();

      await store.markActiveSeen('main');

      expect(await store.isActiveSeen('main'), isTrue);
      expect(await store.isActiveSeen('test'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(ironwoodActiveSeenStorageKey('main')), isTrue);
      expect(prefs.getBool(ironwoodActiveSeenStorageKey('test')), isNull);
    },
  );
}

ProviderContainer _container({
  required RpcEndpointConfig endpoint,
  required ChainUpgradeStatusGetter getChainUpgradeStatus,
  ChainUpgradeStatusAtHeightGetter? getChainUpgradeStatusAtHeight,
  IronwoodActivationStore? store,
}) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(endpoint)),
      chainUpgradeStatusGetterProvider.overrideWithValue(getChainUpgradeStatus),
      ironwoodActivationStoreProvider.overrideWithValue(
        store ?? _FakeIronwoodActivationStore(),
      ),
      chainUpgradeStatusAtHeightGetterProvider.overrideWithValue(
        getChainUpgradeStatusAtHeight ??
            (({required network, required tipHeight}) async =>
                _activationStatus(
                  network: network,
                  tipHeight: tipHeight,
                  ironwoodActive: false,
                )),
      ),
    ],
  );
}

class _FakeIronwoodActivationStore implements IronwoodActivationStore {
  _FakeIronwoodActivationStore([Set<String>? activeNetworks])
    : activeNetworks = activeNetworks ?? <String>{};

  final Set<String> activeNetworks;

  @override
  Future<bool> isActiveSeen(String network) async {
    return activeNetworks.contains(network);
  }

  @override
  Future<void> markActiveSeen(String network) async {
    activeNetworks.add(network);
  }
}

rust_wallet.ChainUpgradeStatus _fullStatus({
  required String network,
  required String lightwalletdUrl,
  required int tipHeight,
  required bool ironwoodActive,
}) {
  return rust_wallet.ChainUpgradeStatus(
    network: network,
    lightwalletdChainName: network,
    tipHeight: BigInt.from(tipHeight),
    lightwalletdReportedHeight: BigInt.from(tipHeight),
    lightwalletdEstimatedHeight: BigInt.from(tipHeight),
    lightwalletdConsensusBranchId: ironwoodActive ? '37a5165b' : 'c8e71055',
    lightwalletdUpgradeName: '',
    lightwalletdUpgradeHeight: BigInt.zero,
    nu63ActivationHeight: BigInt.from(3_428_143),
    ironwoodActiveAtTip: ironwoodActive,
    endpointMatchesNetwork: true,
  );
}

rust_wallet.ChainUpgradeActivationStatus _activationStatus({
  required String network,
  required BigInt tipHeight,
  required bool ironwoodActive,
}) {
  return rust_wallet.ChainUpgradeActivationStatus(
    network: network,
    tipHeight: tipHeight,
    nu63ActivationHeight: BigInt.from(3_428_143),
    ironwoodActiveAtTip: ironwoodActive,
  );
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
