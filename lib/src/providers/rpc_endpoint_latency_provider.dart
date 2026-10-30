import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/rpc_endpoint_config.dart';
import '../rust/api/wallet.dart' as rust_wallet;

typedef RpcEndpointProbeGetter =
    Future<rust_wallet.LightwalletdEndpointProbe> Function(
      String lightwalletdUrl,
    );

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
  required RpcEndpointProbeGetter getProbe,
}) async {
  // Rust times the existing connection and chain-info request after its bridge
  // worker starts, so queued work is not reported as endpoint latency.
  try {
    final probe = await getProbe(lightwalletdUrl);
    if (probe.chainName != expectedNetworkName) {
      return const RpcEndpointLatencySample.wrongNetwork();
    }
    return RpcEndpointLatencySample.available(
      Duration(milliseconds: probe.latencyMs),
    );
  } catch (_) {
    return const RpcEndpointLatencySample.unavailable();
  }
}

final rpcEndpointProbeGetterProvider = Provider<RpcEndpointProbeGetter>(
  (ref) =>
      (lightwalletdUrl) => rust_wallet.probeLightwalletdEndpoint(
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
    final getProbe = ref.read(rpcEndpointProbeGetterProvider);

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
          getProbe: getProbe,
          generation: generation,
        ),
    ]);
  }

  Future<void> _measurePreset({
    required RpcEndpointPreset preset,
    required String networkName,
    required RpcEndpointProbeGetter getProbe,
    required int generation,
  }) async {
    final normalizedUrl = normalizeRpcEndpointUrl(
      preset.url,
      allowDefaultPort: true,
    );
    final sample = await measureRpcEndpointLatency(
      lightwalletdUrl: normalizedUrl,
      expectedNetworkName: networkName,
      getProbe: getProbe,
    );
    if (generation != _generation) return;
    state = state.copyWithSample(normalizedUrl, sample);
  }
}

final rpcEndpointLatencyProvider =
    NotifierProvider<RpcEndpointLatencyNotifier, RpcEndpointLatencyState>(
      RpcEndpointLatencyNotifier.new,
    );
