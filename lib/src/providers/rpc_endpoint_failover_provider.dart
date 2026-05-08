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
    this.slowHeightWindow = const Duration(minutes: 5),
    this.minHeightIncreaseInSlowWindow = 2,
    this.slowFallbackLeadBlocks = 2,
    this.primaryReturnLagToleranceBlocks = 1,
  });

  final Duration primaryProbeInterval;
  final int primaryFailureThreshold;
  final Duration slowHeightWindow;
  final int minHeightIncreaseInSlowWindow;
  final int slowFallbackLeadBlocks;
  final int primaryReturnLagToleranceBlocks;
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
    this.heightWindowStartedAt,
    this.heightWindowStartHeight,
    this.lastObservedHeight,
    this.lastObservedAt,
  });

  final RpcEndpointConfig primary;
  final RpcEndpointConfig current;
  final List<RpcEndpointConfig> fallbackCandidates;
  final int primaryFailureCount;
  final String? lastFailure;
  final DateTime? switchedAt;
  final DateTime? lastPrimaryProbeAt;
  final RpcEndpointFailoverEvent? lastEvent;
  final DateTime? heightWindowStartedAt;
  final BigInt? heightWindowStartHeight;
  final BigInt? lastObservedHeight;
  final DateTime? lastObservedAt;

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
    DateTime? heightWindowStartedAt,
    bool clearHeightWindowStartedAt = false,
    BigInt? heightWindowStartHeight,
    bool clearHeightWindowStartHeight = false,
    BigInt? lastObservedHeight,
    bool clearLastObservedHeight = false,
    DateTime? lastObservedAt,
    bool clearLastObservedAt = false,
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
      heightWindowStartedAt: clearHeightWindowStartedAt
          ? null
          : heightWindowStartedAt ?? this.heightWindowStartedAt,
      heightWindowStartHeight: clearHeightWindowStartHeight
          ? null
          : heightWindowStartHeight ?? this.heightWindowStartHeight,
      lastObservedHeight: clearLastObservedHeight
          ? null
          : lastObservedHeight ?? this.lastObservedHeight,
      lastObservedAt: clearLastObservedAt
          ? null
          : lastObservedAt ?? this.lastObservedAt,
    );
  }
}

class _FallbackHealth {
  const _FallbackHealth({required this.endpoint, required this.health});

  final RpcEndpointConfig endpoint;
  final RpcEndpointHealth health;
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

  Future<BigInt> getLatestBlockHeight() async {
    const operation = 'latest block height';
    await maybeProbePrimary();
    final endpoint = state.current;
    final getLatestBlockHeight = ref.read(
      rpcEndpointFailoverLatestBlockHeightGetterProvider,
    );

    try {
      final height = await getLatestBlockHeight(
        endpoint.normalizedLightwalletdUrl,
      );
      _recordEndpointSuccess(endpoint);
      final slowFallback = await _maybeSwitchFromSlowHeight(
        endpoint,
        height,
        operation: operation,
      );
      return slowFallback?.height ?? height;
    } catch (e, st) {
      final switched = await switchToFallbackFor(
        e,
        endpoint: endpoint,
        operation: operation,
      );
      if (!switched) {
        Error.throwWithStackTrace(e, st);
      }

      final fallbackEndpoint = state.current;
      try {
        final fallbackHeight = await getLatestBlockHeight(
          fallbackEndpoint.normalizedLightwalletdUrl,
        );
        _recordEndpointSuccess(fallbackEndpoint);
        _resetHeightWindow(fallbackEndpoint, fallbackHeight);
        return fallbackHeight;
      } catch (fallbackError, fallbackStack) {
        Error.throwWithStackTrace(fallbackError, fallbackStack);
      }
    }
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
    final attemptedUrl = attempted.normalizedLightwalletdUrl;
    final currentUrl = state.current.normalizedLightwalletdUrl;
    final primaryUrl = state.primary.normalizedLightwalletdUrl;
    if (attemptedUrl != currentUrl || !shouldFallback(error)) {
      return false;
    }

    final failedPrimary = attemptedUrl == primaryUrl;
    final nextFailureCount = failedPrimary
        ? state.primaryFailureCount + 1
        : state.primaryFailureCount;
    final settings = ref.read(rpcEndpointFailoverSettingsProvider);
    if (failedPrimary && nextFailureCount < settings.primaryFailureThreshold) {
      state = state.copyWith(
        primaryFailureCount: nextFailureCount,
        lastFailure: error.toString(),
      );
      return false;
    }

    final fallbackCandidates = state.fallbackCandidates
        .where(
          (candidate) => candidate.normalizedLightwalletdUrl != attemptedUrl,
        )
        .toList(growable: false);
    if (fallbackCandidates.isEmpty) {
      log(
        'RpcEndpointFailover: no fallback endpoint for '
        '${attempted.hostPort} after $operation failure: $error',
      );
      state = state.copyWith(
        primaryFailureCount: nextFailureCount,
        lastFailure: error.toString(),
      );
      return false;
    }

    RpcEndpointConfig? fallback;
    RpcEndpointHealth? fallbackHealth;
    Object? lastFallbackError;
    for (final candidate in fallbackCandidates) {
      try {
        final health = await _checkHealth(candidate);
        fallback = candidate;
        fallbackHealth = health;
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

    final selectedFallbackHealth = fallbackHealth!;
    final now = ref.read(rpcEndpointFailoverClockProvider)();
    final event = RpcEndpointFailoverEvent(
      sequence: ++_eventSequence,
      kind: RpcEndpointFailoverEventKind.switchedToFallback,
      message: 'Selected endpoint is unstable. Switched to fallback endpoint.',
      endpoint: fallback,
    );
    log(
      'RpcEndpointFailover: switched ${attempted.hostPort} -> '
      '${fallback.hostPort} after $operation failure: $error',
    );
    state = state.copyWith(
      current: fallback,
      primaryFailureCount: nextFailureCount,
      lastFailure: error.toString(),
      switchedAt: now,
      lastPrimaryProbeAt: failedPrimary ? now : state.lastPrimaryProbeAt,
      lastEvent: event,
      heightWindowStartedAt: now,
      heightWindowStartHeight: selectedFallbackHealth.height,
      lastObservedHeight: selectedFallbackHealth.height,
      lastObservedAt: now,
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
    late final RpcEndpointHealth primaryHealth;
    try {
      primaryHealth = await _checkHealth(state.primary);
    } catch (e) {
      log(
        'RpcEndpointFailover: primary ${state.primary.hostPort} probe failed: $e',
      );
      return false;
    }

    final currentEndpoint = state.current;
    var currentHeight = state.lastObservedHeight;
    try {
      final currentHealth = await _checkHealth(currentEndpoint);
      currentHeight = _maxHeight(currentHeight, currentHealth.height);
      state = state.copyWith(
        lastObservedHeight: currentHeight,
        lastObservedAt: now,
      );
    } catch (e) {
      log(
        'RpcEndpointFailover: current fallback ${currentEndpoint.hostPort} '
        'probe failed while checking primary recovery: $e',
      );
    }

    final tolerance = BigInt.from(
      ref
          .read(rpcEndpointFailoverSettingsProvider)
          .primaryReturnLagToleranceBlocks,
    );
    if (currentHeight != null &&
        primaryHealth.height + tolerance < currentHeight) {
      log(
        'RpcEndpointFailover: primary ${state.primary.hostPort} probe lagging '
        'at height ${primaryHealth.height}; current height is $currentHeight',
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
      heightWindowStartedAt: now,
      heightWindowStartHeight: primaryHealth.height,
      lastObservedHeight: primaryHealth.height,
      lastObservedAt: now,
    );
    return true;
  }

  Future<RpcEndpointHealth?> _maybeSwitchFromSlowHeight(
    RpcEndpointConfig endpoint,
    BigInt height, {
    required String operation,
  }) async {
    if (!_isCurrentEndpoint(endpoint)) return null;

    final now = ref.read(rpcEndpointFailoverClockProvider)();
    final windowStartedAt = state.heightWindowStartedAt;
    final windowStartHeight = state.heightWindowStartHeight;
    if (windowStartedAt == null ||
        windowStartHeight == null ||
        height < windowStartHeight) {
      _resetHeightWindow(endpoint, height, now: now);
      return null;
    }

    state = state.copyWith(lastObservedHeight: height, lastObservedAt: now);

    final settings = ref.read(rpcEndpointFailoverSettingsProvider);
    if (now.difference(windowStartedAt) < settings.slowHeightWindow) {
      return null;
    }

    final heightIncrease = height - windowStartHeight;
    if (heightIncrease >= BigInt.from(settings.minHeightIncreaseInSlowWindow)) {
      _resetHeightWindow(endpoint, height, now: now);
      return null;
    }

    final fallback = await _findFallbackAheadOf(
      endpoint,
      currentHeight: height,
      operation: operation,
    );
    if (fallback == null) {
      log(
        'RpcEndpointFailover: ${endpoint.hostPort} height increased by '
        '$heightIncrease blocks in ${settings.slowHeightWindow.inSeconds}s, '
        'but no fallback endpoint is ahead enough; keeping current endpoint',
      );
      _resetHeightWindow(endpoint, height, now: now);
      return null;
    }

    final primaryUrl = state.primary.normalizedLightwalletdUrl;
    final failedPrimary = endpoint.normalizedLightwalletdUrl == primaryUrl;
    final event = RpcEndpointFailoverEvent(
      sequence: ++_eventSequence,
      kind: RpcEndpointFailoverEventKind.switchedToFallback,
      message: 'Selected endpoint is unstable. Switched to fallback endpoint.',
      endpoint: fallback.endpoint,
    );
    log(
      'RpcEndpointFailover: switched ${endpoint.hostPort} -> '
      '${fallback.endpoint.hostPort} because height only increased '
      'by $heightIncrease blocks in ${settings.slowHeightWindow.inSeconds}s '
      'during $operation and fallback is at height ${fallback.health.height}',
    );
    state = state.copyWith(
      current: fallback.endpoint,
      lastFailure:
          'Endpoint height increased by $heightIncrease blocks in '
          '${settings.slowHeightWindow.inSeconds}s.',
      switchedAt: now,
      lastPrimaryProbeAt: failedPrimary ? now : state.lastPrimaryProbeAt,
      lastEvent: event,
      heightWindowStartedAt: now,
      heightWindowStartHeight: fallback.health.height,
      lastObservedHeight: fallback.health.height,
      lastObservedAt: now,
    );
    return fallback.health;
  }

  Future<_FallbackHealth?> _findFallbackAheadOf(
    RpcEndpointConfig attempted, {
    required BigInt currentHeight,
    required String operation,
  }) async {
    final settings = ref.read(rpcEndpointFailoverSettingsProvider);
    final requiredHeight =
        currentHeight + BigInt.from(settings.slowFallbackLeadBlocks);
    final attemptedUrl = attempted.normalizedLightwalletdUrl;
    for (final candidate in state.fallbackCandidates) {
      if (candidate.normalizedLightwalletdUrl == attemptedUrl) continue;
      try {
        final health = await _checkHealth(candidate);
        if (health.height >= requiredHeight) {
          return _FallbackHealth(endpoint: candidate, health: health);
        }
        log(
          'RpcEndpointFailover: fallback ${candidate.hostPort} is not ahead '
          'enough for slow $operation; height=${health.height}, '
          'required>=$requiredHeight',
        );
      } catch (fallbackError) {
        log(
          'RpcEndpointFailover: fallback ${candidate.hostPort} failed health '
          'check during slow $operation fallback: $fallbackError',
        );
      }
    }
    return null;
  }

  void _resetHeightWindow(
    RpcEndpointConfig endpoint,
    BigInt height, {
    DateTime? now,
  }) {
    if (!_isCurrentEndpoint(endpoint)) return;
    final observedAt = now ?? ref.read(rpcEndpointFailoverClockProvider)();
    state = state.copyWith(
      heightWindowStartedAt: observedAt,
      heightWindowStartHeight: height,
      lastObservedHeight: height,
      lastObservedAt: observedAt,
    );
  }

  bool _isCurrentEndpoint(RpcEndpointConfig endpoint) {
    return endpoint.normalizedLightwalletdUrl ==
        state.current.normalizedLightwalletdUrl;
  }

  BigInt _maxHeight(BigInt? a, BigInt b) {
    if (a == null || b > a) return b;
    return a;
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
