import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_provider.dart';

const _displayTickDuration = Duration(milliseconds: 20);
const _preparationCeiling = 0.05;
const _scanCeiling = 0.99;
const _timeEstimateShare = 0.85;
const _timeEstimateSettleFactor = 6.0;

typedef _SyncDisplayTarget = ({
  bool isSyncing,
  bool isSyncComplete,
  double percentage,
  double targetPercentage,
  int targetBlocks,
  int checkingCycle,
  int phaseCompletedUnits,
  int phaseTotalUnits,
  String phase,
  DateTime? startedAt,
  DateTime? completedAt,
  String jobId,
});

_SyncDisplayTarget _displayTarget(AsyncValue<SyncState> value) {
  final sync = value.asData?.value ?? SyncState();
  return (
    isSyncing: sync.isSyncing,
    isSyncComplete: sync.isSyncComplete,
    percentage: sync.checking?.percentage ?? sync.percentage,
    targetPercentage:
        sync.checking?.displayTargetPercentage ?? sync.displayTargetPercentage,
    targetBlocks: sync.displayTargetBlocks,
    checkingCycle: sync.checking?.cycle ?? 0,
    phaseCompletedUnits: sync.phaseCompletedUnits,
    phaseTotalUnits: sync.phaseTotalUnits,
    phase: sync.isChecking ? 'checking' : sync.phase,
    startedAt: sync.lastSyncStartedAt,
    completedAt: sync.lastSyncCompletedAt,
    jobId: sync.syncJobId,
  );
}

/// UI-only sync progress interpolated between authoritative Rust events.
///
/// Preparation occupies a bounded 0-5% display range. Measurable preparation
/// work (currently active-account transparent UTXO batches) advances from real
/// committed work units, while indeterminate waits approach—but never reach—
/// their phase ceiling over time. Authoritative block progress is then mapped
/// into 5-99%; only a real completion event can produce 100%.
///
/// A display session restarts from zero only for a new sync job. A new
/// attempt of an unfinished job (Rust retry, endpoint fallback, relaunch)
/// keeps the value it reached and resumes from the job's stored percentage.
final syncDisplayPercentageProvider =
    NotifierProvider.autoDispose<SyncDisplayPercentageNotifier, double>(
      SyncDisplayPercentageNotifier.new,
    );

/// Whole percentage for labels that do not need frame-level progress.
final syncDisplayWholePercentageProvider = Provider.autoDispose<int>((ref) {
  final progress = ref.watch(syncDisplayPercentageProvider);
  return (progress.clamp(0.0, _scanCeiling) * 100).round();
});

/// Stage/queue changes only; never notified by the display interpolation timer.
/// The cycle is internal: a retry's discovered queue may reset Checking to a
/// lower fraction, while ordinary events retain the smooth predicted floor.
final syncDisplayCheckingCycleProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(
    syncProvider.select((value) {
      final sync = value.asData?.value;
      return sync?.isChecking == true ? sync!.checking!.cycle : 0;
    }),
  );
});

class SyncDisplayPercentageNotifier extends Notifier<double> {
  Timer? _timer;
  _SyncDisplayTarget? _target;
  DateTime? _sessionStartedAt;
  String _sessionJobId = '';
  bool _sessionCompleted = false;
  String _phase = '';
  int _checkingCycle = 0;
  Stopwatch? _phaseStopwatch;
  double _displayValue = 0;

  @override
  double build() {
    final input = ref.watch(syncProvider.select(_displayTarget));
    final isNewSession = _beginsNewSession(input);
    final isNewStage = input.isSyncing && input.checkingCycle != _checkingCycle;
    if (isNewSession || isNewStage) {
      _stopTimer();
      _displayValue = 0;
      _phase = '';
      _phaseStopwatch = null;
    }
    _trackSession(input, isNewSession: isNewSession);
    _target = input;
    _checkingCycle = input.checkingCycle;
    ref.onDispose(_stopTimer);
    Future<void>.microtask(() {
      if (ref.mounted && identical(_target, input)) _applyTarget(input);
    });
    final next = _initialValue(input);
    _displayValue = isNewSession || isNewStage
        ? next
        : math.max(_displayValue, next);
    return _displayValue;
  }

  /// Whether [input] starts a display session that restarts from zero.
  ///
  /// A new attempt continues the current session while it belongs to the
  /// same unfinished job, including before its first event names the job.
  /// A job Rust replaced (different id) always restarts.
  bool _beginsNewSession(_SyncDisplayTarget input) {
    if (!input.isSyncing) return false;
    // A sync that completed after the session's attempt started ended its
    // job, even when this notifier never saw the completed state.
    final sessionStartedAt = _sessionStartedAt;
    final sessionCompleted =
        _sessionCompleted ||
        (sessionStartedAt != null &&
            (input.completedAt?.isAfter(sessionStartedAt) ?? false));
    final hasSession = _sessionJobId.isNotEmpty && !sessionCompleted;
    final isNewAttempt =
        input.startedAt != null && input.startedAt != _sessionStartedAt;
    if (input.jobId.isNotEmpty && _sessionJobId.isNotEmpty) {
      if (input.jobId != _sessionJobId) return true;
      return isNewAttempt && sessionCompleted;
    }
    return isNewAttempt && !hasSession;
  }

  void _trackSession(_SyncDisplayTarget input, {required bool isNewSession}) {
    if (input.isSyncing && input.startedAt != _sessionStartedAt) {
      _sessionCompleted = false;
    }
    _sessionStartedAt = input.startedAt;
    if (isNewSession || input.jobId.isNotEmpty) _sessionJobId = input.jobId;
    if (input.isSyncComplete) _sessionCompleted = true;
  }

  double _initialValue(_SyncDisplayTarget input) {
    if (input.isSyncComplete) return 1;
    if (!input.isSyncing) return _resumedFloor(input);
    if (isSyncPreparationPhase(input.phase)) {
      final range = _preparationRange(input.phase);
      return math.max(
        _resumedFloor(input),
        math.max(range.floor, _measuredPreparation(input, range)),
      );
    }
    return _mappedScanPercentage(input.percentage, input.phase);
  }

  /// The scan-range value of a resumed job's stored percentage, so
  /// preparation of a later attempt does not show 0-5% again. Zero for a
  /// new job. Also the idle value, so starting a sync does not jump.
  double _resumedFloor(_SyncDisplayTarget input) {
    if (input.percentage <= 0) return 0;
    return _mappedScanPercentage(input.percentage, 'scan');
  }

  void _applyTarget(_SyncDisplayTarget input) {
    final isNewSession = _beginsNewSession(input);
    if (isNewSession) {
      _stopTimer();
      _publish(0);
      _phase = '';
      _phaseStopwatch = null;
    }
    _trackSession(input, isNewSession: isNewSession);
    _target = input;

    if (input.isSyncComplete) {
      _stopTimer();
      _publish(1);
      return;
    }
    if (!input.isSyncing) {
      // Between attempts of a job (stopped, failed, restarting) keep what
      // the session reached. Without a job (signed out, wallet reset) show
      // the plain value. Both use the scan-range mapping a sync resumes in.
      _stopTimer();
      final floor = _resumedFloor(input);
      _publish(input.jobId.isNotEmpty ? math.max(_displayValue, floor) : floor);
      return;
    }

    if (isSyncPreparationPhase(input.phase)) {
      _applyPreparationTarget(input);
    } else {
      _applyScanTarget(input);
    }
  }

  void _applyPreparationTarget(_SyncDisplayTarget input) {
    final range = _preparationRange(input.phase);
    if (_phase != input.phase) {
      _stopTimer();
      _phase = input.phase;
      _phaseStopwatch = Stopwatch()..start();
    }
    final measured = _measuredPreparation(input, range);
    _publish(
      math.max(
        math.max(_displayValue, _resumedFloor(input)),
        math.max(range.floor, measured),
      ),
    );
    final elapsedMs = _phaseStopwatch?.elapsedMilliseconds.toDouble() ?? 0;
    if (_timer == null &&
        _displayValue < range.ceiling &&
        !_timeEstimateHasSettled(elapsedMs, range)) {
      _timer = Timer.periodic(_displayTickDuration, (_) {
        final current = _target;
        if (!ref.mounted ||
            current == null ||
            !current.isSyncing ||
            current.phase != _phase) {
          _stopTimer();
          return;
        }
        final currentRange = _preparationRange(_phase);
        final elapsedMs = _phaseStopwatch?.elapsedMilliseconds.toDouble() ?? 0;
        final timeFraction =
            _timeEstimateShare *
            (1 - math.exp(-elapsedMs / currentRange.timeConstantMs));
        final temporal =
            currentRange.floor +
            (currentRange.ceiling - currentRange.floor) * timeFraction;
        final actual = _measuredPreparation(current, currentRange);
        final next = math.min(
          currentRange.ceiling,
          math.max(_displayValue, math.max(temporal, actual)),
        );
        if (next > _displayValue) _publish(next);
        if (_timeEstimateHasSettled(elapsedMs, currentRange)) {
          _stopTimer();
        }
      });
    }
  }

  void _applyScanTarget(_SyncDisplayTarget input) {
    _stopTimer();
    _phase = input.phase;
    _phaseStopwatch = null;
    final base = _mappedScanPercentage(input.percentage, input.phase);
    final target = _mappedScanPercentage(
      input.targetPercentage,
      input.phase,
    ).clamp(base, _scanCeiling).toDouble();
    _publish(math.max(_displayValue, base));
    if (input.targetBlocks <= 0 || target <= _displayValue) return;

    final start = _displayValue;
    _timer = Timer.periodic(_displayTickDuration, (timer) {
      if (!ref.mounted) {
        timer.cancel();
        return;
      }
      final virtualBlocks = math.min(timer.tick, input.targetBlocks);
      final next =
          start + ((target - start) * virtualBlocks / input.targetBlocks);
      if (next > _displayValue) _publish(next);
      if (virtualBlocks >= input.targetBlocks || next >= target) {
        _stopTimer();
      }
    });
  }

  double _mappedScanPercentage(double raw, String phase) {
    final clamped = raw.clamp(0.0, 1.0).toDouble();
    if (phase != 'download' && phase != 'scan') {
      return clamped.clamp(0.0, _scanCeiling).toDouble();
    }
    return (_preparationCeiling +
            (_scanCeiling - _preparationCeiling) * clamped)
        .clamp(_preparationCeiling, _scanCeiling)
        .toDouble();
  }

  double _measuredPreparation(
    _SyncDisplayTarget input,
    _PreparationRange range,
  ) {
    if (input.phaseTotalUnits <= 0) return range.floor;
    final fraction = (input.phaseCompletedUnits / input.phaseTotalUnits).clamp(
      0.0,
      1.0,
    );
    return range.floor + (range.ceiling - range.floor) * fraction;
  }

  _PreparationRange _preparationRange(String phase) {
    return switch (phase) {
      kSyncPhasePreflight => const _PreparationRange(0, 0.01, 400),
      kSyncPhaseSetup => const _PreparationRange(0.01, 0.02, 800),
      kSyncPhaseActiveUtxo => const _PreparationRange(0.02, 0.04, 1500),
      kSyncPhaseChainPrepare => const _PreparationRange(0.04, 0.05, 1000),
      _ => const _PreparationRange(0, 0, 1000),
    };
  }

  bool _timeEstimateHasSettled(double elapsedMs, _PreparationRange range) =>
      elapsedMs >= range.timeConstantMs * _timeEstimateSettleFactor;

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _publish(double next) {
    _displayValue = next;
    state = next;
  }
}

class _PreparationRange {
  final double floor;
  final double ceiling;
  final double timeConstantMs;

  const _PreparationRange(this.floor, this.ceiling, this.timeConstantMs);
}
