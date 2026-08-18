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
  int phaseCompletedUnits,
  int phaseTotalUnits,
  String phase,
  DateTime? startedAt,
});

_SyncDisplayTarget _displayTarget(AsyncValue<SyncState> value) {
  final sync = value.asData?.value ?? SyncState();
  return (
    isSyncing: sync.isSyncing,
    isSyncComplete: sync.isSyncComplete,
    percentage: sync.percentage,
    targetPercentage: sync.displayTargetPercentage,
    targetBlocks: sync.displayTargetBlocks,
    phaseCompletedUnits: sync.phaseCompletedUnits,
    phaseTotalUnits: sync.phaseTotalUnits,
    phase: sync.phase,
    startedAt: sync.lastSyncStartedAt,
  );
}

/// UI-only sync progress interpolated between authoritative Rust events.
///
/// Preparation occupies a bounded 0-5% display range. Measurable preparation
/// work (currently active-account transparent UTXO batches) advances from real
/// committed work units, while indeterminate waits approach—but never reach—
/// their phase ceiling over time. Authoritative block progress is then mapped
/// into 5-99%; only a real completion event can produce 100%.
final syncDisplayPercentageProvider =
    NotifierProvider.autoDispose<SyncDisplayPercentageNotifier, double>(
      SyncDisplayPercentageNotifier.new,
    );

/// Whole percentage for labels that do not need frame-level progress.
final syncDisplayWholePercentageProvider = Provider.autoDispose<int>((ref) {
  final progress = ref.watch(syncDisplayPercentageProvider);
  return (progress.clamp(0.0, _scanCeiling) * 100).round();
});

class SyncDisplayPercentageNotifier extends Notifier<double> {
  Timer? _timer;
  _SyncDisplayTarget? _target;
  DateTime? _sessionStartedAt;
  String _phase = '';
  Stopwatch? _phaseStopwatch;
  double _displayValue = 0;

  @override
  double build() {
    final input = ref.watch(syncProvider.select(_displayTarget));
    final isNewSession =
        input.isSyncing &&
        input.startedAt != null &&
        input.startedAt != _sessionStartedAt;
    if (isNewSession) {
      _stopTimer();
      _displayValue = 0;
      _phase = '';
      _phaseStopwatch = null;
    }
    _target = input;
    _sessionStartedAt = input.startedAt;
    ref.onDispose(_stopTimer);
    Future<void>.microtask(() {
      if (ref.mounted && identical(_target, input)) _applyTarget(input);
    });
    final next = _initialValue(input);
    _displayValue = isNewSession ? next : math.max(_displayValue, next);
    return _displayValue;
  }

  double _initialValue(_SyncDisplayTarget input) {
    if (input.isSyncComplete) return 1;
    if (!input.isSyncing) {
      return input.percentage.clamp(0.0, _scanCeiling).toDouble();
    }
    if (isSyncPreparationPhase(input.phase)) {
      final range = _preparationRange(input.phase);
      return math.max(range.floor, _measuredPreparation(input, range));
    }
    return _mappedScanPercentage(input.percentage, input.phase);
  }

  void _applyTarget(_SyncDisplayTarget input) {
    final isNewSession =
        input.isSyncing &&
        input.startedAt != null &&
        input.startedAt != _sessionStartedAt;
    if (isNewSession) {
      _stopTimer();
      _publish(0);
      _phase = '';
      _phaseStopwatch = null;
      _sessionStartedAt = input.startedAt;
    }
    _target = input;

    if (input.isSyncComplete) {
      _stopTimer();
      _publish(1);
      return;
    }
    if (!input.isSyncing) {
      _stopTimer();
      _publish(input.percentage.clamp(0.0, _scanCeiling).toDouble());
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
    _publish(math.max(_displayValue, math.max(range.floor, measured)));
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
