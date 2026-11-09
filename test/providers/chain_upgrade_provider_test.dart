import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
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
  });

  test('waits for endpoint selection before fetching chain metadata', () async {
    const endpoint = RpcEndpointConfig(
      networkName: 'main',
      lightwalletdUrl: 'https://seed.example:443',
    );
    const selected = RpcEndpointConfig(
      networkName: 'main',
      lightwalletdUrl: 'https://selected.example:443',
    );
    final selection = Completer<RpcEndpointConfig>();
    final calls = <String>[];
    final container = _container(
      endpoint: endpoint,
      resolver: () => _DeferredRoute(selected, selection.future),
      getChainUpgradeStatus:
          ({required lightwalletdUrl, required network}) async {
            calls.add(lightwalletdUrl);
            return _fullStatus(
              network: network,
              lightwalletdUrl: lightwalletdUrl,
              tipHeight: 3_500_000,
              ironwoodActive: true,
            );
          },
    );
    addTearDown(container.dispose);
    final pending = container.read(chainUpgradeStatusProvider.future);
    await pumpEventQueue();
    expect(calls, isEmpty);
    selection.complete(selected);
    final status = await pending;
    expect(calls, ['https://selected.example:443']);
    expect(status.endpointUrl, 'https://selected.example:443');
  });

  for (final refresh in [false, true]) {
    for (final lock in [false, true]) {
      test(
        '${refresh ? 'refresh' : 'build'} skips metadata when selection completes '
        'after ${lock ? 'locking' : 'readiness invalidation'}',
        () async {
          final endpoint = defaultRpcEndpointConfig('main');
          final selection = Completer<RpcEndpointConfig>();
          final security = _Security();
          final route = _DeferredRoute(
            endpoint,
            refresh ? Future.value(endpoint) : selection.future,
          );
          var calls = 0;
          final container = _container(
            endpoint: endpoint,
            resolver: () => route,
            security: security,
            getChainUpgradeStatus:
                ({required lightwalletdUrl, required network}) async {
                  calls++;
                  return _fullStatus(
                    network: network,
                    lightwalletdUrl: lightwalletdUrl,
                    tipHeight: 3_400_000,
                    ironwoodActive: false,
                  );
                },
          );
          addTearDown(container.dispose);

          Future<Object?> pending;
          if (refresh) {
            await container.read(chainUpgradeStatusProvider.future);
            expect(calls, 1);
            route.selection = selection.future;
            pending = container
                .read(chainUpgradeStatusProvider.notifier)
                .refresh();
          } else {
            pending = container.read(chainUpgradeStatusProvider.future);
          }
          await pumpEventQueue();
          expect(calls, refresh ? 1 : 0);

          if (lock) {
            security.publishLocked();
          } else {
            route.invalidateReadiness();
          }
          selection.complete(endpoint);
          if (refresh) {
            await pending;
          } else {
            // Locking invalidates the provider's loading generation. Observe
            // the replacement build rather than its superseded Future.
            pending.ignore();
            await container.read(chainUpgradeStatusProvider.future);
          }
          await pumpEventQueue();

          expect(calls, refresh ? 1 : 0);
        },
      );
    }
  }

  test('locked automatic startup keeps chain metadata unobserved', () async {
    var calls = 0;
    final container = _container(
      endpoint: defaultRpcEndpointConfig('main'),
      locked: true,
      getChainUpgradeStatus:
          ({required lightwalletdUrl, required network}) async {
            calls++;
            throw StateError('locked startup must not query lightwalletd');
          },
    );
    addTearDown(container.dispose);

    final status = await container.read(chainUpgradeStatusProvider.future);
    expect(status.ironwoodActiveAtTip, isFalse);
    expect(status.tipHeight, BigInt.zero);
    expect(calls, 0);
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

  test('SharedPreferences store does not persist regtest activation', () async {
    const store = SharedPreferencesIronwoodActivationStore();
    final prefs = await SharedPreferences.getInstance();

    await store.markActiveSeen('regtest');
    expect(prefs.getBool(ironwoodActiveSeenStorageKey('regtest')), isNull);

    await prefs.setBool(ironwoodActiveSeenStorageKey('regtest'), true);
    expect(await store.isActiveSeen('regtest'), isFalse);
  });
}

ProviderContainer _container({
  required RpcEndpointConfig endpoint,
  required ChainUpgradeStatusGetter getChainUpgradeStatus,
  ChainUpgradeStatusAtHeightGetter? getChainUpgradeStatusAtHeight,
  IronwoodActivationStore? store,
  RpcEndpointFailoverNotifier Function()? resolver,
  bool locked = false,
  _Security? security,
}) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrap(endpoint, locked: locked),
      ),
      if (resolver != null) rpcEndpointFailoverProvider.overrideWith(resolver),
      if (security != null) appSecurityProvider.overrideWith(() => security),
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

class _DeferredRoute extends RpcEndpointFailoverNotifier {
  _DeferredRoute(this.endpoint, this.selection);

  final RpcEndpointConfig endpoint;
  Future<RpcEndpointConfig> selection;

  @override
  RpcEndpointFailoverState build() => RpcEndpointFailoverState(
    primary: endpoint,
    current: endpoint,
    fallbackCandidates: const [],
  );

  @override
  Future<RpcEndpointConfig> ensureReady() => selection;

  void invalidateReadiness() => state = state.copyWith(automaticReady: false);
}

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  void publishLocked() => state = state.copyWith(isUnlocked: false);
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
    tipHeight: BigInt.from(tipHeight),
    ironwoodActiveAtTip: ironwoodActive,
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
    ironwoodActiveAtTip: ironwoodActive,
  );
}

AppBootstrapState _bootstrap(
  RpcEndpointConfig endpoint, {
  bool locked = false,
}) {
  return AppBootstrapState(
    initialLocation: '/welcome',
    initialAccountState: const AccountState(),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: endpoint.networkName,
    rpcEndpointConfig: endpoint,
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: locked,
    isUnlocked: !locked,
    passwordRotationRecoveryFailed: false,
  );
}
