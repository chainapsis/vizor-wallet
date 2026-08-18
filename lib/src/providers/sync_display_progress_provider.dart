import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_provider.dart';

const _displayBlockDuration = Duration(milliseconds: 20);
const _maxIncompleteDisplayPercentage = 0.999;

typedef _SyncDisplayTarget = ({
  bool isSyncing,
  bool isSyncComplete,
  double percentage,
  double targetPercentage,
  int targetBlocks,
});

/// UI-only sync progress interpolated between authoritative Rust events.
///
/// Keeping the timer outside [SyncState] means its 20 ms updates reach only
/// widgets that explicitly render smooth progress. Wallet data, Home content,
/// and other sync consumers continue to update at Rust event boundaries.
final syncDisplayPercentageProvider =
    NotifierProvider.autoDispose<SyncDisplayPercentageNotifier, double>(
      SyncDisplayPercentageNotifier.new,
    );

/// Whole percentage for labels that do not need frame-level progress.
final syncDisplayWholePercentageProvider = Provider.autoDispose<int>((ref) {
  final progress = ref.watch(syncDisplayPercentageProvider);
  return (progress.clamp(0.0, 0.99) * 100).round();
});

class SyncDisplayPercentageNotifier extends Notifier<double> {
  Timer? _timer;

  @override
  double build() {
    final target = ref.watch(
      syncProvider.select((value) {
        final sync = value.asData?.value ?? SyncState();
        return (
          isSyncing: sync.isSyncing,
          isSyncComplete: sync.isSyncComplete,
          percentage: sync.percentage,
          targetPercentage: sync.displayTargetPercentage,
          targetBlocks: sync.displayTargetBlocks,
        );
      }),
    );

    _stopTimer();
    ref.onDispose(_stopTimer);
    return _startInterpolation(target);
  }

  double _startInterpolation(_SyncDisplayTarget input) {
    final base = input.isSyncComplete
        ? 1.0
        : input.percentage
              .clamp(0.0, _maxIncompleteDisplayPercentage)
              .toDouble();
    final target = input.isSyncing
        ? input.targetPercentage
              .clamp(base, _maxIncompleteDisplayPercentage)
              .toDouble()
        : base;
    if (input.targetBlocks <= 0 || target <= base) return base;

    _timer = Timer.periodic(_displayBlockDuration, (timer) {
      if (!ref.mounted) {
        timer.cancel();
        return;
      }
      final virtualBlocks = math.min(timer.tick, input.targetBlocks);
      final next =
          base + ((target - base) * virtualBlocks / input.targetBlocks);
      if (next > state) state = next;
      if (virtualBlocks >= input.targetBlocks || next >= target) {
        _stopTimer();
      }
    });
    return base;
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }
}
