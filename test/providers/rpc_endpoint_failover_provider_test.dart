import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';

void main() {
  test('classifies transient endpoint failures only', () {
    expect(
      shouldFallbackFromLightwalletdError(
        'network: get_latest_block: status: DeadlineExceeded',
      ),
      isTrue,
    );
    expect(
      shouldFallbackFromLightwalletdError(
        'gRPC connect failed: connection refused',
      ),
      isTrue,
    );
    expect(
      shouldFallbackFromLightwalletdError(
        'Endpoint is for test, but this wallet uses main.',
      ),
      isFalse,
    );
    expect(
      shouldFallbackFromLightwalletdError(
        'Proposal not found (expired or already executed)',
      ),
      isFalse,
    );
  });

  test('checkRpcEndpointHealth rejects wrong-network endpoints', () async {
    await expectLater(
      checkRpcEndpointHealth(
        endpoint: defaultRpcEndpointConfig('main'),
        getChainName: (_) async => 'test',
        getLatestBlockHeight: (_) async => BigInt.from(10),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('runWithEndpointFallback switches to a healthy fallback', () async {
    final primary = _customRegtestPrimary();
    final container = _container(
      primary: primary,
      chainNameByUrl: {'http://127.0.0.1:9067': 'regtest'},
      heightByUrl: {'http://127.0.0.1:9067': BigInt.from(10)},
    );
    addTearDown(container.dispose);

    final result = await container
        .read(rpcEndpointFailoverProvider.notifier)
        .runWithEndpointFallback(
          operation: 'test read',
          action: (endpoint) async {
            if (endpoint.normalizedLightwalletdUrl ==
                primary.normalizedLightwalletdUrl) {
              throw Exception('gRPC connect failed: connection refused');
            }
            return endpoint.hostPort;
          },
        );

    final state = container.read(rpcEndpointFailoverProvider);
    expect(result, '127.0.0.1:9067');
    expect(state.isUsingFallback, isTrue);
    expect(state.current.normalizedLightwalletdUrl, 'http://127.0.0.1:9067');
    expect(
      state.lastEvent?.kind,
      RpcEndpointFailoverEventKind.switchedToFallback,
    );
  });

  test('does not fallback for wallet-state errors', () async {
    final primary = _customRegtestPrimary();
    final container = _container(
      primary: primary,
      chainNameByUrl: {'http://127.0.0.1:9067': 'regtest'},
      heightByUrl: {'http://127.0.0.1:9067': BigInt.from(10)},
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(rpcEndpointFailoverProvider.notifier)
          .runWithEndpointFallback(
            operation: 'test read',
            action: (_) async =>
                throw Exception('Proposal not found (expired)'),
          ),
      throwsA(isA<Exception>()),
    );

    expect(
      container.read(rpcEndpointFailoverProvider).isUsingFallback,
      isFalse,
    );
  });

  test('periodic primary probe switches back after recovery', () async {
    var now = DateTime(2026);
    final primary = _customRegtestPrimary();
    final primaryUrl = primary.normalizedLightwalletdUrl;
    final container = _container(
      primary: primary,
      clock: () => now,
      chainNameByUrl: {
        'http://127.0.0.1:9067': 'regtest',
        primaryUrl: 'regtest',
      },
      heightByUrl: {
        'http://127.0.0.1:9067': BigInt.from(10),
        primaryUrl: BigInt.from(11),
      },
      settings: const RpcEndpointFailoverSettings(
        primaryProbeInterval: Duration(seconds: 5),
      ),
    );
    addTearDown(container.dispose);

    await container
        .read(rpcEndpointFailoverProvider.notifier)
        .switchToFallbackFor(
          Exception('DeadlineExceeded'),
          operation: 'test sync',
        );
    expect(container.read(rpcEndpointFailoverProvider).isUsingFallback, isTrue);
    expect(
      await container
          .read(rpcEndpointFailoverProvider.notifier)
          .maybeProbePrimary(),
      isFalse,
    );

    now = now.add(const Duration(seconds: 5));
    final recovered = await container
        .read(rpcEndpointFailoverProvider.notifier)
        .maybeProbePrimary();

    final state = container.read(rpcEndpointFailoverProvider);
    expect(recovered, isTrue);
    expect(state.isUsingFallback, isFalse);
    expect(
      state.lastEvent?.kind,
      RpcEndpointFailoverEventKind.switchedToPrimary,
    );
  });
}

ProviderContainer _container({
  required RpcEndpointConfig primary,
  required Map<String, String> chainNameByUrl,
  required Map<String, BigInt> heightByUrl,
  DateTime Function()? clock,
  RpcEndpointFailoverSettings settings = const RpcEndpointFailoverSettings(),
}) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(primary)),
      rpcEndpointFailoverSettingsProvider.overrideWithValue(settings),
      if (clock != null)
        rpcEndpointFailoverClockProvider.overrideWithValue(clock),
      rpcEndpointFailoverChainNameGetterProvider.overrideWithValue(
        (url) async =>
            chainNameByUrl[url] ?? (throw Exception('no chain $url')),
      ),
      rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
        (url) async => heightByUrl[url] ?? (throw Exception('no height $url')),
      ),
    ],
  );
}

RpcEndpointConfig _customRegtestPrimary() {
  return const RpcEndpointConfig(
    networkName: 'regtest',
    lightwalletdUrl: 'http://127.0.0.1:19067',
    presetId: kCustomRpcEndpointPresetId,
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
