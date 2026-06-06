import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../core/storage/wallet_paths.dart';
import '../rust/api/pir.dart' as rust_pir;
import 'rpc_endpoint_failover_provider.dart';

const _pirSpendUrlOverride = String.fromEnvironment(
  'ZCASH_PIR_SPEND_URL_OVERRIDE',
);
const _pirWitnessUrlOverride = String.fromEnvironment(
  'ZCASH_PIR_WITNESS_URL_OVERRIDE',
);

class PirSpendabilityState {
  const PirSpendabilityState({
    this.phase = '',
    this.completedCount = 0,
    this.totalCount = 0,
    this.witnessesInserted = 0,
    this.skippedReason,
    this.isRunning = false,
    this.lastError,
  });

  final String phase;
  final int completedCount;
  final int totalCount;
  final int witnessesInserted;
  final String? skippedReason;
  final bool isRunning;
  final String? lastError;

  PirSpendabilityState copyWith({
    String? phase,
    int? completedCount,
    int? totalCount,
    int? witnessesInserted,
    String? skippedReason,
    bool clearSkippedReason = false,
    bool? isRunning,
    String? lastError,
    bool clearLastError = false,
  }) {
    return PirSpendabilityState(
      phase: phase ?? this.phase,
      completedCount: completedCount ?? this.completedCount,
      totalCount: totalCount ?? this.totalCount,
      witnessesInserted: witnessesInserted ?? this.witnessesInserted,
      skippedReason: clearSkippedReason
          ? null
          : skippedReason ?? this.skippedReason,
      isRunning: isRunning ?? this.isRunning,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }
}

class PirSpendabilityNotifier extends AsyncNotifier<PirSpendabilityState> {
  static bool _ranThisLaunch = false;
  static const int _maxServerUnavailableRetries = 2;
  static const Duration _serverUnavailableRetryDelay = Duration(seconds: 15);

  StreamSubscription? _subscription;
  Completer<void>? _runCompleter;
  String? _lastLoggedPhase;
  int _serverUnavailableRetryCount = 0;
  bool _serverUnavailableRetryScheduled = false;

  @override
  Future<PirSpendabilityState> build() async {
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      rust_pir.cancelStartupPir();
    });
    return const PirSpendabilityState();
  }

  Future<void> run({bool forceRetry = false}) async {
    if (_ranThisLaunch && !forceRetry) {
      log('PIR: startup run already executed this launch; skipping');
      return;
    }
    if (rust_pir.isStartupPirRunning()) {
      log('PIR: startup run already in progress; skipping duplicate trigger');
      return;
    }
    _ranThisLaunch = true;
    _lastLoggedPhase = null;

    final endpoint = ref.read(rpcEndpointFailoverProvider).current;
    final dbPath = await getWalletDbPath();
    log(
      'PIR: startup trigger (network=${endpoint.networkName}, '
      'spendOverride=${_pirSpendUrlOverride.isNotEmpty}, '
      'witnessOverride=${_pirWitnessUrlOverride.isNotEmpty}, '
      'forceRetry=$forceRetry, '
      'retryCount=$_serverUnavailableRetryCount/$_maxServerUnavailableRetries)',
    );
    state = AsyncData(
      const PirSpendabilityState().copyWith(
        phase: 'starting',
        isRunning: true,
        clearSkippedReason: true,
        clearLastError: true,
      ),
    );

    final done = Completer<void>();
    _runCompleter = done;
    try {
      final stream = rust_pir.runStartupPir(
        dbPath: dbPath,
        network: endpoint.networkName,
        spendServerUrlOverride: _pirSpendUrlOverride,
        witnessServerUrlOverride: _pirWitnessUrlOverride,
      );
      _subscription = stream.listen(
        (event) {
          if (event.phase != _lastLoggedPhase || event.phase == 'skipped') {
            final skipped = event.skippedReason;
            final skippedSuffix = (skipped != null && skipped.isNotEmpty)
                ? ', skippedReason=$skipped'
                : '';
            log(
              'PIR: phase=${event.phase}, progress=${event.completed}/${event.total}, '
              'witnessesInserted=${event.witnessesInserted}$skippedSuffix',
            );
            _lastLoggedPhase = event.phase;
          }
          state = AsyncData(
            PirSpendabilityState(
              phase: event.phase,
              completedCount: event.completed,
              totalCount: event.total,
              witnessesInserted: event.witnessesInserted,
              skippedReason: event.skippedReason,
              isRunning: event.phase != 'done' && event.phase != 'skipped',
            ),
          );
        },
        onDone: () {
          final prev = state.value ?? const PirSpendabilityState();
          final skipped = prev.skippedReason;
          if (skipped != null && skipped.isNotEmpty) {
            log(
              'PIR: startup stream completed (skippedReason=$skipped, '
              'witnessesInserted=${prev.witnessesInserted})',
            );
          } else {
            log(
              'PIR: startup stream completed '
              '(witnessesInserted=${prev.witnessesInserted})',
            );
          }
          if (skipped == 'server_unavailable') {
            _scheduleServerUnavailableRetry();
          } else {
            _serverUnavailableRetryScheduled = false;
          }
          state = AsyncData(prev.copyWith(isRunning: false));
          if (!done.isCompleted) {
            done.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          log('PIR: startup stream error: $error\n$stackTrace');
          state = AsyncData(
            PirSpendabilityState(
              phase: 'error',
              isRunning: false,
              lastError: error.toString(),
            ),
          );
          if (!done.isCompleted) {
            done.complete();
          }
        },
        cancelOnError: true,
      );
      await done.future;
    } catch (error, stackTrace) {
      log('PIR: startup run failed: $error\n$stackTrace');
      state = AsyncData(
        PirSpendabilityState(
          phase: 'error',
          isRunning: false,
          lastError: error.toString(),
        ),
      );
    } finally {
      _subscription = null;
      if (identical(_runCompleter, done)) {
        _runCompleter = null;
      }
    }
  }

  Future<void> cancelAndWait({int timeoutMs = 5000}) async {
    rust_pir.cancelStartupPir();
    await _subscription?.cancel();
    _subscription = null;
    final completer = _runCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }

    var waited = 0;
    while (rust_pir.isStartupPirRunning() && waited < timeoutMs) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited += 100;
    }
    if (rust_pir.isStartupPirRunning()) {
      log('PIR: timed out waiting for startup PIR to stop after ${timeoutMs}ms');
    }

    final prev = state.value ?? const PirSpendabilityState();
    state = AsyncData(prev.copyWith(isRunning: false));
  }

  void _scheduleServerUnavailableRetry() {
    if (_serverUnavailableRetryCount >= _maxServerUnavailableRetries) {
      log(
        'PIR: server unavailable after '
        '$_serverUnavailableRetryCount retry attempts; giving up for this launch',
      );
      return;
    }
    if (_serverUnavailableRetryScheduled) {
      log('PIR: retry already scheduled; skipping duplicate schedule');
      return;
    }
    _serverUnavailableRetryScheduled = true;
    _serverUnavailableRetryCount += 1;
    final attempt = _serverUnavailableRetryCount;
    log(
      'PIR: scheduling retry $attempt/$_maxServerUnavailableRetries '
      'in ${_serverUnavailableRetryDelay.inSeconds}s',
    );
    Future<void>.delayed(_serverUnavailableRetryDelay, () {
      _serverUnavailableRetryScheduled = false;
      log('PIR: retrying startup after server_unavailable (attempt $attempt)');
      unawaited(run(forceRetry: true));
    });
  }
}

final pirSpendabilityProvider =
    AsyncNotifierProvider<PirSpendabilityNotifier, PirSpendabilityState>(
      () => PirSpendabilityNotifier(),
    );
