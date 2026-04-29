import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_latency_provider.dart';

void main() {
  group('measureRpcEndpointLatency', () {
    test('returns an available sample with elapsed milliseconds', () async {
      final timestamps = [
        DateTime(2026),
        DateTime(2026).add(const Duration(milliseconds: 123)),
      ];
      var index = 0;

      final sample = await measureRpcEndpointLatency(
        lightwalletdUrl: 'https://zec.rocks:443',
        expectedNetworkName: 'main',
        getChainName: (_) async => 'main',
        now: () => timestamps[index++],
      );

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
          getChainName: (_) async => 'test',
        );

        expect(sample.status, RpcEndpointLatencyStatus.wrongNetwork);
        expect(sample.label, 'Wrong network');
      },
    );

    test('returns unavailable when the endpoint check fails', () async {
      final sample = await measureRpcEndpointLatency(
        lightwalletdUrl: 'https://does-not-exist.example:443',
        expectedNetworkName: 'main',
        getChainName: (_) async => throw Exception('connect failed'),
      );

      expect(sample.status, RpcEndpointLatencyStatus.unavailable);
      expect(sample.label, 'Unavailable');
    });
  });

  group('RpcEndpointLatencyNotifier', () {
    test('marks presets checking before resolving measured latency', () async {
      final completer = Completer<String>();
      final container = ProviderContainer(
        overrides: [
          rpcEndpointChainNameGetterProvider.overrideWithValue(
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

      completer.complete('main');
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
      final completers = <Completer<String>>[];
      final container = ProviderContainer(
        overrides: [
          rpcEndpointChainNameGetterProvider.overrideWithValue((_) {
            final completer = Completer<String>();
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
      final firstCompleters = List<Completer<String>>.of(completers);

      final secondRefresh = container
          .read(rpcEndpointLatencyProvider.notifier)
          .refresh('main');
      await Future<void>.delayed(Duration.zero);
      final secondCompleters = completers
          .where((completer) => !firstCompleters.contains(completer))
          .toList();

      for (final completer in firstCompleters) {
        completer.complete('test');
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
        completer.complete('main');
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
