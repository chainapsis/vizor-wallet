import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_provider.dart';

const _displayTickDuration = Duration(milliseconds: 20);
const _scanCeiling = 0.99;

/// The least a scanning job shows. A whole-percent label rounds a new full
/// restore's first scan work to 0% for about its first minute; 1% from the
/// first scan event shows that preparation is over and scanning has begun.
const _scanFloor = 0.01;
const _checkingPhase = 'checking';

typedef _SyncDisplayTarget = ({
  bool isSyncing,
  bool isSyncComplete,
  double percentage,
  double targetPercentage,
  int targetBlocks,
  int checkingCycle,
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
    phase: sync.isChecking ? _checkingPhase : sync.phase,
    startedAt: sync.lastSyncStartedAt,
    completedAt: sync.lastSyncCompletedAt,
    jobId: sync.syncJobId,
  );
}

/// UI-only sync progress interpolated between authoritative Rust events.
///
/// The job's share of scan work is shown as 0-99%; only a real completion
/// event can produce 100%. Preparation adds nothing: a new job stays at 0%
/// and a resumed job holds its stored percentage. Once the job scans it shows
/// at least 1% (Checking keeps its own fraction).
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
  int _checkingCycle = 0;
  double _displayValue = 0;

  @override
  double build() {
    final input = ref.watch(syncProvider.select(_displayTarget));
    final isNewSession = _beginsNewSession(input);
    final isNewStage = input.isSyncing && input.checkingCycle != _checkingCycle;
    if (isNewSession || isNewStage) {
      _stopTimer();
      _displayValue = 0;
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
    return _scanBase(input);
  }

  /// The job's percentage, at least [_scanFloor] once Rust reports a scan
  /// phase.
  double _scanBase(_SyncDisplayTarget input) {
    final mapped = _mappedPercentage(input.percentage);
    final scanning =
        input.isSyncing &&
        input.phase.isNotEmpty &&
        !isSyncPreparationPhase(input.phase) &&
        input.phase != _checkingPhase;
    return scanning ? math.max(mapped, _scanFloor) : mapped;
  }

  /// A resumed job's stored percentage, held through preparation of a later
  /// attempt; zero for a new job. Also the idle value, so starting a sync
  /// does not jump.
  double _resumedFloor(_SyncDisplayTarget input) =>
      _mappedPercentage(input.percentage);

  void _applyTarget(_SyncDisplayTarget input) {
    final isNewSession = _beginsNewSession(input);
    if (isNewSession) {
      _stopTimer();
      _publish(0);
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
      // Preparation reports no scan work: hold what the job has reached.
      _stopTimer();
      _publish(math.max(_displayValue, _resumedFloor(input)));
    } else {
      _applyScanTarget(input);
    }
  }

  void _applyScanTarget(_SyncDisplayTarget input) {
    _stopTimer();
    final base = _scanBase(input);
    final target = _mappedPercentage(
      input.targetPercentage,
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

  double _mappedPercentage(double raw) =>
      raw.clamp(0.0, _scanCeiling).toDouble();

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _publish(double next) {
    _displayValue = next;
    state = next;
  }
}
