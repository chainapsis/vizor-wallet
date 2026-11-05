import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../core/config/rpc_endpoint_config.dart';
import '../rust/api/wallet.dart' as rust_wallet;
import 'rpc_endpoint_provider.dart';
import 'automatic_rpc_endpoint_selection.dart';
import 'network_privacy_provider.dart';
import 'app_security_provider.dart';
import '../core/layout/app_process_work_policy.dart';
import '../core/lifecycle/app_shutdown_signal.dart';

typedef RpcEndpointChainNameGetter =
    Future<String> Function(String lightwalletdUrl);
typedef RpcEndpointLatestBlockHeightGetter =
    Future<BigInt> Function(String lightwalletdUrl, String network);

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
    this.automaticReady = true,
    this.automaticProvisional = false,
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
  final bool automaticReady;
  final bool automaticProvisional;

  RpcEndpointConfig? get fallback =>
      fallbackCandidates.isEmpty ? null : fallbackCandidates.first;

  bool get isUsingFallback =>
      !isAutomaticRpcEndpointConfig(primary) &&
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
    bool? automaticReady,
    bool? automaticProvisional,
  }) {
    return RpcEndpointFailoverState(
      automaticReady: automaticReady ?? this.automaticReady,
      automaticProvisional: automaticProvisional ?? this.automaticProvisional,
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

class _FailoverContext {
  const _FailoverContext({
    required this.generation,
    required this.automaticEpoch,
    required this.primary,
    required this.current,
    required this.fallbackCandidates,
  });

  final int generation;
  final int automaticEpoch;
  final RpcEndpointConfig primary;
  final RpcEndpointConfig current;
  final List<RpcEndpointConfig> fallbackCandidates;
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
  final height = await getLatestBlockHeight(
    endpoint.normalizedLightwalletdUrl,
    endpoint.networkName,
  );
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
          (lightwalletdUrl, network) => rust_wallet.getLatestBlockHeight(
            lightwalletdUrl: lightwalletdUrl,
            network: network,
          ),
    );

class _AutomaticTipObservation {
  const _AutomaticTipObservation({
    required this.endpoint,
    required this.sample,
    required this.epoch,
    required this.tor,
    required this.observedAt,
  });
  final RpcEndpointConfig endpoint;
  final RpcEndpointCandidateSample sample;
  final int epoch;
  final bool tor;
  final DateTime observedAt;
}

class RpcEndpointFailoverNotifier extends Notifier<RpcEndpointFailoverState> {
  int _eventSequence = 0;
  int _configGeneration = 0;
  int _automaticEpoch = 0;
  int _selectionPauseCount = 0;
  static int _selectionSequence = 0;
  Future<RpcEndpointConfig>? _automaticSelection;
  Future<BigInt>? _automaticTipFlight;
  bool _selectionIsValidation = false;
  bool _selectionIsWarmRead = false;
  bool _initialComparisonPending = false;
  bool _initialComparisonAllowed = false;
  _InitialEndpointImprovement? _initialImprovement;
  bool _needsWarmTipRead = false;
  DateTime? _lastSuccessAt;
  DateTime? _lastPeerValidatedAt;
  DateTime? _lastBenchmarkAt;
  DateTime? _lastNetworkVerifiedAt;
  DateTime? _lastCacheWriteAt;
  bool? _evaluatedTor;
  _AutomaticTipObservation? _pendingTip;
  DateTime? _validationDueAt;
  Duration? _selectedLatency;
  String? _selectionExcludeUrl;
  BigInt? _selectionMinimumHeight;
  String? _selectionId;
  void Function(String)? _cancelProbe;
  Completer<void>? _selectionCancelled;
  Future<void> _cacheWrites = Future.value();
  DateTime? _selectedAt;
  DateTime? _checkedAt;
  DateTime? _retryAt;
  int _failedSelections = 0;
  int _slowResponses = 0;
  final Map<String, DateTime> _cooldowns = {};
  bool _inForeground = true;
  AppLifecycleListener? _automaticLifecycle;

  @override
  RpcEndpointFailoverState build() {
    _configGeneration += 1;
    _cancelAutomaticWork();
    _selectedAt = null;
    _lastSuccessAt = null;
    _lastPeerValidatedAt = null;
    _lastBenchmarkAt = null;
    _lastNetworkVerifiedAt = null;
    _lastCacheWriteAt = null;
    _evaluatedTor = null;
    _pendingTip = null;
    _needsWarmTipRead = false;
    _selectedLatency = null;
    _validationDueAt = null;
    _initialComparisonPending = false;
    _initialComparisonAllowed = false;
    _initialImprovement = null;
    _checkedAt = null;
    _retryAt = null;
    _failedSelections = 0;
    _cooldowns.clear();
    ref.onDispose(() {
      _cancelAutomaticWork();
      _automaticLifecycle?.dispose();
      _automaticLifecycle = null;
    });
    final shutdown = ref.read(appShutdownSignalProvider);
    shutdown.addListener(cancelAutomaticSelection);
    ref.onDispose(() => shutdown.removeListener(cancelAutomaticSelection));
    ref.listen(networkPrivacyProvider, (previous, next) {
      if (previous == null) return;
      if ((previous.targetTorEnabled ?? previous.torEnabled) !=
              (next.targetTorEnabled ?? next.torEnabled) ||
          (!previous.isBusy && next.isBusy) ||
          next.status == NetworkPrivacyConnectionStatus.failed) {
        _retryAt = null;
        _failedSelections = 0;
        _cooldowns.clear();
        invalidateAutomaticSelection();
      }
    });
    ref.listen(appSecurityProvider.select((s) => s.requiresUnlock), (
      _,
      locked,
    ) {
      if (locked) cancelAutomaticSelection();
    });
    final primary = ref.watch(rpcEndpointProvider);
    return RpcEndpointFailoverState(
      primary: primary,
      current: primary,
      automaticReady: !isAutomaticRpcEndpointConfig(primary),
      fallbackCandidates: fallbackRpcEndpointCandidatesFor(primary),
    );
  }

  RpcEndpointConfig get currentEndpoint => state.current;

  /// Called only after a foreground sync stream has started. Startup never
  /// waits for this complete-pool comparison, and warm starts never schedule it.
  void startInitialComparisonAfterSyncStart() {
    _initialComparisonAllowed = true;
    _startInitialComparisonIfDue();
  }

  /// A performance correction takes effect at the next sync boundary. It does
  /// not interrupt a stream or inherit the periodic check's minimum residence.
  void applyPendingInitialComparison() {
    final pending = _initialImprovement;
    if (pending == null) return;
    _requireAutomaticEligibility();
    _initialImprovement = null;
    if (!_isUsableInitialImprovement(pending)) {
      _queueAutomaticCacheWrite(_automaticEpoch, force: true);
      return;
    }
    _publishAutomaticEndpoint(
      selected: pending.endpoint,
      sample: pending.sample,
      primary: state.primary,
      tor: pending.tor,
      epoch: _automaticEpoch,
      provisional: false,
    );
  }

  bool _isUsableInitialImprovement(_InitialEndpointImprovement pending) {
    final route = ref.read(networkPrivacyProvider);
    return isAutomaticRpcEndpointConfig(state.primary) &&
        state.automaticReady &&
        _isCurrentContext(pending.context) &&
        !route.isBusy &&
        (route.status == NetworkPrivacyConnectionStatus.off ||
            route.status == NetworkPrivacyConnectionStatus.connected) &&
        route.torEnabled == pending.tor &&
        isRecentEndpointObservation(
          pending.measuredAt,
          ref.read(rpcEndpointFailoverClockProvider)(),
          ref.read(automaticRpcEndpointSettingsProvider).warmReuseMaxAge,
        );
  }

  void _startInitialComparisonIfDue() {
    if (!ref.mounted ||
        !_initialComparisonPending ||
        !_initialComparisonAllowed ||
        _automaticSelection != null ||
        !state.automaticReady ||
        _needsWarmTipRead ||
        !isAutomaticRpcEndpointConfig(state.primary) ||
        _selectionPauseCount > 0 ||
        ref.read(appSecurityProvider).requiresUnlock ||
        !canRunAppProcessWork(
          isInForeground: _inForeground,
          shutdownSignal: ref.read(appShutdownSignalProvider),
        )) {
      return;
    }
    _initialComparisonPending = false;
    final epoch = _automaticEpoch;
    final cancelled = Completer<void>();
    _selectionCancelled = cancelled;
    // Recovery can supersede this optional work just like peer validation.
    _selectionIsValidation = true;
    _selectionExcludeUrl = null;
    _selectionMinimumHeight = null;
    late final Future<RpcEndpointConfig> comparison;
    comparison = _compareInitialEndpoints(epoch, cancelled).whenComplete(() {
      if (identical(_automaticSelection, comparison)) {
        _automaticSelection = null;
        _selectionIsValidation = false;
        _selectionId = null;
        _selectionCancelled = null;
      }
    });
    _automaticSelection = comparison;
    unawaited(
      comparison.then<void>(
        (_) {},
        onError: (Object error, StackTrace _) {
          log('Automatic endpoint initial comparison failed: $error');
        },
      ),
    );
  }

  Future<RpcEndpointConfig> _compareInitialEndpoints(
    int epoch,
    Completer<void> cancelled,
  ) async {
    final context = _captureContext();
    final tor = await _waitForRoute(cancelled);
    if (!_isCurrentContext(context) || cancelled.isCompleted) {
      throw _automaticSelectionStopped();
    }
    final settings = ref.read(automaticRpcEndpointSettingsProvider);
    final now = ref.read(rpcEndpointFailoverClockProvider)();
    final targets = automaticRpcEndpointCandidatesFor(context.primary)
        .where(
          (c) =>
              !(_cooldowns[c.normalizedLightwalletdUrl]?.isAfter(now) ?? false),
        )
        .toList();
    final concurrency = tor ? 2 : 4;
    final timeout = tor
        ? settings.torProbeTimeout
        : settings.directProbeTimeout;
    final waves = (targets.length + concurrency - 1) ~/ concurrency;
    final samples = await _probeAutomaticCandidates(
      targets: targets,
      primary: context.primary,
      epoch: epoch,
      cancelled: cancelled,
      probe: ref.read(rpcEndpointFullCandidatesProbeProvider),
      probeTimeout: timeout,
      // Reserve a full timeout for every wave, plus scheduling headroom.
      remaining: timeout * waves + const Duration(seconds: 1),
      maxConcurrency: concurrency,
    );
    if (!_isCurrentContext(context) || cancelled.isCompleted) {
      throw _automaticSelectionStopped();
    }
    _requireAutomaticEligibility();
    final ranked = rankAutomaticRpcEndpointSamples(
      samples,
      requireCorroboration: true,
    );
    final current = ranked
        .where((s) => s.url == context.current.normalizedLightwalletdUrl)
        .firstOrNull;
    // An optional performance comparison never replaces an unmeasured or
    // uncorroborated current server; normal health recovery owns that case.
    if (current == null || ranked.isEmpty) return state.current;
    final winner = ranked.first;
    final improvement =
        current.latency.inMilliseconds - winner.latency.inMilliseconds;
    if (winner.url == current.url ||
        improvement < 150 ||
        winner.latency.inMicroseconds > current.latency.inMicroseconds * 0.7) {
      return state.current;
    }
    _initialImprovement = _InitialEndpointImprovement(
      context: context,
      endpoint: targets.firstWhere(
        (c) => c.normalizedLightwalletdUrl == winner.url,
      ),
      sample: winner,
      measuredAt: ref.read(rpcEndpointFailoverClockProvider)(),
      tor: tor,
    );
    // Persist the recommendation for a restart, while the active stream and
    // current endpoint keep using their original server until the next sync.
    _queueAutomaticCacheWrite(epoch, force: true);
    return state.current;
  }

  /// A single network boundary for all automatic-mode consumers. Reading the
  /// preference or building a settings widget never starts endpoint probes.
  Future<RpcEndpointConfig> ensureReady() => _ensureReadyForOperation();

  Future<RpcEndpointConfig> _ensureReadyForOperation({
    bool forTipRead = false,
  }) async {
    if (!isAutomaticRpcEndpointConfig(state.primary)) return state.current;
    _trackAutomaticLifecycle();
    _requireAutomaticEligibility();
    final nowBefore = ref.read(rpcEndpointFailoverClockProvider)();
    final policy = ref.read(automaticRpcEndpointSettingsProvider);
    if (state.automaticReady &&
        _evaluatedTor != null &&
        (!isRecentEndpointObservation(
              _lastNetworkVerifiedAt,
              nowBefore,
              policy.cacheMaxAge,
            ) ||
            (_needsWarmTipRead &&
                !isRecentEndpointObservation(
                  _lastSuccessAt,
                  nowBefore,
                  policy.warmReuseMaxAge,
                )))) {
      invalidateAutomaticSelection();
    }
    if (!state.automaticReady) await _ensureAutomatic();
    _requireAutomaticEligibility();
    if (!forTipRead && _needsWarmTipRead) await _ensureWarmTipRead();
    final settings = ref.read(automaticRpcEndpointSettingsProvider);
    final now = ref.read(rpcEndpointFailoverClockProvider)();
    if (!_hasFreshPeerProof(now)) {
      state = state.copyWith(automaticProvisional: true);
    }
    if (!_needsWarmTipRead &&
        (_checkedAt == null ||
            now.difference(_checkedAt!) >= settings.recheckInterval)) {
      unawaited(
        _ensureAutomatic(force: true).then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            log('Automatic endpoint recheck failed: $error');
          },
        ),
      );
    } else if (state.automaticProvisional) {
      _startProvisionalValidationIfDue();
    }
    return state.current;
  }

  void _requireAutomaticEligibility() {
    if (!ref.mounted ||
        _selectionPauseCount > 0 ||
        ref.read(appSecurityProvider).requiresUnlock ||
        !canRunAppProcessWork(
          isInForeground: _inForeground,
          shutdownSignal: ref.read(appShutdownSignalProvider),
        )) {
      throw StateError('Automatic endpoint selection is paused.');
    }
  }

  bool _hasFreshPeerProof(DateTime now) => isRecentEndpointObservation(
    _lastPeerValidatedAt,
    now,
    ref.read(automaticRpcEndpointSettingsProvider).recheckInterval,
  );

  bool _canRetainAutomaticHealth() {
    if (!ref.mounted || !state.automaticReady) return false;
    final route = ref.read(networkPrivacyProvider);
    return !route.isBusy &&
        (route.status == NetworkPrivacyConnectionStatus.off ||
            route.status == NetworkPrivacyConnectionStatus.connected) &&
        _evaluatedTor == route.torEnabled &&
        isRecentEndpointObservation(
          _lastSuccessAt,
          ref.read(rpcEndpointFailoverClockProvider)(),
          ref.read(automaticRpcEndpointSettingsProvider).warmReuseMaxAge,
        );
  }

  void _trackAutomaticLifecycle() {
    if (_automaticLifecycle != null) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _inForeground =
        lifecycle != AppLifecycleState.hidden &&
        lifecycle != AppLifecycleState.paused &&
        lifecycle != AppLifecycleState.detached;
    _automaticLifecycle = AppLifecycleListener(
      onResume: () => _inForeground = true,
      onHide: () {
        _inForeground = false;
        if (!canRunAppProcessWork(isInForeground: false)) {
          cancelAutomaticSelection();
        }
      },
    );
  }

  void _cancelAutomaticWork() {
    ++_automaticEpoch;
    final id = _selectionId;
    if (id != null) _cancelProbe?.call(id);
    final signal = _selectionCancelled;
    if (signal != null && !signal.isCompleted) signal.complete();
    _selectionId = null;
    _automaticSelection = null;
    _automaticTipFlight = null;
    _selectionIsValidation = false;
    _selectionIsWarmRead = false;
    _selectionCancelled = null;
    _pendingTip = null;
    _initialComparisonPending = false;
    _initialComparisonAllowed = false;
    _initialImprovement = null;
  }

  /// Stops process work without throwing away recent public server evidence.
  void cancelAutomaticSelection() {
    final retain = _canRetainAutomaticHealth();
    _cancelAutomaticWork();
    _needsWarmTipRead = retain;
    if (ref.mounted && isAutomaticRpcEndpointConfig(state.primary)) {
      state = state.copyWith(automaticReady: retain);
    }
  }

  /// Route, preferences and destructive operations invalidate cached readiness.
  void invalidateAutomaticSelection() {
    _cancelAutomaticWork();
    _checkedAt = null;
    _lastSuccessAt = null;
    _lastPeerValidatedAt = null;
    _lastBenchmarkAt = null;
    _lastNetworkVerifiedAt = null;
    _lastCacheWriteAt = null;
    _evaluatedTor = null;
    _needsWarmTipRead = false;
    if (ref.mounted && isAutomaticRpcEndpointConfig(state.primary)) {
      state = state.copyWith(
        automaticReady: false,
        automaticProvisional: false,
        clearLastObservedHeight: true,
        clearLastObservedAt: true,
        clearHeightWindowStartedAt: true,
        clearHeightWindowStartHeight: true,
      );
    }
  }

  void pauseAutomaticSelection() {
    _selectionPauseCount++;
    invalidateAutomaticSelection();
  }

  void resumeAutomaticSelection() {
    if (_selectionPauseCount > 0) _selectionPauseCount--;
  }

  Future<void> clearAutomaticSelectionCache() async {
    invalidateAutomaticSelection();
    _cooldowns.clear();
    _retryAt = null;
    _failedSelections = 0;
    await _cacheWrites;
    try {
      await ref.read(automaticRpcEndpointStoreProvider).clear();
    } catch (error) {
      log('Automatic endpoint cache cleanup failed: $error');
    }
  }

  StateError _automaticSelectionStopped({bool routeBlocked = false}) {
    if (ref.mounted &&
        _selectionPauseCount == 0 &&
        isAutomaticRpcEndpointConfig(state.primary) &&
        !ref.read(appSecurityProvider).requiresUnlock &&
        canRunAppProcessWork(
          isInForeground: _inForeground,
          shutdownSignal: ref.read(appShutdownSignalProvider),
        )) {
      final route = ref.read(networkPrivacyProvider);
      if (route.torRouteRetained &&
          route.status == NetworkPrivacyConnectionStatus.failed) {
        // A failed bootstrap also cancels pending selection work. Preserve
        // its actionable cause so Home Retry restarts Tor rather than sync.
        return StateError(
          'Network privacy blocked automatic endpoint selection: '
          'Tor is enabled but unavailable.',
        );
      }
    }
    return StateError(
      routeBlocked
          ? 'Network privacy blocked automatic endpoint selection.'
          : 'Automatic endpoint selection cancelled.',
    );
  }

  Future<bool> _waitForRoute(Completer<void> cancelled) async {
    bool ready(NetworkPrivacyState route) =>
        !route.isBusy &&
        (route.status == NetworkPrivacyConnectionStatus.off ||
            route.status == NetworkPrivacyConnectionStatus.connected);
    var route = ref.read(networkPrivacyProvider);
    if (!ready(route) && route.isBusy) {
      final changed = Completer<void>();
      final subscription = ref.listen(networkPrivacyProvider, (_, next) {
        if (!next.isBusy && !changed.isCompleted) changed.complete();
      });
      try {
        await Future.any([changed.future, cancelled.future]);
      } finally {
        subscription.close();
      }
      if (cancelled.isCompleted || !ref.mounted) {
        throw _automaticSelectionStopped();
      }
      route = ref.read(networkPrivacyProvider);
    }
    if (!ready(route)) {
      throw _automaticSelectionStopped(routeBlocked: true);
    }
    return route.torEnabled;
  }

  Future<RpcEndpointConfig> _ensureAutomatic({
    bool force = false,
    String? excludeUrl,
    BigInt? minimumHeight,
  }) {
    if (!ref.mounted) {
      return Future.error(_automaticSelectionStopped());
    }
    _trackAutomaticLifecycle();
    if (_selectionPauseCount > 0 ||
        ref.read(appSecurityProvider).requiresUnlock ||
        !canRunAppProcessWork(
          isInForeground: _inForeground,
          shutdownSignal: ref.read(appShutdownSignalProvider),
        )) {
      return Future.error(
        StateError('Automatic endpoint selection is paused.'),
      );
    }
    final pending = _automaticSelection;
    if (pending != null) {
      if ((excludeUrl == null && minimumHeight == null) ||
          (!_selectionIsValidation &&
              excludeUrl == _selectionExcludeUrl &&
              minimumHeight == _selectionMinimumHeight)) {
        return pending;
      }
      _cancelAutomaticWork();
    }
    _selectionIsValidation = false;
    _selectionIsWarmRead = false;
    _selectionExcludeUrl = excludeUrl;
    _selectionMinimumHeight = minimumHeight;
    final now = ref.read(rpcEndpointFailoverClockProvider)();
    if (_retryAt != null && now.isBefore(_retryAt!)) {
      return Future.error(
        StateError('No automatic endpoint is available; retry pending.'),
      );
    }
    final epoch = _automaticEpoch;
    final cancelled = Completer<void>();
    _selectionCancelled = cancelled;
    late final Future<RpcEndpointConfig> selection;
    selection =
        _selectAutomatic(
          epoch: epoch,
          cancelled: cancelled,
          force: force,
          excludeUrl: excludeUrl,
          minimumHeight: minimumHeight,
        ).whenComplete(() {
          if (identical(_automaticSelection, selection)) {
            _automaticSelection = null;
            _selectionId = null;
            _selectionCancelled = null;
            _startInitialComparisonIfDue();
          }
        });
    _automaticSelection = selection;
    return selection;
  }

  Future<RpcEndpointConfig> _selectAutomatic({
    required int epoch,
    required Completer<void> cancelled,
    required bool force,
    String? excludeUrl,
    BigInt? minimumHeight,
    Duration? budgetOverride,
  }) async {
    final tor = await _waitForRoute(cancelled);
    void requireCurrent() {
      if (!ref.mounted || epoch != _automaticEpoch || cancelled.isCompleted) {
        throw _automaticSelectionStopped();
      }
    }

    requireCurrent();
    final primary = state.primary;
    final previous = state.current;
    final hadReady = state.automaticReady;
    final settings = ref.read(automaticRpcEndpointSettingsProvider);
    final clock = ref.read(rpcEndpointFailoverClockProvider);
    final store = ref.read(automaticRpcEndpointStoreProvider);
    final probe = ref.read(rpcEndpointCandidatesProbeProvider);
    _cancelProbe = ref.read(rpcEndpointSelectionCancelProvider);
    final now = clock();
    final candidates = automaticRpcEndpointCandidatesFor(primary).where((
      candidate,
    ) {
      final url = candidate.normalizedLightwalletdUrl;
      return url != excludeUrl && !(_cooldowns[url]?.isAfter(now) ?? false);
    }).toList();
    if (candidates.isEmpty) {
      final deadlines =
          _cooldowns.values.where((at) => at.isAfter(now)).toList()..sort();
      _retryAt = deadlines.firstOrNull;
      throw StateError(
        'No automatic endpoint is available; all candidates are cooling down.',
      );
    }
    // Rotate a region/operator-diverse list. Cache preference is applied below;
    // no geography service or device location permission is needed.
    final offset = _selectionSequence++ % candidates.length;
    final ordered = [...candidates.skip(offset), ...candidates.take(offset)];
    if (hadReady) {
      final index = ordered.indexWhere(
        (c) =>
            c.normalizedLightwalletdUrl == previous.normalizedLightwalletdUrl,
      );
      if (index > 0) ordered.insert(0, ordered.removeAt(index));
    }
    AutomaticRpcEndpointCache? cached;
    if (!force && !hadReady) {
      try {
        cached = await Future.any<AutomaticRpcEndpointCache?>([
          store.read(primary.networkName, tor),
          cancelled.future.then((_) => null),
        ]).timeout(const Duration(milliseconds: 250));
      } catch (_) {
        /* Optional cache; connectivity is independent of storage. */
      }
    }
    requireCurrent();
    final budget =
        budgetOverride ?? (tor ? settings.torBudget : settings.directBudget);
    final timeout = tor
        ? settings.torProbeTimeout
        : settings.directProbeTimeout;
    final stopwatch = Stopwatch()..start();
    final samples = <RpcEndpointCandidateSample>[];
    Future<List<RpcEndpointCandidateSample>> check(
      List<RpcEndpointConfig> targets,
      Duration remaining,
    ) => _probeAutomaticCandidates(
      targets: targets,
      primary: primary,
      epoch: epoch,
      cancelled: cancelled,
      probe: probe,
      probeTimeout: timeout,
      remaining: remaining,
      maxConcurrency: tor ? 2 : 4,
    );

    try {
      final cacheAge = cached == null
          ? null
          : now.difference(cached.observedAt);
      final preferred = ordered
          .where((c) => c.presetId == cached?.presetId)
          .firstOrNull;
      final hasUsableCache =
          preferred != null &&
          cacheAge != null &&
          !cacheAge.isNegative &&
          cacheAge < settings.cacheMaxAge;
      if (preferred != null &&
          cacheAge != null &&
          !cacheAge.isNegative &&
          cacheAge < settings.cacheMaxAge) {
        if (cached!.isWarm(
          now,
          settings,
          expectedUrl: preferred.normalizedLightwalletdUrl,
        )) {
          _lastSuccessAt = cached.lastSuccessAt;
          _lastPeerValidatedAt =
              isRecentEndpointObservation(
                cached.lastPeerValidatedAt,
                now,
                settings.recheckInterval,
              )
              ? cached.lastPeerValidatedAt
              : null;
          _lastBenchmarkAt =
              cached.lastBenchmarkAt != null &&
                  !cached.lastBenchmarkAt!.isAfter(now)
              ? cached.lastBenchmarkAt
              : null;
          _lastNetworkVerifiedAt =
              cached.lastNetworkVerifiedAt ?? cached.lastBenchmarkAt;
          _checkedAt = _lastBenchmarkAt;
          _selectedAt = cached.observedAt;
          _selectedLatency = cached.latencyMs == null
              ? null
              : Duration(milliseconds: cached.latencyMs!);
          _evaluatedTor = tor;
          _needsWarmTipRead = true;
          state = state.copyWith(
            current: preferred,
            automaticReady: true,
            automaticProvisional: !_hasFreshPeerProof(now),
            clearLastObservedHeight: true,
            clearLastObservedAt: true,
            clearHeightWindowStartedAt: true,
            clearHeightWindowStartHeight: true,
          );
          return preferred;
        }
        // A cached endpoint gets a short head start, never an entire long
        // request timeout before other regions become eligible.
        try {
          samples.addAll(
            await check(
              [preferred],
              (tor
                          ? const Duration(seconds: 2)
                          : const Duration(milliseconds: 750)) <
                      budget
                  ? (tor
                        ? const Duration(seconds: 2)
                        : const Duration(milliseconds: 750))
                  : budget,
            ),
          );
        } catch (_) {
          requireCurrent();
        }
      }
      requireCurrent();
      final remaining = budget - stopwatch.elapsed;
      if (samples.isEmpty && remaining > Duration.zero) {
        samples.addAll(await check(ordered, remaining));
      }
      requireCurrent();
      final allowed = {
        for (final c in candidates) c.normalizedLightwalletdUrl: c,
      };
      final valid = samples.where((s) => allowed.containsKey(s.url)).toList();
      final ranked = rankAutomaticRpcEndpointSamples(
        valid,
        minimumHeight: minimumHeight,
      );
      if (ranked.isEmpty) {
        throw StateError('No healthy automatic endpoint is available.');
      }
      var winner = ranked.first;
      final residence = _selectedAt == null
          ? Duration.zero
          : now.difference(_selectedAt!);
      if (hadReady &&
          excludeUrl == null &&
          minimumHeight == null &&
          residence < settings.minimumResidence) {
        _checkedAt = clock();
        return previous;
      }
      // Performance-driven rechecks retain a healthy current server unless a
      // materially faster candidate justifies paying for a new connection.
      final currentSample = ranked
          .where((s) => s.url == previous.normalizedLightwalletdUrl)
          .firstOrNull;
      if (hadReady &&
          excludeUrl == null &&
          minimumHeight == null &&
          currentSample != null) {
        final residence = _selectedAt == null
            ? Duration.zero
            : now.difference(_selectedAt!);
        final improvement =
            currentSample.latency.inMilliseconds -
            winner.latency.inMilliseconds;
        if (residence < settings.minimumResidence ||
            improvement < 150 ||
            winner.latency.inMicroseconds >
                currentSample.latency.inMicroseconds * 0.7) {
          winner = currentSample;
        }
      }
      final provisional = rankAutomaticRpcEndpointSamples(
        valid,
        requireCorroboration: true,
      ).isEmpty;
      final selected = _publishAutomaticEndpoint(
        selected: allowed[winner.url]!,
        sample: winner,
        primary: primary,
        tor: tor,
        epoch: epoch,
        provisional: provisional,
      );
      if (!hadReady && !force && excludeUrl == null && !hasUsableCache) {
        _initialComparisonPending = true;
      }
      _pendingTip = _AutomaticTipObservation(
        endpoint: selected,
        sample: winner,
        epoch: epoch,
        tor: tor,
        observedAt: clock(),
      );
      if (provisional) {
        _validationDueAt = clock();
        // The selection slot must be released before independent validation
        // starts. Its result never holds up the first usable operation.
        final completed = _automaticSelection;
        if (completed != null) {
          unawaited(
            completed.then<void>((_) {
              if (ref.mounted && epoch == _automaticEpoch) {
                _startProvisionalValidationIfDue();
              }
            }, onError: (Object _, StackTrace _) {}),
          );
        }
      }
      return selected;
    } catch (error) {
      requireCurrent();
      if (hadReady && excludeUrl == null && minimumHeight == null) {
        // An exploratory check must not turn a working connection into an
        // outage when no better alternative could be measured.
        _checkedAt = clock();
        return previous;
      }
      final message = error.toString().toLowerCase();
      if (message.contains('network privacy blocked') ||
          message.contains('cancelled')) {
        rethrow;
      }
      _failedSelections++;
      final seconds = (5 * (1 << (_failedSelections - 1).clamp(0, 4))).clamp(
        5,
        60,
      );
      _retryAt = clock().add(Duration(seconds: seconds));
      if (!hadReady || excludeUrl != null) {
        state = state.copyWith(
          automaticReady: false,
          lastFailure: error.toString(),
        );
      }
      rethrow;
    }
  }

  Future<RpcEndpointConfig> _ensureWarmTipRead() {
    if (!_needsWarmTipRead) return Future.value(state.current);
    _requireAutomaticEligibility();
    final pending = _automaticSelection;
    if (pending != null) {
      if (_selectionIsWarmRead) return pending;
      return pending.then((_) => _ensureWarmTipRead());
    }
    final epoch = _automaticEpoch;
    final cancelled = Completer<void>();
    _selectionCancelled = cancelled;
    _selectionIsValidation = false;
    _selectionIsWarmRead = true;
    _selectionExcludeUrl = null;
    _selectionMinimumHeight = null;
    late final Future<RpcEndpointConfig> read;
    read = _readWarmTip(epoch, cancelled).whenComplete(() {
      if (identical(_automaticSelection, read)) {
        _automaticSelection = null;
        _selectionIsWarmRead = false;
        _selectionId = null;
        _selectionCancelled = null;
      }
    });
    _automaticSelection = read;
    return read;
  }

  Future<RpcEndpointConfig> _readWarmTip(
    int epoch,
    Completer<void> cancelled,
  ) async {
    final endpoint = state.current;
    final tor = await _waitForRoute(cancelled);
    void requireCurrent() {
      if (!ref.mounted ||
          epoch != _automaticEpoch ||
          cancelled.isCompleted ||
          !_sameEndpointIdentity(endpoint, state.current)) {
        throw _automaticSelectionStopped();
      }
      _requireAutomaticEligibility();
    }

    requireCurrent();
    final settings = ref.read(automaticRpcEndpointSettingsProvider);
    final timeout = settings.warmTipTimeout(
      tor: tor,
      recentLatency: _selectedLatency,
    );
    final watch = Stopwatch()..start();
    final read = ref.read(rpcEndpointWarmTipReaderProvider);
    _cancelProbe = ref.read(rpcEndpointSelectionCancelProvider);
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${_selectionSequence++}';
    _selectionId = id;
    try {
      final sample =
          await Future.any([
            read(endpoint: endpoint, selectionId: id, timeout: timeout),
            cancelled.future.then<RpcEndpointCandidateSample>(
              (_) => throw _automaticSelectionStopped(),
            ),
          ]).timeout(
            timeout,
            onTimeout: () {
              _cancelProbe?.call(id);
              throw TimeoutException(
                'Cached endpoint tip read timed out.',
                timeout,
              );
            },
          );
      requireCurrent();
      if (sample.url != endpoint.normalizedLightwalletdUrl) {
        throw StateError('Cached endpoint returned a different route.');
      }
      final now = ref.read(rpcEndpointFailoverClockProvider)();
      _needsWarmTipRead = false;
      _recordAutomaticTipSuccess(endpoint, sample, epoch, tor, now);
      _pendingTip = _AutomaticTipObservation(
        endpoint: endpoint,
        sample: sample,
        epoch: epoch,
        tor: tor,
        observedAt: now,
      );
      return endpoint;
    } catch (error) {
      requireCurrent();
      if (error.toString().toLowerCase().contains('network privacy blocked')) {
        rethrow;
      }
      // A warm-read error may be local or hide its underlying cause. Exclude
      // this host for this recovery only, without recording a host cooldown.
      _needsWarmTipRead = false;
      _selectionIsWarmRead = false;
      _pendingTip = null;
      state = state.copyWith(automaticReady: false);
      // This is still the same cancellable, coalesced read operation. Selection
      // supplies a real replacement tip; callers never replay a broadcast.
      final remaining =
          (tor ? settings.torBudget : settings.directBudget) - watch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Automatic endpoint recovery timed out.');
      }
      return _selectAutomatic(
        epoch: epoch,
        cancelled: cancelled,
        force: true,
        excludeUrl: endpoint.normalizedLightwalletdUrl,
        budgetOverride: remaining,
      );
    }
  }

  bool _sameAutomaticRoute(bool tor) {
    final route = ref.read(networkPrivacyProvider);
    return !route.isBusy &&
        route.torEnabled == tor &&
        (route.status == NetworkPrivacyConnectionStatus.off ||
            route.status == NetworkPrivacyConnectionStatus.connected);
  }

  RpcEndpointCandidateSample? _takePendingAutomaticTip(
    RpcEndpointConfig endpoint,
  ) {
    final tip = _pendingTip;
    _pendingTip = null;
    if (tip == null ||
        tip.epoch != _automaticEpoch ||
        !_sameEndpointIdentity(tip.endpoint, endpoint) ||
        !_sameAutomaticRoute(tip.tor) ||
        !isRecentEndpointObservation(
          tip.observedAt,
          ref.read(rpcEndpointFailoverClockProvider)(),
          ref.read(automaticRpcEndpointSettingsProvider).tipReuseMaxAge,
        )) {
      return null;
    }
    return tip.sample;
  }

  void _recordAutomaticTipSuccess(
    RpcEndpointConfig endpoint,
    RpcEndpointCandidateSample sample,
    int epoch,
    bool tor,
    DateTime observedAt,
  ) {
    if (!ref.mounted ||
        epoch != _automaticEpoch ||
        !_sameAutomaticRoute(tor) ||
        !_isCurrentEndpoint(endpoint) ||
        !isAutomaticRpcEndpointConfig(state.primary)) {
      return;
    }
    _lastSuccessAt = observedAt;
    _evaluatedTor = tor;
    _selectedLatency = sample.latency;
    state = state.copyWith(
      lastObservedHeight: sample.height,
      lastObservedAt: observedAt,
      automaticProvisional: !_hasFreshPeerProof(observedAt),
    );
    _queueAutomaticCacheWrite(epoch);
  }

  Future<List<RpcEndpointCandidateSample>> _probeAutomaticCandidates({
    required List<RpcEndpointConfig> targets,
    required RpcEndpointConfig primary,
    required int epoch,
    required Completer<void> cancelled,
    required RpcEndpointCandidatesProbe probe,
    required Duration probeTimeout,
    required Duration remaining,
    required int maxConcurrency,
  }) async {
    if (!ref.mounted || epoch != _automaticEpoch || cancelled.isCompleted) {
      throw _automaticSelectionStopped();
    }
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${_selectionSequence++}';
    _selectionId = id;
    final samples =
        await Future.any([
          probe(
            urls: targets.map((c) => c.normalizedLightwalletdUrl).toList(),
            network: primary.networkName,
            selectionId: id,
            probeTimeout: probeTimeout < remaining ? probeTimeout : remaining,
            totalTimeout: remaining,
            maxConcurrency: maxConcurrency,
          ),
          cancelled.future.then<List<RpcEndpointCandidateSample>>(
            (_) => throw _automaticSelectionStopped(),
          ),
        ]).timeout(
          remaining,
          onTimeout: () {
            _cancelProbe?.call(id);
            throw TimeoutException(
              'Automatic endpoint selection timed out.',
              remaining,
            );
          },
        );
    final allowed = targets.map((c) => c.normalizedLightwalletdUrl).toSet();
    return samples.where((sample) => allowed.contains(sample.url)).toList();
  }

  RpcEndpointConfig _publishAutomaticEndpoint({
    required RpcEndpointConfig selected,
    required RpcEndpointCandidateSample sample,
    required RpcEndpointConfig primary,
    required bool tor,
    required int epoch,
    required bool provisional,
    bool benchmark = true,
  }) {
    final observedAt = ref.read(rpcEndpointFailoverClockProvider)();
    final changed = !_sameEndpointIdentity(selected, state.current);
    if (changed) {
      _initialImprovement = null;
      _selectedAt = observedAt;
      _lastPeerValidatedAt = null;
      _pendingTip = null;
    }
    _selectedAt ??= observedAt;
    _selectedLatency = sample.latency;
    _lastSuccessAt = observedAt;
    _evaluatedTor = tor;
    _needsWarmTipRead = false;
    if (!provisional) _lastPeerValidatedAt = observedAt;
    if (benchmark) _lastBenchmarkAt = observedAt;
    if (benchmark || changed) _lastNetworkVerifiedAt = observedAt;
    _checkedAt = _lastBenchmarkAt;
    _retryAt = null;
    _failedSelections = 0;
    _slowResponses = 0;
    state = state.copyWith(
      current: selected,
      automaticReady: true,
      automaticProvisional: provisional,
      clearLastFailure: true,
      heightWindowStartedAt: observedAt,
      heightWindowStartHeight: sample.height,
      lastObservedHeight: sample.height,
      lastObservedAt: observedAt,
    );
    _queueAutomaticCacheWrite(epoch, force: true);
    return selected;
  }

  void _queueAutomaticCacheWrite(int epoch, {bool force = false}) {
    if (!ref.mounted ||
        epoch != _automaticEpoch ||
        _lastSuccessAt == null ||
        _evaluatedTor == null) {
      return;
    }
    final now = ref.read(rpcEndpointFailoverClockProvider)();
    if (!force &&
        isRecentEndpointObservation(
          _lastCacheWriteAt,
          now,
          ref.read(automaticRpcEndpointSettingsProvider).cacheWriteInterval,
        )) {
      return;
    }
    _lastCacheWriteAt = now;
    final store = ref.read(automaticRpcEndpointStoreProvider);
    final pending = _initialImprovement;
    final usePending = pending != null && _isUsableInitialImprovement(pending);
    final endpoint = usePending ? pending.endpoint : state.current;
    final tor = usePending ? pending.tor : _evaluatedTor!;
    final cache = AutomaticRpcEndpointCache(
      presetId: endpoint.presetId!,
      observedAt: usePending ? pending.measuredAt : _lastSuccessAt!,
      lastSuccessAt: usePending ? pending.measuredAt : _lastSuccessAt,
      lastPeerValidatedAt: usePending
          ? pending.measuredAt
          : _lastPeerValidatedAt,
      lastBenchmarkAt: usePending ? pending.measuredAt : _lastBenchmarkAt,
      lastNetworkVerifiedAt: usePending
          ? pending.measuredAt
          : _lastNetworkVerifiedAt,
      latencyMs: usePending
          ? pending.sample.latency.inMilliseconds
          : _selectedLatency?.inMilliseconds,
      endpointUrl: endpoint.normalizedLightwalletdUrl,
    );
    _cacheWrites = _cacheWrites.then((_) async {
      if (!ref.mounted || epoch != _automaticEpoch) return;
      try {
        await store.write(endpoint.networkName, tor, cache);
      } catch (error) {
        log('Automatic endpoint cache write failed: $error');
      }
    });
  }

  void _startProvisionalValidationIfDue() {
    if (!ref.mounted ||
        _automaticSelection != null ||
        !state.automaticReady ||
        _needsWarmTipRead ||
        state.lastObservedHeight == null ||
        !state.automaticProvisional ||
        _selectionPauseCount > 0 ||
        ref.read(appSecurityProvider).requiresUnlock ||
        !canRunAppProcessWork(
          isInForeground: _inForeground,
          shutdownSignal: ref.read(appShutdownSignalProvider),
        )) {
      return;
    }
    final now = ref.read(rpcEndpointFailoverClockProvider)();
    if (_validationDueAt != null && now.isBefore(_validationDueAt!)) return;
    _validationDueAt = now.add(
      ref.read(automaticRpcEndpointSettingsProvider).provisionalRecheckInterval,
    );
    final epoch = _automaticEpoch;
    final cancelled = Completer<void>();
    _selectionCancelled = cancelled;
    _selectionIsValidation = true;
    _selectionExcludeUrl = state.current.normalizedLightwalletdUrl;
    _selectionMinimumHeight = null;
    late final Future<RpcEndpointConfig> validation;
    validation = _validateProvisionalEndpoint(epoch, cancelled).whenComplete(
      () {
        if (identical(_automaticSelection, validation)) {
          _automaticSelection = null;
          _selectionIsValidation = false;
          _selectionId = null;
          _selectionCancelled = null;
          _startInitialComparisonIfDue();
        }
      },
    );
    _automaticSelection = validation;
    unawaited(
      validation.then<void>(
        (_) {},
        onError: (Object error, StackTrace _) {
          log('Automatic endpoint freshness validation failed: $error');
        },
      ),
    );
  }

  Future<RpcEndpointConfig> _validateProvisionalEndpoint(
    int epoch,
    Completer<void> cancelled,
  ) async {
    final primary = state.primary;
    final current = state.current;
    void requireCurrent() {
      if (!ref.mounted ||
          epoch != _automaticEpoch ||
          cancelled.isCompleted ||
          !_sameEndpointIdentity(current, state.current) ||
          !state.automaticReady) {
        throw _automaticSelectionStopped();
      }
    }

    final tor = await _waitForRoute(cancelled);
    requireCurrent();
    final settings = ref.read(automaticRpcEndpointSettingsProvider);
    final clock = ref.read(rpcEndpointFailoverClockProvider);
    final probe = ref.read(rpcEndpointCandidatesProbeProvider);
    _cancelProbe = ref.read(rpcEndpointSelectionCancelProvider);
    final budget = tor ? settings.torBudget : settings.directBudget;
    final timeout = tor
        ? settings.torProbeTimeout
        : settings.directProbeTimeout;
    final watch = Stopwatch()..start();
    final now = clock();
    final peers = automaticRpcEndpointCandidatesFor(primary)
        .where(
          (candidate) =>
              candidate.normalizedLightwalletdUrl !=
                  current.normalizedLightwalletdUrl &&
              !(_cooldowns[candidate.normalizedLightwalletdUrl]?.isAfter(now) ??
                  false),
        )
        .toList();
    final observations = <String, RpcEndpointCandidateSample>{};
    RpcEndpointCandidateSample currentSample() => RpcEndpointCandidateSample(
      url: current.normalizedLightwalletdUrl,
      height: state.lastObservedHeight!,
      latency: _selectedLatency ?? Duration.zero,
    );
    List<RpcEndpointCandidateSample> corroborated() =>
        rankAutomaticRpcEndpointSamples([
          currentSample(),
          ...observations.values,
        ], requireCorroboration: true);
    try {
      var ranked = <RpcEndpointCandidateSample>[];
      // Every successful round removes at least one distinct host from the
      // remaining targets. Keep looking through conflicting fast peers until
      // a cluster agrees, the finite pool is exhausted, or the one budget ends.
      while (ranked.isEmpty) {
        final remaining = budget - watch.elapsed;
        final targets = peers
            .where(
              (candidate) => !observations.containsKey(
                candidate.normalizedLightwalletdUrl,
              ),
            )
            .toList();
        if (remaining <= Duration.zero || targets.isEmpty) break;
        final observedBefore = observations.length;
        final samples = await _probeAutomaticCandidates(
          targets: targets,
          primary: primary,
          epoch: epoch,
          cancelled: cancelled,
          probe: probe,
          probeTimeout: timeout,
          remaining: remaining,
          maxConcurrency: tor ? 2 : 4,
        );
        requireCurrent();
        for (final sample in samples) {
          observations[sample.url] = sample;
        }
        // Empty or invalid replies cannot spin without making progress.
        if (observations.length == observedBefore) break;
        ranked = corroborated();
      }
      requireCurrent();
      if (ranked.isEmpty) return current;
      var winner = ranked.first;
      final verifiedCurrent = ranked
          .where((s) => s.url == current.normalizedLightwalletdUrl)
          .firstOrNull;
      if (verifiedCurrent != null) {
        final residence = _selectedAt == null
            ? Duration.zero
            : clock().difference(_selectedAt!);
        final improvement =
            verifiedCurrent.latency.inMilliseconds -
            winner.latency.inMilliseconds;
        if (residence < settings.minimumResidence ||
            improvement < 150 ||
            winner.latency.inMicroseconds >
                verifiedCurrent.latency.inMicroseconds * 0.7) {
          winner = verifiedCurrent;
        }
      }
      final selected = winner.url == current.normalizedLightwalletdUrl
          ? current
          : peers.firstWhere((c) => c.normalizedLightwalletdUrl == winner.url);
      return _publishAutomaticEndpoint(
        selected: selected,
        sample: winner,
        primary: primary,
        tor: tor,
        epoch: epoch,
        provisional: false,
        benchmark: false,
      );
    } catch (error) {
      requireCurrent();
      // A provisional success is still usable while independent peers are
      // unavailable. The next ordinary operation retries at the due time.
      log('Automatic endpoint freshness validation unresolved: $error');
      return current;
    }
  }

  Future<BigInt> getLatestBlockHeight() {
    if (!isAutomaticRpcEndpointConfig(state.primary)) {
      return _getLatestBlockHeight();
    }
    final pending = _automaticTipFlight;
    if (pending != null) return pending;
    late final Future<BigInt> read;
    read = _getLatestBlockHeight().whenComplete(() {
      if (identical(_automaticTipFlight, read)) _automaticTipFlight = null;
    });
    _automaticTipFlight = read;
    return read;
  }

  Future<BigInt> _getLatestBlockHeight() async {
    const operation = 'latest block height';
    await _ensureReadyForOperation(forTipRead: true);
    if (isAutomaticRpcEndpointConfig(state.primary) && _needsWarmTipRead) {
      await _ensureWarmTipRead();
    }
    await maybeProbePrimary();
    final endpoint = state.current;
    final operationEpoch = _automaticEpoch;
    final getLatestBlockHeight = ref.read(
      rpcEndpointFailoverLatestBlockHeightGetterProvider,
    );
    final stopwatch = Stopwatch()..start();
    final tor = ref.read(networkPrivacyProvider).torEnabled;

    try {
      final reuse = isAutomaticRpcEndpointConfig(state.primary)
          ? _takePendingAutomaticTip(endpoint)
          : null;
      final height =
          reuse?.height ??
          await getLatestBlockHeight(
            endpoint.normalizedLightwalletdUrl,
            endpoint.networkName,
          );
      if (!ref.mounted || operationEpoch != _automaticEpoch) return height;
      _recordEndpointSuccess(endpoint);
      if (reuse == null) {
        _recordAutomaticTipSuccess(
          endpoint,
          RpcEndpointCandidateSample(
            url: endpoint.normalizedLightwalletdUrl,
            height: height,
            latency: stopwatch.elapsed,
          ),
          operationEpoch,
          tor,
          ref.read(rpcEndpointFailoverClockProvider)(),
        );
      }
      _startProvisionalValidationIfDue();
      unawaited(
        _recordAutomaticResponse(endpoint, reuse?.latency ?? stopwatch.elapsed),
      );
      final slowFallback = await _maybeSwitchFromSlowHeight(
        endpoint,
        height,
        operation: operation,
      );
      return slowFallback?.height ?? height;
    } catch (e, st) {
      if (!ref.mounted || operationEpoch != _automaticEpoch) {
        Error.throwWithStackTrace(e, st);
      }
      final switched = await switchToFallbackFor(
        e,
        endpoint: endpoint,
        operation: operation,
      );
      if (!switched) {
        Error.throwWithStackTrace(e, st);
      }

      final fallbackEndpoint = state.current;
      final fallbackEpoch = _automaticEpoch;
      final fallbackTor = ref.read(networkPrivacyProvider).torEnabled;
      try {
        final replacementTip = isAutomaticRpcEndpointConfig(state.primary)
            ? _takePendingAutomaticTip(fallbackEndpoint)
            : null;
        final fallbackHeight =
            replacementTip?.height ??
            await getLatestBlockHeight(
              fallbackEndpoint.normalizedLightwalletdUrl,
              fallbackEndpoint.networkName,
            );
        if (!ref.mounted || fallbackEpoch != _automaticEpoch) {
          return fallbackHeight;
        }
        _recordEndpointSuccess(fallbackEndpoint);
        if (replacementTip == null) {
          _recordAutomaticTipSuccess(
            fallbackEndpoint,
            RpcEndpointCandidateSample(
              url: fallbackEndpoint.normalizedLightwalletdUrl,
              height: fallbackHeight,
              latency: stopwatch.elapsed,
            ),
            fallbackEpoch,
            fallbackTor,
            ref.read(rpcEndpointFailoverClockProvider)(),
          );
        }
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
    await ensureReady();
    await maybeProbePrimary();
    final endpoint = state.current;
    final operationEpoch = _automaticEpoch;
    try {
      final result = await action(endpoint);
      if (!ref.mounted || operationEpoch != _automaticEpoch) return result;
      _recordEndpointSuccess(endpoint);
      return result;
    } catch (e, st) {
      if (!ref.mounted || operationEpoch != _automaticEpoch) {
        Error.throwWithStackTrace(e, st);
      }
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
      final fallbackEpoch = _automaticEpoch;
      try {
        final result = await action(fallbackEndpoint);
        if (!ref.mounted || fallbackEpoch != _automaticEpoch) return result;
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
    final context = _captureContext();
    if (!shouldFallback(error)) return false;
    if (!_sameEndpointIdentity(attempted, context.current)) {
      // A performance recheck may already have selected B while an existing
      // sync is still finishing on A. Reuse B rather than recording an outage
      // or starting a second recovery; never cross a manual/custom preference.
      return isAutomaticRpcEndpointConfig(context.primary) &&
          state.automaticReady &&
          _selectionPauseCount == 0 &&
          !ref.read(appSecurityProvider).requiresUnlock &&
          canRunAppProcessWork(
            isInForeground: _inForeground,
            shutdownSignal: ref.read(appShutdownSignalProvider),
          ) &&
          automaticRpcEndpointCandidatesFor(
            context.primary,
          ).any((candidate) => _sameEndpointIdentity(candidate, attempted));
    }

    final attemptedUrl = attempted.normalizedLightwalletdUrl;
    if (isAutomaticRpcEndpointConfig(context.primary)) {
      _cooldowns[attemptedUrl] = ref
          .read(rpcEndpointFailoverClockProvider)()
          .add(ref.read(automaticRpcEndpointSettingsProvider).failureCooldown);
      if (!ref.mounted ||
          _selectionPauseCount > 0 ||
          ref.read(appSecurityProvider).requiresUnlock ||
          !canRunAppProcessWork(
            isInForeground: _inForeground,
            shutdownSignal: ref.read(appShutdownSignalProvider),
          )) {
        return false;
      }
      state = state.copyWith(automaticReady: false);
      _checkedAt = null;
      try {
        final selection = _ensureAutomatic(
          force: true,
          excludeUrl: attemptedUrl,
        );
        final selectionEpoch = _automaticEpoch;
        final selected = await selection;
        return ref.mounted &&
            context.generation == _configGeneration &&
            selectionEpoch == _automaticEpoch &&
            _sameEndpointIdentity(context.primary, state.primary) &&
            state.automaticReady &&
            _sameEndpointIdentity(selected, state.current) &&
            selected.normalizedLightwalletdUrl != attemptedUrl;
      } catch (selectionError) {
        log(
          'Automatic endpoint recovery failed after $operation: $selectionError',
        );
        return false;
      }
    }
    final failedPrimary = _sameEndpointIdentity(attempted, context.primary);
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

    final fallbackCandidates = context.fallbackCandidates
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
      if (!_isCurrentContext(context)) return false;
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

    if (!_isCurrentContext(context)) {
      log(
        'RpcEndpointFailover: ignored stale fallback result for '
        '${attempted.hostPort} after endpoint settings changed',
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
    if (isAutomaticRpcEndpointConfig(state.primary)) return false;
    if (!state.isUsingFallback) return false;

    final context = _captureContext();
    final primary = context.primary;
    final currentEndpoint = context.current;
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
      primaryHealth = await _checkHealth(primary);
    } catch (e) {
      log('RpcEndpointFailover: primary ${primary.hostPort} probe failed: $e');
      return false;
    }
    if (!_isCurrentContext(context)) {
      log(
        'RpcEndpointFailover: ignored stale primary probe for '
        '${primary.hostPort} after endpoint settings changed',
      );
      return false;
    }

    var currentHeight = state.lastObservedHeight;
    try {
      final currentHealth = await _checkHealth(currentEndpoint);
      if (!_isCurrentContext(context)) {
        log(
          'RpcEndpointFailover: ignored stale fallback probe for '
          '${currentEndpoint.hostPort} after endpoint settings changed',
        );
        return false;
      }
      currentHeight = _maxHeight(currentHeight, currentHealth.height);
      state = state.copyWith(
        lastObservedHeight: currentHeight,
        lastObservedAt: now,
      );
    } catch (e) {
      if (!_isCurrentContext(context)) return false;
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
        'RpcEndpointFailover: primary ${primary.hostPort} probe lagging '
        'at height ${primaryHealth.height}; current height is $currentHeight',
      );
      return false;
    }
    if (!_isCurrentContext(context)) return false;

    final event = RpcEndpointFailoverEvent(
      sequence: ++_eventSequence,
      kind: RpcEndpointFailoverEventKind.switchedToPrimary,
      message: 'Selected endpoint recovered. Switched back.',
      endpoint: primary,
    );
    log(
      'RpcEndpointFailover: primary ${primary.hostPort} recovered; '
      'leaving fallback ${currentEndpoint.hostPort}',
    );
    state = state.copyWith(
      current: primary,
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

    final context = _captureContext();
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

    if (isAutomaticRpcEndpointConfig(context.primary)) {
      try {
        final requiredHeight =
            height + BigInt.from(settings.slowFallbackLeadBlocks);
        final selection = _ensureAutomatic(
          force: true,
          minimumHeight: requiredHeight,
        );
        final selectionEpoch = _automaticEpoch;
        await selection;
        if (!ref.mounted ||
            selectionEpoch != _automaticEpoch ||
            context.generation != _configGeneration ||
            !state.automaticReady ||
            _isCurrentEndpoint(endpoint) ||
            state.lastObservedHeight! < requiredHeight) {
          return null;
        }
        return RpcEndpointHealth(
          chainName: state.current.networkName,
          height: state.lastObservedHeight!,
        );
      } catch (_) {
        if (_isCurrentContext(context)) {
          _resetHeightWindow(endpoint, height, now: now);
        }
        return null;
      }
    }
    final fallback = await _findFallbackAheadOf(
      endpoint,
      candidates: context.fallbackCandidates,
      currentHeight: height,
      operation: operation,
    );
    if (fallback == null) {
      if (!_isCurrentContext(context)) return null;
      log(
        'RpcEndpointFailover: ${endpoint.hostPort} height increased by '
        '$heightIncrease blocks in ${settings.slowHeightWindow.inSeconds}s, '
        'but no fallback endpoint is ahead enough; keeping current endpoint',
      );
      _resetHeightWindow(endpoint, height, now: now);
      return null;
    }

    if (!_isCurrentContext(context)) {
      log(
        'RpcEndpointFailover: ignored stale slow-height fallback for '
        '${endpoint.hostPort} after endpoint settings changed',
      );
      return null;
    }

    final failedPrimary = _sameEndpointIdentity(endpoint, context.primary);
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
    required List<RpcEndpointConfig> candidates,
    required BigInt currentHeight,
    required String operation,
  }) async {
    final settings = ref.read(rpcEndpointFailoverSettingsProvider);
    final requiredHeight =
        currentHeight + BigInt.from(settings.slowFallbackLeadBlocks);
    final attemptedUrl = attempted.normalizedLightwalletdUrl;
    for (final candidate in candidates) {
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

  Future<void> _recordAutomaticResponse(
    RpcEndpointConfig endpoint,
    Duration elapsed,
  ) async {
    if (!isAutomaticRpcEndpointConfig(state.primary) ||
        !_isCurrentEndpoint(endpoint)) {
      return;
    }
    final settings = ref.read(automaticRpcEndpointSettingsProvider);
    final tor = ref.read(networkPrivacyProvider).torEnabled;
    if (elapsed < (tor ? settings.slowTorResponse : settings.slowResponse)) {
      _slowResponses = 0;
      return;
    }
    if (++_slowResponses < 2) return;
    _slowResponses = 0;
    try {
      await _ensureAutomatic(force: true);
    } catch (_) {
      /* A slow success is still a success when alternatives fail. */
    }
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
    return _sameEndpointIdentity(endpoint, state.current);
  }

  _FailoverContext _captureContext() {
    return _FailoverContext(
      generation: _configGeneration,
      automaticEpoch: _automaticEpoch,
      primary: state.primary,
      current: state.current,
      fallbackCandidates: state.fallbackCandidates,
    );
  }

  bool _isCurrentContext(_FailoverContext context) {
    return _configGeneration == context.generation &&
        _automaticEpoch == context.automaticEpoch &&
        _sameEndpointIdentity(state.primary, context.primary) &&
        _sameEndpointIdentity(state.current, context.current);
  }

  bool _sameEndpointIdentity(RpcEndpointConfig a, RpcEndpointConfig b) {
    return a.networkName == b.networkName &&
        a.effectivePresetId == b.effectivePresetId &&
        a.normalizedLightwalletdUrl == b.normalizedLightwalletdUrl;
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

class _InitialEndpointImprovement {
  const _InitialEndpointImprovement({
    required this.context,
    required this.endpoint,
    required this.sample,
    required this.measuredAt,
    required this.tor,
  });

  final _FailoverContext context;
  final RpcEndpointConfig endpoint;
  final RpcEndpointCandidateSample sample;
  final DateTime measuredAt;
  final bool tor;
}

final rpcEndpointFailoverProvider =
    NotifierProvider<RpcEndpointFailoverNotifier, RpcEndpointFailoverState>(
      RpcEndpointFailoverNotifier.new,
    );
