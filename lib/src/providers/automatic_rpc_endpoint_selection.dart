import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_secure_store.dart';
import '../core/config/rpc_endpoint_config.dart';
import '../rust/api/wallet.dart' as rust_wallet;

/// Selection uses public chain metadata only, never a wallet-derived request.
class RpcEndpointCandidateSample {
  const RpcEndpointCandidateSample({
    required this.url,
    required this.height,
    required this.latency,
  });

  final String url;
  final BigInt height;
  final Duration latency;
}

typedef RpcEndpointCandidatesProbe =
    Future<List<RpcEndpointCandidateSample>> Function({
      required List<String> urls,
      required String network,
      required String selectionId,
      required Duration probeTimeout,
      required Duration totalTimeout,
      required int maxConcurrency,
    });

final rpcEndpointCandidatesProbeProvider = Provider<RpcEndpointCandidatesProbe>(
  (_) =>
      ({
        required urls,
        required network,
        required selectionId,
        required probeTimeout,
        required totalTimeout,
        required maxConcurrency,
      }) async {
        // Reserve synchronously before the FRB worker can queue. Cancellation
        // then remains authoritative even if that worker starts much later.
        rust_wallet.beginLightwalletdSelection(selectionId: selectionId);
        final results = await rust_wallet.probeLightwalletdCandidates(
          lightwalletdUrls: urls,
          expectedNetwork: network,
          selectionId: selectionId,
          probeTimeoutMs: probeTimeout.inMilliseconds,
          totalTimeoutMs: totalTimeout.inMilliseconds,
          maxConcurrency: maxConcurrency,
        );
        return [
          for (final result in results)
            RpcEndpointCandidateSample(
              url: result.url,
              height: result.height,
              latency: Duration(milliseconds: result.latencyMs),
            ),
        ];
      },
);

final rpcEndpointSelectionCancelProvider = Provider<void Function(String)>(
  (_) =>
      (id) => rust_wallet.cancelLightwalletdSelection(selectionId: id),
);

/// A bounded real tip read used only after a recently verified cached route.
typedef RpcEndpointWarmTipReader =
    Future<RpcEndpointCandidateSample> Function({
      required RpcEndpointConfig endpoint,
      required String selectionId,
      required Duration timeout,
    });

final rpcEndpointWarmTipReaderProvider = Provider<RpcEndpointWarmTipReader>(
  (_) => ({required endpoint, required selectionId, required timeout}) async {
    rust_wallet.beginLightwalletdSelection(selectionId: selectionId);
    final result = await rust_wallet.readLightwalletdTip(
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      expectedNetwork: endpoint.networkName,
      selectionId: selectionId,
      timeoutMs: timeout.inMilliseconds,
    );
    return RpcEndpointCandidateSample(
      url: result.url,
      height: result.height,
      latency: Duration(milliseconds: result.latencyMs),
    );
  },
);

class AutomaticRpcEndpointSettings {
  const AutomaticRpcEndpointSettings({
    this.directBudget = const Duration(seconds: 6),
    this.torBudget = const Duration(seconds: 15),
    this.directProbeTimeout = const Duration(seconds: 3),
    this.torProbeTimeout = const Duration(seconds: 8),
    this.cacheMaxAge = const Duration(hours: 12),
    this.warmReuseMaxAge = const Duration(minutes: 5),
    this.tipReuseMaxAge = const Duration(seconds: 5),
    this.directWarmTipTimeout = const Duration(milliseconds: 1500),
    this.torWarmTipTimeout = const Duration(seconds: 5),
    this.directWarmTipMaxTimeout = const Duration(seconds: 4),
    this.torWarmTipMaxTimeout = const Duration(seconds: 8),
    this.cacheWriteInterval = const Duration(minutes: 1),
    this.recheckInterval = const Duration(minutes: 15),
    this.provisionalRecheckInterval = const Duration(minutes: 1),
    this.minimumResidence = const Duration(minutes: 5),
    this.slowResponse = const Duration(seconds: 2),
    this.slowTorResponse = const Duration(seconds: 5),
    this.failureCooldown = const Duration(minutes: 1),
  });

  final Duration directBudget;
  final Duration torBudget;
  final Duration directProbeTimeout;
  final Duration torProbeTimeout;
  final Duration cacheMaxAge;
  final Duration warmReuseMaxAge;
  final Duration tipReuseMaxAge;
  final Duration directWarmTipTimeout;
  final Duration torWarmTipTimeout;
  final Duration directWarmTipMaxTimeout;
  final Duration torWarmTipMaxTimeout;
  final Duration cacheWriteInterval;
  final Duration recheckInterval;
  final Duration provisionalRecheckInterval;
  final Duration minimumResidence;
  final Duration slowResponse;
  final Duration slowTorResponse;
  final Duration failureCooldown;

  /// Allows for recent route latency, including a new connection after resume.
  /// At least one third of the recovery budget remains for candidate selection.
  Duration warmTipTimeout({required bool tor, Duration? recentLatency}) {
    final total = tor ? torBudget : directBudget;
    final floor = tor ? torWarmTipTimeout : directWarmTipTimeout;
    final ceiling = tor ? torWarmTipMaxTimeout : directWarmTipMaxTimeout;
    final capMicros = math.max(
      0,
      math.min(
        math.min(
          ceiling.inMicroseconds,
          const Duration(seconds: 30).inMicroseconds,
        ),
        (total.inMicroseconds ~/ 3) * 2,
      ),
    );
    final floorMicros = math.max(0, math.min(floor.inMicroseconds, capMicros));
    if (recentLatency == null || recentLatency <= Duration.zero) {
      return Duration(microseconds: floorMicros);
    }
    // Clamp before multiplication so a large latency cannot overflow or
    // expand the native request beyond its supported deadline.
    if (recentLatency.inMicroseconds >= capMicros) {
      return Duration(microseconds: capMicros);
    }
    final slack = tor
        ? const Duration(seconds: 1)
        : const Duration(milliseconds: 500);
    final adaptiveMicros =
        recentLatency.inMicroseconds * 3 + slack.inMicroseconds;
    return Duration(
      microseconds: math.min(capMicros, math.max(floorMicros, adaptiveMicros)),
    );
  }
}

final automaticRpcEndpointSettingsProvider =
    Provider<AutomaticRpcEndpointSettings>(
      (_) => const AutomaticRpcEndpointSettings(),
    );

class AutomaticRpcEndpointCache {
  const AutomaticRpcEndpointCache({
    required this.presetId,
    required this.observedAt,
    this.lastSuccessAt,
    this.lastPeerValidatedAt,
    this.lastBenchmarkAt,
    this.lastNetworkVerifiedAt,
    this.latencyMs,
    this.endpointUrl,
  });

  final String presetId;
  final DateTime observedAt;
  final DateTime? lastSuccessAt;
  final DateTime? lastPeerValidatedAt;
  final DateTime? lastBenchmarkAt;
  final DateTime? lastNetworkVerifiedAt;
  final int? latencyMs;
  final String? endpointUrl;

  bool isWarm(
    DateTime now,
    AutomaticRpcEndpointSettings settings, {
    String? expectedUrl,
  }) =>
      endpointUrl != null &&
      (expectedUrl == null || endpointUrl == expectedUrl) &&
      isRecentEndpointObservation(observedAt, now, settings.cacheMaxAge) &&
      isRecentEndpointObservation(
        lastSuccessAt,
        now,
        settings.warmReuseMaxAge,
      ) &&
      isRecentEndpointObservation(
        lastNetworkVerifiedAt ?? lastBenchmarkAt,
        now,
        settings.cacheMaxAge,
      );
}

bool isRecentEndpointObservation(DateTime? at, DateTime now, Duration maxAge) {
  if (at == null) return false;
  final age = now.difference(at);
  return !age.isNegative && age < maxAge;
}

abstract interface class AutomaticRpcEndpointStore {
  Future<AutomaticRpcEndpointCache?> read(String network, bool tor);
  Future<void> write(String network, bool tor, AutomaticRpcEndpointCache cache);
  Future<void> clear();
}

/// Uses the existing wallet store, so a full secure-storage wipe also removes
/// connection history. Cache failures never prevent a network operation.
class SecureAutomaticRpcEndpointStore implements AutomaticRpcEndpointStore {
  const SecureAutomaticRpcEndpointStore();

  String _key(String network, bool tor) =>
      'zcash_automatic_rpc_v1_${network}_${tor ? 'tor' : 'direct'}';

  @override
  Future<AutomaticRpcEndpointCache?> read(String network, bool tor) async {
    final raw = await AppSecureStore.instance.readPlain(_key(network, tor));
    if (raw == null) return null;
    final value = jsonDecode(raw) as Map<String, dynamic>;
    return AutomaticRpcEndpointCache(
      presetId: value['preset'] as String,
      observedAt: DateTime.parse(value['observedAt'] as String),
      lastSuccessAt: value['lastSuccessAt'] == null
          ? null
          : DateTime.parse(value['lastSuccessAt'] as String),
      lastPeerValidatedAt: value['lastPeerValidatedAt'] == null
          ? null
          : DateTime.parse(value['lastPeerValidatedAt'] as String),
      lastBenchmarkAt: value['lastBenchmarkAt'] == null
          ? null
          : DateTime.parse(value['lastBenchmarkAt'] as String),
      lastNetworkVerifiedAt: value['lastNetworkVerifiedAt'] == null
          ? null
          : DateTime.parse(value['lastNetworkVerifiedAt'] as String),
      latencyMs: value['latencyMs'] as int?,
      endpointUrl: value['endpointUrl'] as String?,
    );
  }

  @override
  Future<void> write(
    String network,
    bool tor,
    AutomaticRpcEndpointCache cache,
  ) => AppSecureStore.instance.writePlain(
    _key(network, tor),
    jsonEncode({
      'preset': cache.presetId,
      'observedAt': cache.observedAt.toUtc().toIso8601String(),
      if (cache.lastSuccessAt != null)
        'lastSuccessAt': cache.lastSuccessAt!.toUtc().toIso8601String(),
      if (cache.lastPeerValidatedAt != null)
        'lastPeerValidatedAt': cache.lastPeerValidatedAt!
            .toUtc()
            .toIso8601String(),
      if (cache.lastBenchmarkAt != null)
        'lastBenchmarkAt': cache.lastBenchmarkAt!.toUtc().toIso8601String(),
      if (cache.lastNetworkVerifiedAt != null)
        'lastNetworkVerifiedAt': cache.lastNetworkVerifiedAt!
            .toUtc()
            .toIso8601String(),
      if (cache.latencyMs != null) 'latencyMs': cache.latencyMs,
      if (cache.endpointUrl != null) 'endpointUrl': cache.endpointUrl,
    }),
  );

  @override
  Future<void> clear() async {
    await AppSecureStore.instance.delete(_key('main', false));
    await AppSecureStore.instance.delete(_key('main', true));
  }
}

final automaticRpcEndpointStoreProvider = Provider<AutomaticRpcEndpointStore>(
  (_) => const SecureAutomaticRpcEndpointStore(),
);

/// Prefer the fastest member of a plausible height cluster. One high outlier
/// must not evict all agreeing servers; an isolated success remains provisional.
List<RpcEndpointCandidateSample> rankAutomaticRpcEndpointSamples(
  List<RpcEndpointCandidateSample> samples, {
  BigInt? minimumHeight,
  bool requireCorroboration = false,
}) {
  if (samples.isEmpty) return const [];
  // A repeated response from one host is not an independent observation.
  final distinct = {
    for (final sample in samples) sample.url: sample,
  }.values.toList();
  final byHeight = [...distinct]..sort((a, b) => a.height.compareTo(b.height));
  final tolerance = BigInt.from(2);
  var start = 0;
  var bestStart = 0;
  var bestEnd = 0;
  for (var end = 0; end < byHeight.length; end++) {
    while (byHeight[end].height - byHeight[start].height > tolerance) {
      start++;
    }
    // Prefer a fresher cluster when equally many peers agree. With no pair
    // agreeing, keep responses provisional rather than trusting one maximum.
    if (end - start >= bestEnd - bestStart) {
      bestStart = start;
      bestEnd = end;
    }
  }
  final hasCluster = bestEnd > bestStart;
  if (requireCorroboration && !hasCluster) return const [];
  final low = byHeight[bestStart].height;
  final high = byHeight[bestEnd].height;
  final ranked =
      distinct
          .where(
            (sample) =>
                (!hasCluster ||
                    (sample.height >= low && sample.height <= high)) &&
                (minimumHeight == null || sample.height >= minimumHeight),
          )
          .toList()
        ..sort((a, b) => a.latency.compareTo(b.latency));
  return ranked;
}
