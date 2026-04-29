import 'package:flutter_test/flutter_test.dart';
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
}
