import 'dart:math';

import 'migration_demo_state.dart';

/// Builds a believable, staggered transfer schedule for the migration demo.
///
/// Transfer 1 "fires" immediately (offset 0); later transfers fire at random
/// points inside the window so the in-progress UI looks naturally spaced.
/// [now] and [random] are injected for deterministic tests.
MigrationDemoState buildMigrationDemoState({
  required String accountUuid,
  required BigInt displayAmountZatoshi,
  required List<String> txids,
  required DateTime now,
  required Random random,
  int totalDurationMs = MigrationDemoState.defaultDurationMs,
}) {
  final transferCount = max(1, txids.length);
  final offsets = _buildTransferOffsets(
    transferCount: transferCount,
    totalDurationMs: totalDurationMs,
    random: random,
  );

  return MigrationDemoState(
    accountUuid: accountUuid,
    startedAtEpochMs: now.millisecondsSinceEpoch,
    totalDurationMs: totalDurationMs,
    displayAmountZatoshi: displayAmountZatoshi,
    transferOffsetsMs: offsets,
    txids: txids,
  );
}

List<int> _buildTransferOffsets({
  required int transferCount,
  required int totalDurationMs,
  required Random random,
}) {
  if (transferCount <= 1) {
    return const [0];
  }

  if (transferCount == 2) {
    return [
      0,
      _randomInRange(
        random,
        (totalDurationMs * 0.25).round(),
        (totalDurationMs * 0.85).round(),
      ),
    ];
  }

  if (transferCount == 3) {
    final second = _randomInRange(
      random,
      (totalDurationMs * 0.15).round(),
      (totalDurationMs * 0.55).round(),
    );
    final third = _randomInRange(
      random,
      (totalDurationMs * 0.55).round(),
      (totalDurationMs * 0.92).round(),
    );

    return <int>[0, second, third]..sort();
  }

  final offsets = <int>[0];
  for (var index = 1; index < transferCount; index++) {
    final minMs = (totalDurationMs * index / transferCount).round();
    final maxMs = (totalDurationMs * (index + 1) / transferCount).round();
    offsets.add(_randomInRange(random, minMs, maxMs));
  }

  return offsets..sort();
}

int _randomInRange(Random random, int minMs, int maxMs) {
  final span = (maxMs - minMs).clamp(1, 1 << 31);
  return minMs + random.nextInt(span);
}
