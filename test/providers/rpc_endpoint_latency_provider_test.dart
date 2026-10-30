import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_latency_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart'
    show LightwalletdEndpointProbe;

void main() {
  group('measureRpcEndpointLatency', () {
    test('uses Rust timing instead of time awaiting the bridge', () async {
      final response = Completer<LightwalletdEndpointProbe>();

      final pending = measureRpcEndpointLatency(
        lightwalletdUrl: 'https://zec.rocks:443',
        expectedNetworkName: 'main',
        getProbe: (_) => response.future,
      );
      // Time spent waiting for a bridge worker/result must not affect the label.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      response.complete(
        const LightwalletdEndpointProbe(chainName: 'main', latencyMs: 123),
      );
      final sample = await pending;

      expect(sample.status, RpcEndpointLatencyStatus.available);
      expect(sample.latency, const Duration(milliseconds: 123));
      expect(sample.label, '123ms');
    });

    test(
      'returns wrongNetwork when the endpoint reports another chain',
      () async {
        final sample = await measureRpcEndpointLatency(
          lightwalletdUrl: 'https://testnet.zec.rocks:443',
          expectedNetworkName: 'main',
          getProbe: (_) async => const LightwalletdEndpointProbe(
            chainName: 'test',
            latencyMs: 123,
          ),
        );

        expect(sample.status, RpcEndpointLatencyStatus.wrongNetwork);
        expect(sample.label, 'Wrong network');
      },
    );

    test('returns unavailable when the endpoint check fails', () async {
      final sample = await measureRpcEndpointLatency(
        lightwalletdUrl: 'https://does-not-exist.example:443',
        expectedNetworkName: 'main',
        getProbe: (_) async => throw Exception('connect failed'),
      );

      expect(sample.status, RpcEndpointLatencyStatus.unavailable);
      expect(sample.label, 'Unavailable');
    });
  });

  group('RpcEndpointLatencyNotifier', () {
    test('marks presets checking before resolving measured latency', () async {
      final completer = Completer<LightwalletdEndpointProbe>();
      final container = ProviderContainer(
        overrides: [
          rpcEndpointProbeGetterProvider.overrideWithValue(
            (_) => completer.future,
          ),
        ],
      );
      addTearDown(container.dispose);

      final refresh = container
          .read(rpcEndpointLatencyProvider.notifier)
          .refresh('main');

      await Future<void>.delayed(Duration.zero);

      final checkingState = container.read(rpcEndpointLatencyProvider);
      expect(
        checkingState.samples.values.every(
          (sample) => sample.status == RpcEndpointLatencyStatus.checking,
        ),
        isTrue,
      );

      completer.complete(
        const LightwalletdEndpointProbe(chainName: 'main', latencyMs: 123),
      );
      await refresh;

      final finalState = container.read(rpcEndpointLatencyProvider);
      expect(
        finalState.samples.values.every(
          (sample) => sample.status == RpcEndpointLatencyStatus.available,
        ),
        isTrue,
      );
    });

    test('discard stale samples when a newer refresh starts', () async {
      final completers = <Completer<LightwalletdEndpointProbe>>[];
      final container = ProviderContainer(
        overrides: [
          rpcEndpointProbeGetterProvider.overrideWithValue((_) {
            final completer = Completer<LightwalletdEndpointProbe>();
            completers.add(completer);
            return completer.future;
          }),
        ],
      );
      addTearDown(container.dispose);

      final firstRefresh = container
          .read(rpcEndpointLatencyProvider.notifier)
          .refresh('main');
      await Future<void>.delayed(Duration.zero);
      final firstCompleters = List<Completer<LightwalletdEndpointProbe>>.of(
        completers,
      );

      final secondRefresh = container
          .read(rpcEndpointLatencyProvider.notifier)
          .refresh('main');
      await Future<void>.delayed(Duration.zero);
      final secondCompleters = completers
          .where((completer) => !firstCompleters.contains(completer))
          .toList();

      for (final completer in firstCompleters) {
        completer.complete(
          const LightwalletdEndpointProbe(chainName: 'test', latencyMs: 456),
        );
      }
      await firstRefresh;
      final afterStale = container.read(rpcEndpointLatencyProvider);
      expect(
        afterStale.samples.values.every(
          (sample) => sample.status == RpcEndpointLatencyStatus.checking,
        ),
        isTrue,
      );

      for (final completer in secondCompleters) {
        completer.complete(
          const LightwalletdEndpointProbe(chainName: 'main', latencyMs: 123),
        );
      }
      await secondRefresh;
      final finalState = container.read(rpcEndpointLatencyProvider);
      expect(
        finalState.samples.values.every(
          (sample) => sample.status == RpcEndpointLatencyStatus.available,
        ),
        isTrue,
      );
    });
  });
}
