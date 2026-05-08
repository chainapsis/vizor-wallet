import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../core/config/rpc_endpoint_config.dart';
import '../rust/api/wallet.dart' as rust_wallet;
import 'rpc_endpoint_provider.dart';

typedef RpcEndpointChainNameGetter =
    Future<String> Function(String lightwalletdUrl);
typedef RpcEndpointLatestBlockHeightGetter =
    Future<BigInt> Function(String lightwalletdUrl);

enum RpcEndpointFailoverEventKind { switchedToFallback, switchedToPrimary }

class RpcEndpointFailoverEvent {
  const RpcEndpointFailoverEvent({
    required this.sequence,
    required this.kind,
    required this.message,
    required this.endpoint,
  });

  final int sequence;
  final RpcEndpointFailoverEventKind kind;
  final String message;
  final RpcEndpointConfig endpoint;
}

class RpcEndpointFailoverSettings {
  const RpcEndpointFailoverSettings({
    this.primaryProbeInterval = const Duration(seconds: 60),
    this.primaryFailureThreshold = 1,
  });

  final Duration primaryProbeInterval;
  final int primaryFailureThreshold;
}

class RpcEndpointHealth {
  const RpcEndpointHealth({required this.chainName, required this.height});

  final String chainName;
  final BigInt height;
}

class RpcEndpointFailoverState {
  const RpcEndpointFailoverState({
    required this.primary,
    required this.current,
    required this.fallbackCandidates,
    this.primaryFailureCount = 0,
    this.lastFailure,
    this.switchedAt,
    this.lastPrimaryProbeAt,
    this.lastEvent,
  });

  final RpcEndpointConfig primary;
  final RpcEndpointConfig current;
  final List<RpcEndpointConfig> fallbackCandidates;
  final int primaryFailureCount;
  final String? lastFailure;
  final DateTime? switchedAt;
  final DateTime? lastPrimaryProbeAt;
  final RpcEndpointFailoverEvent? lastEvent;

  RpcEndpointConfig? get fallback =>
      fallbackCandidates.isEmpty ? null : fallbackCandidates.first;

  bool get isUsingFallback =>
      current.normalizedLightwalletdUrl != primary.normalizedLightwalletdUrl;

  RpcEndpointFailoverState copyWith({
    RpcEndpointConfig? primary,
    RpcEndpointConfig? current,
    List<RpcEndpointConfig>? fallbackCandidates,
    int? primaryFailureCount,
    String? lastFailure,
    bool clearLastFailure = false,
    DateTime? switchedAt,
    bool clearSwitchedAt = false,
    DateTime? lastPrimaryProbeAt,
    RpcEndpointFailoverEvent? lastEvent,
  }) {
    return RpcEndpointFailoverState(
      primary: primary ?? this.primary,
      current: current ?? this.current,
      fallbackCandidates: fallbackCandidates ?? this.fallbackCandidates,
      primaryFailureCount: primaryFailureCount ?? this.primaryFailureCount,
      lastFailure: clearLastFailure ? null : lastFailure ?? this.lastFailure,
      switchedAt: clearSwitchedAt ? null : switchedAt ?? this.switchedAt,
      lastPrimaryProbeAt: lastPrimaryProbeAt ?? this.lastPrimaryProbeAt,
      lastEvent: lastEvent ?? this.lastEvent,
    );
  }
}

Future<RpcEndpointHealth> checkRpcEndpointHealth({
  required RpcEndpointConfig endpoint,
  required RpcEndpointChainNameGetter getChainName,
  required RpcEndpointLatestBlockHeightGetter getLatestBlockHeight,
}) async {
  final chainName = await getChainName(endpoint.normalizedLightwalletdUrl);
  if (chainName != endpoint.networkName) {
    throw FormatException(
      'Endpoint is for $chainName, but this wallet uses ${endpoint.networkName}.',
    );
  }
  final height = await getLatestBlockHeight(endpoint.normalizedLightwalletdUrl);
  return RpcEndpointHealth(chainName: chainName, height: height);
}

bool shouldFallbackFromLightwalletdError(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('wrong network') ||
      message.contains('endpoint is for') ||
      message.contains('database is locked') ||
      message.contains('proposal not found') ||
      message.contains('send flow mismatch') ||
      message.contains('insufficient') ||
      message.contains('invalid amount') ||
      message.contains('invalid address')) {
    return false;
  }

  return message.contains('network:') ||
      message.contains('deadlineexceeded') ||
      message.contains('deadline exceeded') ||
      message.contains('unavailable') ||
      message.contains('timed out') ||
      message.contains('timeout') ||
      message.contains('grpc connect failed') ||
      message.contains('connect failed') ||
      message.contains('connection refused') ||
      message.contains('connection reset') ||
      message.contains('connection closed') ||
      message.contains('dns') ||
      message.contains('failed to lookup address') ||
      message.contains('tls error') ||
      message.contains('transport error') ||
      message.contains('http2') ||
      message.contains('socket');
}

final rpcEndpointFailoverSettingsProvider =
    Provider<RpcEndpointFailoverSettings>(
      (_) => const RpcEndpointFailoverSettings(),
    );

final rpcEndpointFailoverClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

final rpcEndpointFailoverChainNameGetterProvider =
    Provider<RpcEndpointChainNameGetter>(
      (_) =>
          (lightwalletdUrl) => rust_wallet.getLightwalletdChainName(
            lightwalletdUrl: lightwalletdUrl,
          ),
    );

final rpcEndpointFailoverLatestBlockHeightGetterProvider =
    Provider<RpcEndpointLatestBlockHeightGetter>(
      (_) =>
          (lightwalletdUrl) => rust_wallet.getLatestBlockHeight(
            lightwalletdUrl: lightwalletdUrl,
          ),
    );

class RpcEndpointFailoverNotifier extends Notifier<RpcEndpointFailoverState> {
  int _eventSequence = 0;

  @override
  RpcEndpointFailoverState build() {
    final primary = ref.watch(rpcEndpointProvider);
    return RpcEndpointFailoverState(
      primary: primary,
      current: primary,
      fallbackCandidates: fallbackRpcEndpointCandidatesFor(primary),
    );
  }

  RpcEndpointConfig get currentEndpoint => state.current;

  Future<BigInt> getLatestBlockHeight() {
    return runWithEndpointFallback(
      operation: 'latest block height',
      action: (endpoint) => ref
          .read(rpcEndpointFailoverLatestBlockHeightGetterProvider)
          .call(endpoint.normalizedLightwalletdUrl),
    );
  }

  Future<T> runWithEndpointFallback<T>({
    required String operation,
    required Future<T> Function(RpcEndpointConfig endpoint) action,
    bool allowFallback = true,
    bool Function(Object error) shouldFallback =
        shouldFallbackFromLightwalletdError,
  }) async {
    await maybeProbePrimary();
    final endpoint = state.current;
    try {
      final result = await action(endpoint);
      _recordEndpointSuccess(endpoint);
      return result;
    } catch (e, st) {
      final switched = allowFallback
          ? await switchToFallbackFor(
              e,
              endpoint: endpoint,
              operation: operation,
              shouldFallback: shouldFallback,
            )
          : false;
      if (!switched) {
        Error.throwWithStackTrace(e, st);
      }

      final fallbackEndpoint = state.current;
      try {
        final result = await action(fallbackEndpoint);
        _recordEndpointSuccess(fallbackEndpoint);
        return result;
      } catch (fallbackError, fallbackStack) {
        Error.throwWithStackTrace(fallbackError, fallbackStack);
      }
    }
  }

  Future<bool> switchToFallbackFor(
    Object error, {
    RpcEndpointConfig? endpoint,
    required String operation,
    bool Function(Object error) shouldFallback =
        shouldFallbackFromLightwalletdError,
  }) async {
    final attempted = endpoint ?? state.current;
    if (state.isUsingFallback ||
        attempted.normalizedLightwalletdUrl !=
            state.primary.normalizedLightwalletdUrl ||
        !shouldFallback(error)) {
      return false;
    }

    final nextFailureCount = state.primaryFailureCount + 1;
    final settings = ref.read(rpcEndpointFailoverSettingsProvider);
    if (nextFailureCount < settings.primaryFailureThreshold) {
      state = state.copyWith(
        primaryFailureCount: nextFailureCount,
        lastFailure: error.toString(),
      );
      return false;
    }

    final fallbackCandidates = state.fallbackCandidates;
    if (fallbackCandidates.isEmpty) {
      log(
        'RpcEndpointFailover: no fallback endpoint for '
        '${state.primary.hostPort} after $operation failure: $error',
      );
      state = state.copyWith(
        primaryFailureCount: nextFailureCount,
        lastFailure: error.toString(),
      );
      return false;
    }

    RpcEndpointConfig? fallback;
    Object? lastFallbackError;
    for (final candidate in fallbackCandidates) {
      try {
        await _checkHealth(candidate);
        fallback = candidate;
        break;
      } catch (fallbackError) {
        lastFallbackError = fallbackError;
        log(
          'RpcEndpointFailover: fallback ${candidate.hostPort} failed health '
          'check after $operation failure: $fallbackError',
        );
      }
    }

    if (fallback == null) {
      log(
        'RpcEndpointFailover: all fallback endpoints failed health checks '
        'after $operation failure: $lastFallbackError',
      );
      state = state.copyWith(
        primaryFailureCount: nextFailureCount,
        lastFailure: error.toString(),
      );
      return false;
    }

    final now = ref.read(rpcEndpointFailoverClockProvider)();
    final event = RpcEndpointFailoverEvent(
      sequence: ++_eventSequence,
      kind: RpcEndpointFailoverEventKind.switchedToFallback,
      message: 'Selected endpoint is unstable. Switched to fallback endpoint.',
      endpoint: fallback,
    );
    log(
      'RpcEndpointFailover: switched ${state.primary.hostPort} -> '
      '${fallback.hostPort} after $operation failure: $error',
    );
    state = state.copyWith(
      current: fallback,
      primaryFailureCount: nextFailureCount,
      lastFailure: error.toString(),
      switchedAt: now,
      lastPrimaryProbeAt: now,
      lastEvent: event,
    );
    return true;
  }

  Future<bool> maybeProbePrimary({bool force = false}) async {
    if (!state.isUsingFallback) return false;

    final now = ref.read(rpcEndpointFailoverClockProvider)();
    final settings = ref.read(rpcEndpointFailoverSettingsProvider);
    final lastProbe = state.lastPrimaryProbeAt;
    if (!force &&
        lastProbe != null &&
        now.difference(lastProbe) < settings.primaryProbeInterval) {
      return false;
    }

    state = state.copyWith(lastPrimaryProbeAt: now);
    try {
      await _checkHealth(state.primary);
    } catch (e) {
      log(
        'RpcEndpointFailover: primary ${state.primary.hostPort} probe failed: $e',
      );
      return false;
    }

    final event = RpcEndpointFailoverEvent(
      sequence: ++_eventSequence,
      kind: RpcEndpointFailoverEventKind.switchedToPrimary,
      message: 'Selected endpoint recovered. Switched back.',
      endpoint: state.primary,
    );
    log(
      'RpcEndpointFailover: primary ${state.primary.hostPort} recovered; '
      'leaving fallback ${state.current.hostPort}',
    );
    state = state.copyWith(
      current: state.primary,
      primaryFailureCount: 0,
      clearLastFailure: true,
      clearSwitchedAt: true,
      lastPrimaryProbeAt: now,
      lastEvent: event,
    );
    return true;
  }

  Future<RpcEndpointHealth> _checkHealth(RpcEndpointConfig endpoint) {
    return checkRpcEndpointHealth(
      endpoint: endpoint,
      getChainName: ref.read(rpcEndpointFailoverChainNameGetterProvider),
      getLatestBlockHeight: ref.read(
        rpcEndpointFailoverLatestBlockHeightGetterProvider,
      ),
    );
  }

  void _recordEndpointSuccess(RpcEndpointConfig endpoint) {
    if (endpoint.normalizedLightwalletdUrl ==
            state.primary.normalizedLightwalletdUrl &&
        state.primaryFailureCount != 0) {
      state = state.copyWith(primaryFailureCount: 0, clearLastFailure: true);
    }
  }
}

final rpcEndpointFailoverProvider =
    NotifierProvider<RpcEndpointFailoverNotifier, RpcEndpointFailoverState>(
      RpcEndpointFailoverNotifier.new,
    );
