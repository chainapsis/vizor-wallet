import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/rpc_endpoint_config.dart';
import '../rust/api/wallet.dart' as rust_wallet;

typedef RpcEndpointChainNameGetter =
    Future<String> Function(String lightwalletdUrl);

enum RpcEndpointLatencyStatus { checking, available, unavailable, wrongNetwork }

class RpcEndpointLatencySample {
  const RpcEndpointLatencySample._({required this.status, this.latency});

  const RpcEndpointLatencySample.checking()
    : this._(status: RpcEndpointLatencyStatus.checking);

  const RpcEndpointLatencySample.available(Duration latency)
    : this._(status: RpcEndpointLatencyStatus.available, latency: latency);

  const RpcEndpointLatencySample.unavailable()
    : this._(status: RpcEndpointLatencyStatus.unavailable);

  const RpcEndpointLatencySample.wrongNetwork()
    : this._(status: RpcEndpointLatencyStatus.wrongNetwork);

  final RpcEndpointLatencyStatus status;
  final Duration? latency;

  String get label {
    return switch (status) {
      RpcEndpointLatencyStatus.checking => 'Checking...',
      RpcEndpointLatencyStatus.available => '${latency!.inMilliseconds}ms',
      RpcEndpointLatencyStatus.unavailable => 'Unavailable',
      RpcEndpointLatencyStatus.wrongNetwork => 'Wrong network',
    };
  }
}

class RpcEndpointLatencyState {
  const RpcEndpointLatencyState({this.samples = const {}});

  final Map<String, RpcEndpointLatencySample> samples;

  RpcEndpointLatencySample? sampleForUrl(String url) {
    final normalized = normalizeRpcEndpointUrl(url, allowDefaultPort: true);
    return samples[normalized];
  }

  RpcEndpointLatencyState copyWithSample(
    String url,
    RpcEndpointLatencySample sample,
  ) {
    final normalized = normalizeRpcEndpointUrl(url, allowDefaultPort: true);
    return RpcEndpointLatencyState(samples: {...samples, normalized: sample});
  }
}

Future<RpcEndpointLatencySample> measureRpcEndpointLatency({
  required String lightwalletdUrl,
  required String expectedNetworkName,
  required RpcEndpointChainNameGetter getChainName,
  DateTime Function() now = DateTime.now,
}) async {
  // Use the same lightwalletd chain-info call as endpoint saving so the
  // displayed latency reflects a real gRPC/TLS response, not only TCP reachability.
  final startedAt = now();
  try {
    final chainName = await getChainName(lightwalletdUrl);
    final elapsed = now().difference(startedAt);
    if (chainName != expectedNetworkName) {
      return const RpcEndpointLatencySample.wrongNetwork();
    }
    return RpcEndpointLatencySample.available(elapsed);
  } catch (_) {
    return const RpcEndpointLatencySample.unavailable();
  }
}

final rpcEndpointChainNameGetterProvider = Provider<RpcEndpointChainNameGetter>(
  (ref) =>
      (lightwalletdUrl) => rust_wallet.getLightwalletdChainName(
        lightwalletdUrl: lightwalletdUrl,
      ),
);

class RpcEndpointLatencyNotifier extends Notifier<RpcEndpointLatencyState> {
  var _generation = 0;

  @override
  RpcEndpointLatencyState build() => const RpcEndpointLatencyState();

  Future<void> refresh(String networkName) async {
    final generation = ++_generation;
    final presets = rpcEndpointPresetsForNetwork(networkName);
    final getChainName = ref.read(rpcEndpointChainNameGetterProvider);

    var nextState = state;
    for (final preset in presets) {
      nextState = nextState.copyWithSample(
        preset.url,
        const RpcEndpointLatencySample.checking(),
      );
    }
    state = nextState;

    await Future.wait([
      for (final preset in presets)
        _measurePreset(
          preset: preset,
          networkName: networkName,
          getChainName: getChainName,
          generation: generation,
        ),
    ]);
  }

  Future<void> _measurePreset({
    required RpcEndpointPreset preset,
    required String networkName,
    required RpcEndpointChainNameGetter getChainName,
    required int generation,
  }) async {
    final sample = await measureRpcEndpointLatency(
      lightwalletdUrl: normalizeRpcEndpointUrl(
        preset.url,
        allowDefaultPort: true,
      ),
      expectedNetworkName: networkName,
      getChainName: getChainName,
    );
    if (generation != _generation) return;
    state = state.copyWithSample(preset.url, sample);
  }
}

final rpcEndpointLatencyProvider =
    NotifierProvider<RpcEndpointLatencyNotifier, RpcEndpointLatencyState>(
      RpcEndpointLatencyNotifier.new,
    );
